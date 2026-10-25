import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';

import 'clock.dart';
import 'dm_channel_id.dart';

/// Public-profile fields needed to backfill a `contacts` row for a peer
/// we've never discovered (decision 79) — a subset of `GET
/// /v3.0/users/{user_id}`'s response, kept minimal so this pure-Dart
/// package doesn't need `vartalap_transport`'s JSON shape.
class ContactProfile {
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  const ContactProfile({this.username, this.displayName, this.avatarUrl});
}

/// A group as `GET /v3.0/channels[/{id}]` describes it: every member
/// mapped to `owner`, `admin` or `member`.
typedef GroupRoster = ({
  String? name,
  String? avatarUrl,
  Map<String, String> roles,
  int createdAt,
});

/// One element of `GET /v3.0/channels` as a [GroupRoster]. A server
/// from before `roles` (decision 150) lists members only: all plain
/// members, until role events say otherwise.
GroupRoster groupRosterFromJson(Map<String, dynamic> json) => (
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      roles: {
        for (final id in (json['members'] as List? ?? const []).cast<String>())
          id: 'member',
        ...?(json['roles'] as Map?)?.cast<String, String>(),
      },
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );

/// One typing-indicator event observed on the inbound WS stream. Emitted
/// from `InboundReceiver.typingEvents` when an envelope marked
/// `ephemeral=true` carries a `ChatPayload{TYPE_TYPING}` body (decision
/// 56) — or a server-authored `ServerEventPayload{Typing}`, which stays
/// decodable in case the gateway ever emits one. Lossy by design —
/// recipients should treat absence as "not typing" and expire any
/// active indicator after a short TTL.
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
/// v3.0 channel/membership lifecycle (CHANNEL_CREATED,
/// CHANNEL_MEMBER_ADDED, CHANNEL_MEMBER_REMOVED, CHANNEL_EDITED,
/// CHANNEL_DELETED) and the user-profile fanout (PROFILE_EDITED,
/// USERNAME_CHANGED). Any remaining unhandled variants fall through to
/// [_logServerEventFallback] — `op_id_seen` is intentionally NOT
/// recorded for those so a later client release can apply them on
/// re-fanout.
/// What [InboundReceiver.open] hands back (decision 188).
typedef OpenedPayload = ({List<int> payload, String retryOf});

class InboundReceiver {
  final ChatStore store;
  final Stream<pb.Envelope> pushes;
  final String localUserId;
  final Clock clock;

  /// Fetches a peer's public profile (`GET /v3.0/users/{user_id}`) for
  /// the decision-79 "stranger DM" backfill — injected so this pure-Dart
  /// package never depends on `vartalap_transport`. `null` disables the
  /// backfill (e.g. in tests that don't care about it).
  final Future<ContactProfile?> Function(String userId)? resolveProfile;

  /// Fetches a group this device has no row for (`GET
  /// /v3.0/channels/{id}`): one we were added to after it was created
  /// has no `ChannelCreated` to build it from. Injected for the same
  /// reason as [resolveProfile]; `null` drops such frames as before.
  final Future<GroupRoster?> Function(String channelId)? resolveGroup;

  /// End-to-end encryption (decision 188): the ChatPayload bytes sealed in
  /// a client envelope, and the op it re-sends ('' for none). An empty
  /// payload is a control frame the crypto took (a group key, a re-send
  /// request); null is an op that will never open here, which becomes a
  /// "Waiting for this message" row and an [undecryptable] call. A throw
  /// (the database) leaves the frame unhandled, the pull pointer before
  /// it. Unset: payloads are read as they are.
  final Future<OpenedPayload?> Function(pb.Envelope env)? open;

  /// After an undecryptable op's placeholder is stored: ask its sender to
  /// re-send it.
  final Future<void> Function(pb.Envelope env)? undecryptable;

  /// After a stored op applied, so [open] can drop what it staged for it.
  final Future<void> Function(pb.Envelope env)? applied;

  StreamSubscription<pb.Envelope>? _sub;
  bool _running = false;

  final Set<Future<void>> _inFlight = <Future<void>>{};

  /// user_ids with a [resolveProfile] call currently in flight — a
  /// synchronous `add`/`remove` guard so a channel event that repeats
  /// the same unknown member (ChannelCreated then MemberAdded in quick
  /// succession) never fires a second fetch for it.
  final Set<String> _profileFetchInFlight = <String>{};

  /// Applies run one at a time, in arrival order. Two frames delivered
  /// in the same microtask batch would otherwise both clear the
  /// `hasSeenOpId` check before either wrote `op_id_seen`, and the
  /// loser blew up on the UNIQUE constraint — losing the apply. Serial
  /// also means a live message can never overtake the
  /// `ChannelCreated` it depends on.
  Future<void> _chain = Future<void>.value();

  /// Ephemeral typing-event fanout. Broadcast so multiple chat screens
  /// can subscribe; never replayed because typing is intentionally lossy
  /// (see Typing proto contract).
  final StreamController<TypingEvent> _typingCtrl =
      StreamController<TypingEvent>.broadcast();

  /// Subscribers (e.g. open chat screens) filter by `channelId` + ignore
  /// own-user events.
  Stream<TypingEvent> get typingEvents => _typingCtrl.stream;

  final StreamController<String> _peerMessageCtrl =
      StreamController<String>.broadcast();

  /// Channel ids that just stored a message from someone else. ChatService
  /// turns bursts of these into one TYPE_DELIVERY_RECEIPT per channel.
  Stream<String> get peerMessagesStored => _peerMessageCtrl.stream;

  /// Synchronous so a listener has every op_id before [drainPending]
  /// returns: the sync pull checks its page right after it.
  final StreamController<String> _handledCtrl =
      StreamController<String>.broadcast(sync: true);

  /// §10.6 — op_ids of the non-ephemeral envelopes this receiver has
  /// handled: stored, already seen, or dropped on purpose. Nothing is
  /// emitted for an apply that threw. The sync pull reads it to tell
  /// whether its whole page went in.
  Stream<String> get handled => _handledCtrl.stream;

  /// §10.6 — the pull pointer: the newest `server_timestamp_ms` among
  /// the envelopes handled, kept in the account's store, the next
  /// pull's `since`. Loaded by [start].
  int get syncPointer => _syncPointer;
  int _syncPointer = 0;

  /// While held, a handled frame does not move [syncPointer] on its own:
  /// something before it may be missing — a frame that failed, or what
  /// a pull still running has yet to bring. Only a pull that got
  /// through every page releases it ([advanceSyncPointer]); until the
  /// first one, nothing is known, so it starts held.
  bool _pointerHeld = true;

  /// Bumped by every hold, so a pull can tell whether one landed while
  /// it ran.
  int _holds = 0;

  InboundReceiver({
    required this.store,
    required this.pushes,
    required this.localUserId,
    this.clock = Clock.system,
    this.resolveProfile,
    this.resolveGroup,
    this.open,
    this.applied,
    this.undecryptable,
  });

  /// Subscribe to inbound pushes. Idempotent — re-calling after [stop]
  /// is supported and re-subscribes.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _syncPointer = await store.syncPointer();
    _sub = pushes.listen(
      (env) => _track(_chain = _chain.then((_) async {
            await _apply(env);
            // Not running: [stop] landed mid-apply, which returns early
            // without storing. Ephemeral envelopes are never stored
            // server-side, so no pull would bring them.
            if (!_running || env.ephemeral) return;
            if (env.opId.isNotEmpty && !_handledCtrl.isClosed) {
              _handledCtrl.add(env.opId);
            }
            if (!_pointerHeld) {
              await _moveSyncPointer(env.serverTimestampMs.toInt());
            }
          }).catchError(
            (Object e) {
              // Keep the chain alive: one bad frame must not stop every
              // later one from applying. It does stop the pointer, so
              // the next pull from there brings this frame back.
              holdSyncPointer();
              // ignore: avoid_print
              print('InboundReceiver: apply failed '
                  'channel=${env.channelId} op_id=${env.opId}: $e');
            },
          )),
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
    if (!_peerMessageCtrl.isClosed) await _peerMessageCtrl.close();
    if (!_handledCtrl.isClosed) await _handledCtrl.close();
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
    // A frame just added to [pushes] reaches the listener in a later
    // microtask, so it is not tracked yet: let those deliveries run
    // first, or a pull that has just injected its page finds nothing
    // to wait for.
    await Future<void>(() {});
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList());
    }
  }

  /// Stop single frames moving [syncPointer] until a pull has caught up
  /// ([advanceSyncPointer] with the returned token).
  int holdSyncPointer() {
    _pointerHeld = true;
    return ++_holds;
  }

  /// A pull handled every frame of a page, up to [ms]: move
  /// [syncPointer] there. With [release], the [holdSyncPointer] token
  /// the pull took when it began — passed on its last page — single
  /// frames move it again, unless something held it since. Queued
  /// behind the frames already arriving, like every apply.
  Future<void> advanceSyncPointer(int ms, {int? release}) => _track(
        _chain = _chain.then((_) async {
          if (!_running) return;
          await _moveSyncPointer(ms);
          if (release == _holds) _pointerHeld = false;
        }).catchError((Object e) {
          // ignore: avoid_print
          print('InboundReceiver: advanceSyncPointer failed: $e');
        }),
      );

  /// Never backwards: an envelope stamped earlier than one already
  /// handled leaves it alone.
  /// ponytail: one small write per live frame on top of its apply; fold
  /// it into the apply's transaction if that ever shows.
  Future<void> _moveSyncPointer(int ms) async {
    if (ms <= _syncPointer) return;
    _syncPointer = ms;
    await store.setSyncPointer(ms);
  }

  /// §15.6 — the groups the server lists that this device has no row
  /// for (a reinstall, or an add whose event never got here). Queued
  /// behind inbound frames, like every other channel write.
  Future<void> adoptGroups(Map<String, GroupRoster> groups) => _track(
        _chain = _chain.then((_) async {
          for (final MapEntry(:key, :value) in groups.entries) {
            await _materializeGroup(key, value);
          }
        }).catchError((Object e) {
          // ignore: avoid_print
          print('InboundReceiver: adoptGroups failed: $e');
        }),
      );

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
    // op_id_seen table, and projection writes entirely. Decode and emit
    // on the side-channel.
    if (env.ephemeral) {
      await _handleEphemeral(env, payload);
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

    // Trim 4 — a DM is never created and never announced, so there is
    // no ChannelCreated to depend on: the first op that lands on a
    // derived id IS the introduction. Materialize the channel here.
    //
    // The id must derive from us and the sender, which is the same
    // check the server makes from the other side. A frame that fails
    // it is either a bug or someone else's channel, and either way
    // there is nothing local it could belong to.
    final open = this.open;
    List<int> plain = payload;
    var retryOf = '';
    if (isDmChannelId(channelId)) {
      final sender = env.senderUserId;
      if (sender.isEmpty || dmChannelId(localUserId, sender) != channelId) {
        // ignore: avoid_print
        print('InboundReceiver: dropping DM frame whose channel_id does not '
            'derive from ($localUserId, $sender): channel=$channelId '
            'op_id=$opId');
        return;
      }
      // Decision 188: group keys ride 1:1 channels. Open first, so a key
      // hand-out (opened to nothing to apply) never makes a chat.
      if (open != null) {
        final opened = await open(env);
        if (!_running) return;
        if (opened == null) {
          await _ensureDmChannel(channelId, sender, env);
          await _placeholder(env);
          return;
        }
        if (opened.payload.isEmpty) return;
        (payload: plain, :retryOf) = opened;
      }
      await _ensureDmChannel(channelId, sender, env);
    } else if (!await store.channelExists(channelId) &&
        !await _fetchGroup(channelId)) {
      // A group we were added to whose event never reached us, and the
      // server says we cannot see it (or there is no resolver). There is
      // no row to store this in: dropped on purpose, which is handled.
      // ignore: avoid_print
      print('InboundReceiver: dropping frame for unknown group '
          'channel=$channelId op_id=$opId');
      return;
    }

    if (open != null && !isDmChannelId(channelId)) {
      final opened = await open(env);
      if (!_running) return;
      if (opened == null) {
        await _placeholder(env);
        return;
      }
      if (opened.payload.isEmpty) return;
      (payload: plain, :retryOf) = opened;
    }
    // The re-send of an op this phone could not decrypt takes its place,
    // in the chat too: it applies at the placeholder's server time.
    if (retryOf.isNotEmpty) {
      final placeholderId = undecryptedMessageId(env.senderUserId, retryOf);
      final placeholder = await store.fetchMessage(placeholderId);
      if (placeholder != null) {
        await store.removeMessage(placeholderId);
        final at = placeholder.serverTimestampMs;
        if (at != null) {
          env = pb.Envelope.fromBuffer(env.writeToBuffer())
            ..serverTimestampMs = fixnum.Int64(at);
        }
      }
    }
    pb.ChatPayload chat;
    try {
      chat = pb.ChatPayload.fromBuffer(plain);
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
          nowMs: clock.nowMs(),
        );
        if (env.senderUserId != localUserId && !_peerMessageCtrl.isClosed) {
          _peerMessageCtrl.add(channelId);
        }
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
          serverTimestampMs: env.serverTimestampMs.toInt(),
          nowMs: clock.nowMs(),
        );
      case pb.ChatPayloadType.TYPE_REACTION_ADD:
        await store.applyInboundReactionAdd(
          channelId: channelId,
          opId: opId,
          messageId: chat.messageId,
          senderUserId: env.senderUserId,
          emoji: chat.emoji,
          serverTimestampMs: env.serverTimestampMs.toInt(),
          nowMs: clock.nowMs(),
        );
      case pb.ChatPayloadType.TYPE_REACTION_REMOVE:
        await store.applyInboundReactionRemove(
          channelId: channelId,
          opId: opId,
          messageId: chat.messageId,
          senderUserId: env.senderUserId,
          emoji: chat.emoji,
          serverTimestampMs: env.serverTimestampMs.toInt(),
          nowMs: clock.nowMs(),
        );
      case pb.ChatPayloadType.TYPE_READ_RECEIPT:
        await _handleReceipt(env, chat, MessageState.read);
      case pb.ChatPayloadType.TYPE_DELIVERY_RECEIPT:
        await _handleReceipt(env, chat, MessageState.delivered);
      case pb.ChatPayloadType.TYPE_TYPING:
        // Typing must ride `ephemeral=true`; on the persistent path it
        // would be a stale indicator by the time it applied. Drop it,
        // but record op_id_seen so a re-fanout isn't re-evaluated.
        await store.markOpIdSeen(channelId, opId, clock.nowMs());
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
        // Kept staged: the re-fanout opens from there, not the ratchet.
        return;
    }
    await applied?.call(env);
  }

  /// Decision 188: an op that will never open here shows as "Waiting for
  /// this message" in its place, recorded as handled so the pointer moves
  /// on, and its sender is asked to re-send it.
  Future<void> _placeholder(pb.Envelope env) async {
    // ignore: avoid_print
    print('InboundReceiver: cannot decrypt channel=${env.channelId} '
        'op_id=${env.opId}; asking for a re-send');
    await store.applyInboundMessage(
      localUserId: localUserId,
      channelId: env.channelId,
      opId: env.opId,
      messageId: undecryptedMessageId(env.senderUserId, env.opId),
      senderUserId: env.senderUserId,
      body: null,
      contentType: kUndecryptedType,
      attachments: null,
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: env.clientTimestampMs.toInt(),
      serverTimestampMs: env.serverTimestampMs.toInt(),
      nowMs: clock.nowMs(),
    );
    await undecryptable?.call(env);
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
      case pb.ServerEventPayload_Body.channelEdited:
        await _handleChannelEdited(env, sep.channelEdited);
      case pb.ServerEventPayload_Body.channelDeleted:
        await _handleChannelDeleted(env, sep.channelDeleted);
      case pb.ServerEventPayload_Body.typing:
        // Typing should never arrive on the persistent path — it's
        // routed via the ephemeral flag. If we see it here a peer/server
        // didn't set the flag; treat as no-op rather than persisting.
      case pb.ServerEventPayload_Body.notSet:
        _logServerEventFallback(env, sep);
    }
  }

  /// Decode and re-emit an ephemeral payload. Peers send
  /// `ChatPayload{TYPE_TYPING}` (decision 56); a 0x53-prefixed
  /// server-authored `ServerEventPayload{Typing}` is still accepted in
  /// case the gateway ever emits one. Anything else is a no-op
  /// (forward-compat for future presence / reaction bursts).
  Future<void> _handleEphemeral(pb.Envelope env, List<int> payload) async {
    final bool? isTyping;
    try {
      if (payload[0] == 0x53) {
        final sep = pb.ServerEventPayload.fromBuffer(payload.sublist(1));
        isTyping = sep.whichBody() == pb.ServerEventPayload_Body.typing
            ? sep.typing.isTyping
            : null;
      } else {
        // Lossy: one that will not open is dropped like a malformed one.
        final open = this.open;
        final plain = open == null ? payload : (await open(env))?.payload;
        if (plain == null || plain.isEmpty) return;
        final chat = pb.ChatPayload.fromBuffer(plain);
        isTyping = chat.type == pb.ChatPayloadType.TYPE_TYPING
            ? chat.isTyping
            : null;
      }
    } catch (_) {
      return;
    }
    if (isTyping == null) return;
    if (_typingCtrl.isClosed) return;
    _typingCtrl.add(TypingEvent(
      channelId: env.channelId,
      userId: env.senderUserId,
      isTyping: isTyping,
      emittedAtMs: env.clientTimestampMs.toInt(),
    ));
  }

  /// §6a read / delivery receipt (decision 56). The sender's up-to
  /// marker is a server timestamp (`marker_server_timestamp_ms`, the
  /// stamp of its newest peer message): every message the LOCAL user
  /// authored in this channel stamped at or before it flips to [state]
  /// (`read` or `delivered`; [ChatStore.applyMessageStateChange] never
  /// moves a row backwards). A timestamp, not a lookup of
  /// `message_id`, so it works when we don't hold that message — a
  /// third member's in a group, or one still in transit. The
  /// authorship filter is the §6a.3 gate — a receipt never touches a
  /// third party's rows, and our own echo (sender == us) is ignored.
  /// Our un-ACKed rows have no stamp yet and are never matched.
  Future<void> _handleReceipt(
    pb.Envelope env,
    pb.ChatPayload chat,
    MessageState state,
  ) async {
    final marker = chat.markerServerTimestampMs.toInt();
    if (env.senderUserId != localUserId && marker > 0) {
      final rows = await store.db.rawQuery(
        '''
        SELECT message_id FROM messages
        WHERE channel_id = ? AND author_user_id = ?
          AND server_timestamp_ms <= ?
        ''',
        [env.channelId, localUserId, marker],
      );
      for (final row in rows) {
        await store.applyMessageStateChange(
          messageId: row['message_id'] as String,
          newState: state,
          changedAtMs: env.serverTimestampMs.toInt(),
        );
      }
    }
    await store.markOpIdSeen(env.channelId, env.opId, clock.nowMs());
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
    await store.markOpIdSeen(env.channelId, env.opId, clock.nowMs());
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
    await store.markOpIdSeen(env.channelId, env.opId, clock.nowMs());
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
    await store.markOpIdSeen(env.channelId, env.opId, clock.nowMs());
  }

  /// §10.2 ChannelEdited. Sparse update — each proto3-`optional` field
  /// is forwarded as a present/absent record so the store can
  /// distinguish "not in this edit" from "user cleared this field".
  /// Out-of-order delivery (channel not yet local) is a no-op in the
  /// store; op_id_seen is still recorded so the dedup invariant holds.
  Future<void> _handleChannelEdited(
    pb.Envelope env,
    pb.ChannelEdited body,
  ) async {
    final channelId = body.channelId;
    if (channelId.isEmpty) return;
    if (await store.channelExists(channelId)) {
      final at = _eventAt(env);
      if (body.hasName()) {
        await _groupEvent(env, GroupEvent(GroupEventKind.renamed,
            text: body.name), at: at);
      }
      if (body.hasAvatarUrl()) {
        await _groupEvent(env, GroupEvent(GroupEventKind.photo,
            text: body.avatarUrl), at: at, suffix: '-photo');
      }
    }
    await store.applyChannelEdit(
      channelId: channelId,
      name: body.hasName()
          ? (value: body.name.isEmpty ? null : body.name)
          : null,
      avatarUrl: body.hasAvatarUrl()
          ? (value: body.avatarUrl.isEmpty ? null : body.avatarUrl)
          : null,
      editedAtMs: body.editedAtMs.toInt(),
    );
    await store.markOpIdSeen(env.channelId, env.opId, clock.nowMs());
  }

  /// §10.2 ChannelDeleted. Tombstones the channel locally so the chat
  /// list drops it; membership rows stay so a re-create doesn't lose
  /// history.
  Future<void> _handleChannelDeleted(
    pb.Envelope env,
    pb.ChannelDeleted body,
  ) async {
    final channelId = body.channelId;
    if (channelId.isEmpty) return;
    await store.applyChannelDelete(
      channelId: channelId,
      deletedAtMs: body.deletedAtMs.toInt(),
    );
    await store.markOpIdSeen(env.channelId, env.opId, clock.nowMs());
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

  /// Trim 4 — local materialization of a derived DM the peer spoke on
  /// first. `channels.name` stays null on purpose: the chat-list title
  /// resolves the peer live through `contacts` (AUTH_CONTRACT §2.4),
  /// and the decision-79 backfill fills that row in.
  Future<void> _ensureDmChannel(
    String channelId,
    String senderUserId,
    pb.Envelope env,
  ) async {
    if (await store.channelExists(channelId)) return;
    final createdAt = env.serverTimestampMs.toInt() != 0
        ? env.serverTimestampMs.toInt()
        : clock.nowMs();
    await store.insertChannel(
      channelId: channelId,
      kind: 'one_to_one',
      ownerUserId: localUserId,
      createdAt: createdAt,
    );
    for (final userId in [localUserId, senderUserId]) {
      await store.insertChannelMember(
        channelId: channelId,
        userId: userId,
        role: userId == localUserId ? 'owner' : 'member',
        joinedAt: createdAt,
      );
    }
    _resolveUnknownMembers([senderUserId]);
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
      // WhatsApp's pair: 'Asha created group "Trip"', 'Asha added you'.
      final at = _eventAt(env);
      await _groupEvent(env, GroupEvent(GroupEventKind.created,
          text: body.name), at: at);
      await _groupEvent(env, GroupEvent(GroupEventKind.added,
          users: [localUserId]), at: at, suffix: '-1');
    }
    // §7.2 — record op_id_seen even on the creator-echo skip path so a
    // re-fanout doesn't re-evaluate.
    await store.markOpIdSeen(env.channelId, env.opId, nowMs);
    _resolveUnknownMembers(body.members);
  }

  /// §10.2 ChannelMemberAdded. Out-of-order delivery (channel not yet
  /// local) is dropped silently but op_id_seen is still recorded — the
  /// dedup table is the source of truth for "have I processed this op."
  ///
  /// Decision 80: the same event carries role changes and owner
  /// succession as a RE-announce of an existing member, so the write is
  /// an upsert. An empty `role` leaves an existing member's role alone
  /// (and lands a new row as `member`); `owner` also moves
  /// `channels.owner_user_id`.
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
      // The same event re-announces a role (decision 80): only members
      // who weren't in the group get an "added" line.
      final before = {
        for (final m in await store.fetchChannelMembers(body.channelId))
          m.userId,
      };
      final addedAt = body.addedAtMs.toInt();
      for (final userId in body.members) {
        await store.upsertChannelMember(
          channelId: body.channelId,
          userId: userId,
          role: body.role,
          joinedAt: addedAt,
        );
      }
      final added = body.members.where((u) => !before.contains(u)).toList();
      if (added.contains(localUserId)) {
        // Back in a group we were removed from: show it again.
        await store.db.update('channels', {'tombstoned': 0},
            where: 'channel_id = ?', whereArgs: [body.channelId]);
      }
      if (added.isNotEmpty) {
        await _groupEvent(env, GroupEvent(GroupEventKind.added, users: added),
            at: _eventAt(env));
      }
    } else if (body.members.contains(localUserId) &&
        await _fetchGroup(body.channelId)) {
      await _groupEvent(
          env, GroupEvent(GroupEventKind.added, users: body.members),
          at: _eventAt(env));
    }
    await store.markOpIdSeen(env.channelId, env.opId, nowMs);
    _resolveUnknownMembers(body.members);
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
      // Removed by someone else, we keep the chat and its history, read
      // only (WhatsApp). Our own leave never gets here: the fanout skips
      // the device that left, and leaving deletes the chat there.
      await _groupEvent(
          env,
          GroupEvent(
            env.senderUserId == body.member
                ? GroupEventKind.left
                : GroupEventKind.removed,
            users: [body.member],
          ),
          at: _eventAt(env));
    }
    await store.markOpIdSeen(env.channelId, env.opId, nowMs);
  }

  int _eventAt(pb.Envelope env) => env.serverTimestampMs.toInt() != 0
      ? env.serverTimestampMs.toInt()
      : clock.nowMs();

  /// One [GroupEvent] line per server event (or two, told apart by
  /// [suffix]), keyed on the envelope so a re-fanout writes nothing.
  Future<void> _groupEvent(
    pb.Envelope env,
    GroupEvent event, {
    required int at,
    String suffix = '',
  }) =>
      store.insertGroupEvent(
        channelId: env.channelId,
        messageId: 'ge-${env.opId}$suffix',
        actorUserId: env.senderUserId,
        event: event,
        atMs: at,
      );

  /// [resolveGroup] then [_materializeGroup]; false when the group is
  /// gone or not ours (the resolver says null), or there is no
  /// resolver. A resolver that throws (offline, 5xx) throws through:
  /// the frame is not stored, so it is not handled, the pointer stays
  /// before it and the next pull brings it back (§10.6).
  Future<bool> _fetchGroup(String channelId) async {
    final resolve = resolveGroup;
    if (resolve == null) return false;
    final roster = await resolve(channelId);
    if (roster == null) return false;
    await _materializeGroup(channelId, roster);
    return true;
  }

  Future<void> _materializeGroup(String channelId, GroupRoster roster) async {
    if (await store.channelExists(channelId)) return;
    final owner = roster.roles.entries
            .where((e) => e.value == 'owner')
            .map((e) => e.key)
            .firstOrNull ??
        '';
    await store.insertChannel(
      channelId: channelId,
      kind: 'group',
      ownerUserId: owner,
      createdAt: roster.createdAt,
      name: roster.name,
      avatarUrl: roster.avatarUrl,
    );
    for (final MapEntry(key: userId, value: role) in roster.roles.entries) {
      await store.insertChannelMember(
        channelId: channelId,
        userId: userId,
        role: role,
        joinedAt: roster.createdAt,
      );
    }
    _resolveUnknownMembers(roster.roles.keys);
  }

  /// Decision 79: schedule a best-effort [resolveProfile] fetch for every
  /// member we don't already have a usable contact row for, so a DM
  /// opened by a stranger stops rendering as "Unknown" (AUTH_CONTRACT
  /// §2.4 resolver just needs `username` in the `contacts` table).
  /// Fire-and-forget — never awaited by callers, so a slow or failing
  /// fetch can't stall the channel/membership projection.
  void _resolveUnknownMembers(Iterable<String> memberIds) {
    final resolve = resolveProfile;
    if (resolve == null) return;
    for (final userId in memberIds) {
      if (userId == localUserId) continue;
      // Atomic check-and-claim: `Set.add` is synchronous, so two events
      // for the same user_id in a row can't both slip past this guard.
      if (!_profileFetchInFlight.add(userId)) continue;
      unawaited(_fetchAndApplyProfile(userId, resolve));
    }
  }

  Future<void> _fetchAndApplyProfile(
    String userId,
    Future<ContactProfile?> Function(String) resolve,
  ) async {
    try {
      final rows = await store.db.query(
        'contacts',
        columns: const ['username'],
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (rows.isNotEmpty &&
          (rows.single['username'] as String?)?.isNotEmpty == true) {
        return; // already resolvable via @username.
      }
      final profile = await resolve(userId);
      if (profile == null) return;
      // applyProfileEdit/applyUsernameChange only ever touch the
      // columns they're given — phone_hash and contact_book_name (set
      // locally, never by the server) are left untouched either way.
      await store.applyProfileEdit(
        userId: userId,
        displayName: (value: profile.displayName),
        avatarUrl: (value: profile.avatarUrl),
        nowMs: clock.nowMs(),
      );
      if (profile.username != null && profile.username!.isNotEmpty) {
        await store.applyUsernameChange(
          userId: userId,
          newUsername: profile.username!,
          nowMs: clock.nowMs(),
        );
      }
    } catch (e) {
      // Best-effort — the next ChannelCreated/ChannelMemberAdded that
      // mentions this user_id will retry (the in-flight guard has
      // already been released via `finally` below).
      // ignore: avoid_print
      print('InboundReceiver: profile fetch failed for user=$userId: $e');
    } finally {
      _profileFetchInFlight.remove(userId);
    }
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
