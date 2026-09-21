import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ack.dart';
import 'asset_client.dart';
import 'auth_client.dart' show AuthClientException;
import 'rest_transport.dart' show classifyHttpStatus;
import 'transport.dart';

/// Third [Transport] adapter, for op kind `asset_upload`.
///
/// The op never reaches the chat server as an op: its "wire" is the
/// three-call media-ms dance (presign → signed PUT → status). Running
/// it through the scheduler rather than inline in the UI is what buys
/// attachments the same retry/backoff/dead-letter behaviour every other
/// outbound action has — an upload that fails on a train is a red
/// bubble with a Retry, not a lost photo.
///
/// The op payload is JSON:
/// `{path, ext, mime, size, category, ...caller-private fields}`.
/// [onUploaded] runs *before* the success ACK is emitted, so whatever
/// it enqueues (the MESSAGE_CREATE carrying the fileId, the profile
/// PATCH) is durable by the time the scheduler retires the upload op.
class AssetUploadTransport implements Transport {
  final AssetClient client;

  /// Availability is borrowed from [network] — usually the WS
  /// transport. media-ms is a different host in production, but "the
  /// chat socket is up" is a good enough proxy for "we have a network",
  /// and it keeps the scheduler from burning retry attempts offline.
  final Transport network;

  final Future<void> Function(String opId, String fileId) onUploaded;

  final _ackCtrl = StreamController<AckFrame>.broadcast();
  bool _disposed = false;

  /// op_ids with an upload in flight. Unlike a WS or REST op — which
  /// the server dedups by op_id (SYNC_PROTOCOL §7.1) — running an
  /// upload twice mints two fileIds and sends two messages, so a
  /// double dispatch has to be swallowed here. Cleared when the upload
  /// settles, so a genuine retry still runs.
  final Set<String> _uploading = {};

  AssetUploadTransport({
    required this.client,
    required this.network,
    required this.onUploaded,
  });

  @override
  Stream<AckFrame> get acks => _ackCtrl.stream;

  @override
  Stream<TransportState> get state => network.state;

  @override
  TransportState get currentState => network.currentState;

  Future<void> dispose() async {
    _disposed = true;
    if (!_ackCtrl.isClosed) await _ackCtrl.close();
  }

  @override
  Future<void> send(OutboundFrame frame) async {
    if (_disposed) throw StateError('AssetUploadTransport.send after dispose');
    if (frame.ops.length != 1) {
      throw StateError('AssetUploadTransport: one op per frame');
    }
    final op = frame.ops.single;
    final Map<String, dynamic> spec;
    try {
      spec = jsonDecode(utf8.decode(op.payload)) as Map<String, dynamic>;
    } catch (e) {
      throw StateError('AssetUploadTransport: payload not JSON: $e');
    }
    if (!_uploading.add(op.opId)) return;
    // Like RestTransport: the network round-trip is not awaited by the
    // scheduler; outcomes come back on `acks`.
    unawaited(_upload(op.opId, spec));
  }

  Future<void> _upload(String opId, Map<String, dynamic> spec) async {
    try {
      final file = File(spec['path'] as String);
      final bytes = await file.readAsBytes();
      final presigned = await client.presignUpload(
        ext: spec['ext'] as String,
        category: spec['category'] as String? ?? 'message',
        size: bytes.length,
      );
      await client.putBytes(
        url: presigned.url,
        bytes: bytes,
        contentType: spec['mime'] as String,
      );
      await client.markUploaded(presigned.fileId);
      await onUploaded(opId, presigned.fileId);
      _emit(opId, const AckSuccess());
    } on AuthClientException catch (e) {
      _emit(opId, classifyHttpStatus(e.statusCode, reason: e.errorCode));
    } on FileSystemException catch (e) {
      // The picked file is gone (temp dir swept, user deleted it).
      // Retrying cannot fix that, so fail it straight to the surface.
      _emit(opId, AckPermanentReject(reason: 'file_missing:${e.osError?.errorCode}'));
    } catch (e) {
      _emit(opId, AckTransientReject(reason: 'upload_error:${e.runtimeType}'));
    } finally {
      _uploading.remove(opId);
    }
  }

  void _emit(String opId, AckOutcome outcome) {
    if (!_ackCtrl.isClosed) {
      _ackCtrl.add(AckFrame(opId: opId, outcome: outcome));
    }
  }
}
