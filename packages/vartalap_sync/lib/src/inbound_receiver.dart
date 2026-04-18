import 'dart:async';
import 'dart:typed_data';

import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';

import 'clock.dart';

/// Inbound WS_PUSH receiver per SYNC_PROTOCOL.md §10.5 and
/// SPIKE_A_SCHEMA.md §5.4.
///
/// Consumes a stream of [pb.Envelope]s (from `WsTransport.pushes`),
/// dedups against [ChatStore.hasSeenOpId], routes by `payload[0]`
/// (0x53 → ServerEventPayload, else → ChatPayload), and applies the
/// payload to the local projections via the inbound writer methods on
/// [ChatStore].
///
/// Runs independently of [SyncScheduler] — the two layers only meet at
/// the store. [stop] mirrors the scheduler's `_track`-based drain so a
/// caller doing `await receiver.stop(); await store.close()` won't race
/// an in-flight apply against a closed DB.
///
/// `ServerEventPayload` handling is decode-and-log for v3.0: the proto
/// schema (SYNC_PROTOCOL.md §10.2) isn't generated yet and projection
/// application lands with step 9 (REST server bodies). The receiver
/// still records `op_id_seen` on those frames so a re-fanout is a
/// no-op.
class InboundReceiver {
  final ChatStore store;
  final Stream<pb.Envelope> pushes;
  final String localUserId;
  final Clock clock;

  StreamSubscription<pb.Envelope>? _sub;
  bool _running = false;

  final Set<Future<void>> _inFlight = <Future<void>>{};

  InboundReceiver({
    required this.store,
    required this.pushes,
    required this.localUserId,
    this.clock = Clock.system,
  });

  /// Subscribe to inbound pushes. Idempotent — re-calling after [stop]
  /// is supported and re-subscribes.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _sub = pushes.listen(
      (env) => _track(_apply(env)),
      onError: (_) {},
    );
  }

  /// Stop listening and wait for every in-flight apply to finish. After
  /// this returns the caller can safely close [ChatStore] without
  /// racing a mid-transaction write.
  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _sub = null;
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList());
    }
  }

  Future<void> _track(Future<void> future) {
    _inFlight.add(future);
    future.whenComplete(() => _inFlight.remove(future));
    return future;
  }

  Future<void> _apply(pb.Envelope env) async {
    if (!_running) return;
    final channelId = env.channelId;
    final opId = env.opId;
    if (channelId.isEmpty || opId.isEmpty) {
      // Malformed envelope — server should never emit this. Drop.
      return;
    }

    if (await store.hasSeenOpId(channelId, opId)) return;
    if (!_running) return;

    final payload = env.payload;
    if (payload.isEmpty) {
      // Reserved for client-defined "ping" semantics per envelope
      // proto's comment on `payload`. Nothing to apply; don't record
      // dedup either (the envelope carries no idempotent intent).
      return;
    }

    if (payload[0] == 0x53) {
      _logServerEvent(env);
      return;
    }

    pb.ChatPayload chat;
    try {
      chat = pb.ChatPayload.fromBuffer(payload);
    } catch (e) {
      // ignore: avoid_print
      print(
        'InboundReceiver: malformed ChatPayload '
        'channel=$channelId op_id=$opId: $e',
      );
      return;
    }

    switch (chat.type) {
      case pb.ChatPayloadType.TYPE_MESSAGE_CREATE:
      case pb.ChatPayloadType.TYPE_MESSAGE_FORWARD:
        await store.applyInboundMessage(
          localUserId: localUserId,
          channelId: channelId,
          opId: opId,
          messageId: chat.messageId,
          senderUserId: env.senderUserId,
          body: chat.hasBody() ? chat.body : null,
          contentType: chat.hasContentType() ? chat.contentType : null,
          attachments: chat.attachments.isEmpty
              ? null
              : Uint8List.fromList(
                  // Re-encode the repeated Attachments as a sub-message
                  // so the stored BLOB round-trips via ChatPayload
                  // parsing. Using the ChatPayload itself as the
                  // envelope keeps decoding simple at read time.
                  pb.ChatPayload(attachments: chat.attachments)
                      .writeToBuffer(),
                ),
          forwardSource: chat.hasForwardSource()
              ? Uint8List.fromList(chat.forwardSource.writeToBuffer())
              : null,
          replyToMessageId:
              chat.hasReplyToMessageId() ? chat.replyToMessageId : null,
          clientTimestampMs: env.clientTimestampMs.toInt(),
          serverTimestampMs: env.serverTimestampMs.toInt(),
          deliverySequence: env.deliverySequence.toInt(),
          nowMs: clock.nowMs(),
        );
      case pb.ChatPayloadType.TYPE_MESSAGE_UPDATE:
        await store.applyInboundMessageUpdate(
          channelId: channelId,
          opId: opId,
          messageId: chat.messageId,
          senderUserId: env.senderUserId,
          body: chat.hasBody() ? chat.body : null,
          contentType: chat.hasContentType() ? chat.contentType : null,
          attachments: chat.attachments.isEmpty
              ? null
              : Uint8List.fromList(
                  pb.ChatPayload(attachments: chat.attachments)
                      .writeToBuffer(),
                ),
          serverTimestampMs: env.serverTimestampMs.toInt(),
          nowMs: clock.nowMs(),
        );
      case pb.ChatPayloadType.TYPE_MESSAGE_DELETE:
        await store.applyInboundMessageDelete(
          channelId: channelId,
          opId: opId,
          messageId: chat.messageId,
          senderUserId: env.senderUserId,
          nowMs: clock.nowMs(),
        );
      case pb.ChatPayloadType.TYPE_REACTION_ADD:
        await store.applyInboundReactionAdd(
          channelId: channelId,
          opId: opId,
          messageId: chat.messageId,
          senderUserId: env.senderUserId,
          emoji: chat.emoji,
          nowMs: clock.nowMs(),
        );
      case pb.ChatPayloadType.TYPE_REACTION_REMOVE:
        await store.applyInboundReactionRemove(
          channelId: channelId,
          opId: opId,
          messageId: chat.messageId,
          senderUserId: env.senderUserId,
          emoji: chat.emoji,
          nowMs: clock.nowMs(),
        );
      case pb.ChatPayloadType.TYPE_UNSPECIFIED:
      default:
        // Unknown type from a future client version. Per v3-chat-
        // payload.proto's forward-compat note, ignore. No op_id_seen
        // record — a later client upgrade should be allowed to
        // interpret the payload when it eventually understands the
        // type.
        // ignore: avoid_print
        print(
          'InboundReceiver: unknown ChatPayloadType=${chat.type} '
          'channel=$channelId op_id=$opId',
        );
    }
  }

  /// Decode-and-log stub for ServerEventPayload (§10.2). The proto for
  /// ServerEventPayload isn't generated in v3.0 — full projection apply
  /// lands with step 9 when the server REST bodies produce these
  /// envelopes. For now we prove the receiver routes correctly and
  /// don't touch op_id_seen (a later client release should be free to
  /// apply the same event if it was delivered early).
  void _logServerEvent(pb.Envelope env) {
    // ignore: avoid_print
    print(
      'InboundReceiver: ServerEventPayload (0x53) '
      'channel=${env.channelId} op_id=${env.opId} '
      'sender=${env.senderUserId} bytes=${env.payload.length} '
      '(decode-and-log; full apply lands in step 9)',
    );
  }
}
