import 'dart:async';
import 'dart:typed_data';

import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';

import 'clock.dart';

/// One typing-indicator event observed on the inbound WS stream. Emitted
/// from `InboundReceiver.typingEvents` when an envelope marked
/// `ephemeral=true` carries a `ServerEventPayload{Typing}` body. Lossy
/// by design — recipients should treat absence as "not typing" and
/// expire any active indicator after a short TTL.
class TypingEvent {
  final String channelId;
  final String userId;
  final bool isTyping;
  final int emittedAtMs;

  const TypingEvent({
    required this.channelId,
    required this.userId,
    required this.isTyping,
    required this.emittedAtMs,
  });
}

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
/// `ServerEventPayload` handling (SYNC_PROTOCOL.md §10.2) covers the
/// v3.0 channel/membership lifecycle: CHANNEL_CREATED,
/// CHANNEL_MEMBER_ADDED, CHANNEL_MEMBER_REMOVED. The remaining four
/// variants (CHANNEL_EDITED / CHANNEL_DELETED / PROFILE_EDITED /
/// USERNAME_CHANGED) fall through to [_logServerEventFallback] until
/// their projections land — `op_id_seen` is intentionally NOT recorded
/// for those so a later client release can apply them on re-fanout.
class InboundReceiver {
  final ChatStore store;
  final Stream<pb.Envelope> pushes;
  final String localUserId;
  final Clock clock;

  StreamSubscription<pb.Envelope>? _sub;
  bool _running = false;

  final Set<Future<void>> _inFlight = <Future<void>>{};

  /// Ephemeral typing-event fanout. Broadcast so multiple chat screens
  /// can subscribe; never replayed because typing is intentionally lossy
  /// (see Typing proto contract).
  final StreamController<TypingEvent> _typingCtrl =
      StreamController<TypingEvent>.broadcast();

  /// Subscribers (e.g. open chat screens) filter by `channelId` + ignore
  /// own-user events.
  Stream<TypingEvent> get typingEvents => _typingCtrl.stream;

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
    if (!_typingCtrl.isClosed) await _typingCtrl.close();
  }

  Future<void> _track(Future<void> future) {
    _inFlight.add(future);
    future.whenComplete(() => _inFlight.remove(future));
    return future;
  }

  /// Wait for every currently-tracked apply to finish. Unlike [stop],
  /// keeps the subscription live — the receiver keeps consuming new
  /// frames after this returns. Used by the client-triggered sync pull
  /// to gate "WS buffer flush" on "pulled events fully applied" so a
  /// live message that depends on a pulled `ChannelCreated` never
  /// races ahead of it.
  Future<void> drainPending() async {
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList());
    }
  }

  Future<void> _apply(pb.Envelope env) async {
    if (!_running) return;
    final channelId = env.channelId;
    final opId = env.opId;
    if (channelId.isEmpty || opId.isEmpty) {
      // Malformed envelope — server should never emit this. Drop.
      return;
    }

    final payload = env.payload;
    if (payload.isEmpty) {
      // Reserved for client-defined "ping" semantics per envelope
      // proto's comment on `payload`. Nothing to apply; don't record
      // dedup either (the envelope carries no idempotent intent).
      return;
    }

    // Ephemeral envelopes (typing, future presence) bypass dedup, the
    // op_id_seen table, and projection writes entirely. We decode the
    // 0x53 ServerEventPayload directly and emit on the side-channel.
    if (env.ephemeral) {
      if (payload[0] != 0x53) return; // unknown ephemeral shape
      _handleEphemeral(env, payload.sublist(1));
      return;
    }

    if (await store.hasSeenOpId(channelId, opId)) return;
    if (!_running) return;

    if (payload[0] == 0x53) {
      // §10.2 wire distinguisher: server PREPENDS 0x53; strip before
      // proto decode (the proto's natural first byte is the tag for
      // `version`, 0x08 — never 0x53).
      await _handleServerEvent(env, payload.sublist(1));
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

  /// §10.2 dispatcher. Decodes the proto-bytes-without-distinguisher
  /// and routes by `whichBody()`. Channel + membership lifecycle is
  /// applied here; the remaining variants fall through to a log stub
  /// (no `op_id_seen` so later clients can apply on re-fanout).
  Future<void> _handleServerEvent(pb.Envelope env, List<int> bytes) async {
    pb.ServerEventPayload sep;
    try {
      sep = pb.ServerEventPayload.fromBuffer(bytes);
    } catch (e) {
      // ignore: avoid_print
      print(
        'InboundReceiver: malformed ServerEventPayload '
        'channel=${env.channelId} op_id=${env.opId}: $e',
      );
      return;
    }
    switch (sep.whichBody()) {
      case pb.ServerEventPayload_Body.channelCreated:
        await _handleChannelCreated(env, sep.channelCreated);
      case pb.ServerEventPayload_Body.memberAdded:
        await _handleChannelMemberAdded(env, sep.memberAdded);
      case pb.ServerEventPayload_Body.memberRemoved:
        await _handleChannelMemberRemoved(env, sep.memberRemoved);
      case pb.ServerEventPayload_Body.messageStateChanged:
        await _handleMessageStateChanged(env, sep.messageStateChanged);
      case pb.ServerEventPayload_Body.profileEdited:
        await _handleProfileEdited(env, sep.profileEdited);
      case pb.ServerEventPayload_Body.usernameChanged:
        await _handleUsernameChanged(env, sep.usernameChanged);
      // TODO(v3.x): wire ChannelEdited / ChannelDeleted. Falling through
      // to log keeps op_id_seen empty so a later client release applies
      // on re-fanout.
      case pb.ServerEventPayload_Body.channelEdited:
      case pb.ServerEventPayload_Body.channelDeleted:
      case pb.ServerEventPayload_Body.typing:
        // Typing should never arrive on the persistent path — it's
        // routed via the ephemeral flag. If we see it here a peer/server
        // didn't set the flag; treat as no-op rather than persisting.
      case pb.ServerEventPayload_Body.notSet:
        _logServerEventFallback(env, sep);
    }
  }

  /// Decode and re-emit an ephemeral ServerEventPayload. The only
  /// variant routed today is [pb.Typing]; anything else is a no-op
  /// (forward-compat for future presence/reactions-bursts).
  void _handleEphemeral(pb.Envelope env, List<int> bytes) {
    pb.ServerEventPayload sep;
    try {
      sep = pb.ServerEventPayload.fromBuffer(bytes);
    } catch (_) {
      return;
    }
    if (sep.whichBody() != pb.ServerEventPayload_Body.typing) return;
    if (_typingCtrl.isClosed) return;
    _typingCtrl.add(TypingEvent(
      channelId: env.channelId,
      userId: env.senderUserId,
      isTyping: sep.typing.isTyping,
      emittedAtMs: env.clientTimestampMs.toInt(),
    ));
  }

  /// §10.2 MessageStateChanged. Flip the local row's `message_state`
  /// (sent → delivered → read). [ChatStore.applyMessageStateChange]
  /// drops stale events on its own; we still record `op_id_seen` here
  /// so the server-side dedup invariant holds.
  Future<void> _handleMessageStateChanged(
    pb.Envelope env,
    pb.MessageStateChanged body,
  ) async {
    final mapped = _messageStateFromWire(body.newState);
    bool applied = false;
    if (mapped != null) {
      applied = await store.applyMessageStateChange(
        messageId: body.messageId,
        newState: mapped,
        changedAtMs: body.changedAtMs.toInt(),
      );
    }
    // ignore: avoid_print
    print('InboundReceiver: MessageStateChanged '
        'channel=${env.channelId} message=${body.messageId} '
        'newState=${body.newState.name} mapped=$mapped applied=$applied');
    await store.db.insert('op_id_seen', {
      'channel_id': env.channelId,
      'op_id': env.opId,
      'seen_at': clock.nowMs(),
    });
  }

  /// §10.2 ProfileEdited. Sparse update — each proto3-`optional` field
  /// is forwarded as a present/absent record so the store can
  /// distinguish "not in this edit" (absent) from "user cleared this
  /// field" (present-empty). The sender's user_id can be anyone in a
  /// channel we share, so the contact row may not exist yet — the
  /// store creates it lazily.
  Future<void> _handleProfileEdited(
    pb.Envelope env,
    pb.ProfileEdited body,
  ) async {
    final userId = body.userId;
    if (userId.isEmpty) return;
    await store.applyProfileEdit(
      userId: userId,
      displayName: body.hasDisplayName()
          ? (value: body.displayName.isEmpty ? null : body.displayName)
          : null,
      avatarUrl: body.hasAvatarUrl()
          ? (value: body.avatarUrl.isEmpty ? null : body.avatarUrl)
          : null,
      statusText: body.hasStatusText()
          ? (value: body.statusText.isEmpty ? null : body.statusText)
          : null,
      nowMs: clock.nowMs(),
    );
    await store.db.insert('op_id_seen', {
      'channel_id': env.channelId,
      'op_id': env.opId,
      'seen_at': clock.nowMs(),
    });
  }

  /// §10.2 UsernameChanged. Empty `new_username` means the user
  /// cleared their handle — store layer treats it as NULL.
  Future<void> _handleUsernameChanged(
    pb.Envelope env,
    pb.UsernameChanged body,
  ) async {
    final userId = body.userId;
    if (userId.isEmpty) return;
    await store.applyUsernameChange(
      userId: userId,
      newUsername: body.newUsername,
      nowMs: clock.nowMs(),
    );
    await store.db.insert('op_id_seen', {
      'channel_id': env.channelId,
      'op_id': env.opId,
      'seen_at': clock.nowMs(),
    });
  }

  static MessageState? _messageStateFromWire(pb.MessageStateValue v) {
    switch (v) {
      case pb.MessageStateValue.MESSAGE_STATE_DELIVERED:
        return MessageState.delivered;
      case pb.MessageStateValue.MESSAGE_STATE_READ:
        return MessageState.read;
      case pb.MessageStateValue.MESSAGE_STATE_REJECTED:
        return MessageState.rejected;
      default:
        return null;
    }
  }

  /// §10.2 ChannelCreated. Materialize the channel + member roster on
  /// every recipient (creator included per the e0e6bfe contract).
  Future<void> _handleChannelCreated(
    pb.Envelope env,
    pb.ChannelCreated body,
  ) async {
    final nowMs = clock.nowMs();
    final existing = await store.db.query(
      'channels',
      columns: const ['channel_id'],
      where: 'channel_id = ?',
      whereArgs: [body.channelId],
      limit: 1,
    );
    if (existing.isEmpty) {
      final createdAt = body.createdAtMs.toInt();
      await store.insertChannel(
        channelId: body.channelId,
        kind: body.kind,
        ownerUserId: body.creator,
        createdAt: createdAt,
        name: body.name.isEmpty ? null : body.name,
      );
      for (final userId in body.members) {
        await store.insertChannelMember(
          channelId: body.channelId,
          userId: userId,
          role: userId == body.creator ? 'owner' : 'member',
          joinedAt: createdAt,
        );
      }
    }
    // §7.2 — record op_id_seen even on the creator-echo skip path so a
    // re-fanout doesn't re-evaluate.
    await store.db.insert('op_id_seen', {
      'channel_id': env.channelId,
      'op_id': env.opId,
      'seen_at': nowMs,
    });
  }

  /// §10.2 ChannelMemberAdded. Out-of-order delivery (channel not yet
  /// local) is dropped silently but op_id_seen is still recorded — the
  /// dedup table is the source of truth for "have I processed this op."
  Future<void> _handleChannelMemberAdded(
    pb.Envelope env,
    pb.ChannelMemberAdded body,
  ) async {
    final nowMs = clock.nowMs();
    final existing = await store.db.query(
      'channels',
      columns: const ['channel_id'],
      where: 'channel_id = ?',
      whereArgs: [body.channelId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final addedAt = body.addedAtMs.toInt();
      for (final userId in body.members) {
        await store.insertChannelMember(
          channelId: body.channelId,
          userId: userId,
          role: 'member',
          joinedAt: addedAt,
        );
      }
    }
    await store.db.insert('op_id_seen', {
      'channel_id': env.channelId,
      'op_id': env.opId,
      'seen_at': nowMs,
    });
  }

  /// §10.2 ChannelMemberRemoved. Soft-deletes the row; if the local user
  /// was the one removed, also tombstone the channel locally so it falls
  /// off the chat list (the user has been kicked).
  Future<void> _handleChannelMemberRemoved(
    pb.Envelope env,
    pb.ChannelMemberRemoved body,
  ) async {
    final nowMs = clock.nowMs();
    final existing = await store.db.query(
      'channels',
      columns: const ['channel_id'],
      where: 'channel_id = ?',
      whereArgs: [body.channelId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await store.removeChannelMember(
        channelId: body.channelId,
        userId: body.member,
        removedAtMs: body.removedAtMs.toInt(),
      );
      if (body.member == localUserId) {
        await store.tombstoneChannel(body.channelId);
      }
    }
    await store.db.insert('op_id_seen', {
      'channel_id': env.channelId,
      'op_id': env.opId,
      'seen_at': nowMs,
    });
  }

  /// Fallback log for ServerEventPayload variants we don't yet apply.
  /// op_id_seen is deliberately NOT recorded — see class docstring.
  void _logServerEventFallback(
    pb.Envelope env,
    pb.ServerEventPayload sep,
  ) {
    // ignore: avoid_print
    print(
      'InboundReceiver: deferred ServerEventPayload variant=${sep.whichBody()} '
      'channel=${env.channelId} op_id=${env.opId} '
      '(op_id_seen NOT recorded; later release will apply)',
    );
  }
}
