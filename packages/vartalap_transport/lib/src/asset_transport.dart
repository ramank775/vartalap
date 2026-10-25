import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  /// [key]: the attachment's key, for a sealed upload.
  final Future<void> Function(String opId, String fileId, Uint8List? key)
      onUploaded;

  /// End-to-end encryption (decisions 188, 190) for a spec with `seal`:
  /// the file's key, its sealed bytes and their MD5. The same file seals to
  /// the same bytes, so an upload the server already holds is skipped; the
  /// MD5 is signed into the upload url and the store checks the body.
  /// Set by the app; unset, such a spec is refused rather than uploaded in
  /// the clear.
  final Future<({Uint8List key, Uint8List sealed, Uint8List md5})> Function(
      Uint8List plain)? seal;

  final _ackCtrl = StreamController<AckFrame>.broadcast();
  bool _disposed = false;

  AssetUploadTransport({
    required this.client,
    required this.network,
    required this.onUploaded,
    this.seal,
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
    // No same-op_id dedup guard here: SyncScheduler._dispatchOnce is now
    // single-flight (decision 59 / DECISIONS.md), so it can never hand
    // this transport the same op_id twice before the first upload
    // settles. Unlike RestTransport/WsTransport, that guarantee matters
    // here specifically because a second upload of the same op would
    // mint a second fileId and send a second message — the server has
    // nothing to dedup against.
    //
    // Like RestTransport: the network round-trip is not awaited by the
    // scheduler; outcomes come back on `acks`.
    unawaited(_upload(op.opId, spec));
  }

  Future<void> _upload(String opId, Map<String, dynamic> spec) async {
    try {
      final file = File(spec['path'] as String);
      // `key` marks a spec queued before decision 190: sealed all the same.
      final sealIt = spec['seal'] == true || spec['key'] != null;
      var bytes = await file.readAsBytes();
      Uint8List? key;
      Uint8List? md5;
      if (sealIt) {
        final seal = this.seal;
        if (seal == null) throw StateError('No attachment sealer');
        final sealed = await seal(bytes);
        (key, bytes, md5) = (sealed.key, sealed.sealed, sealed.md5);
      }
      final presigned = await client.presignUpload(
        // Ciphertext is opaque bytes to the server and the bucket.
        ext: sealIt ? 'bin' : spec['ext'] as String,
        category: spec['category'] as String? ?? 'message',
        size: bytes.length,
        md5: md5 == null
            ? null
            : [for (final b in md5) b.toRadixString(16).padLeft(2, '0')].join(),
      );
      if (!presigned.existing) {
        await client.putBytes(
          url: presigned.url,
          bytes: bytes,
          // The server's type, not ours: they disagree on anything its
          // table lacks, and a mismatch fails the signature.
          contentType: presigned.contentType ??
              (sealIt ? 'application/octet-stream' : spec['mime'] as String),
          contentMd5: md5 == null ? null : base64.encode(md5),
        );
        await client.markUploaded(presigned.fileId);
      }
      await onUploaded(opId, presigned.fileId, key);
      _emit(opId, const AckSuccess());
    } on AuthClientException catch (e) {
      _emit(opId, classifyHttpStatus(e.statusCode, reason: e.errorCode));
    } on FileSystemException catch (e) {
      // The picked file is gone (temp dir swept, user deleted it).
      // Retrying cannot fix that, so fail it straight to the surface.
      _emit(opId, AckPermanentReject(reason: 'file_missing:${e.osError?.errorCode}'));
    } catch (e) {
      _emit(opId, AckTransientReject(reason: 'upload_error:${e.runtimeType}'));
    }
  }

  void _emit(String opId, AckOutcome outcome) {
    if (!_ackCtrl.isClosed) {
      _ackCtrl.add(AckFrame(opId: opId, outcome: outcome));
    }
  }
}
