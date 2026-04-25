/// v3 chat service adapter.
///
/// Thin wrapper around [ChatStore] + [SyncScheduler] that exposes the
/// handful of reactive queries and actions the UI needs. All reads
/// come off the local store's watch streams (offline-first per
/// V3_ARCHITECTURE.md decision 3); writes land locally first and
/// enqueue an outbound op so the scheduler takes it from there.
///
/// The v2 `ChatService` was a pile of static methods with its own
/// socket + SQLite entanglement. v3 inverts that: this class holds
/// nothing stateful beyond its constructor args; the store is the
/// source of truth.
library vartalap.services.chat_service;

import 'dart:async';
import 'dart:convert';

import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// Encoding used for the outbound_ops.payload bytes when the
/// `ChatPayload` proto isn't wired yet (step 9). Once `vartalap_proto`
/// carries a real encoder we swap this out; the shape of the enqueued
/// op is identical so scheduler tests don't care.
List<int> _encodeChatPayload({
  required String messageId,
  required String body,
}) {
  final json = {
    'message_id': messageId,
    'type': 'TYPE_MESSAGE_CREATE',
    'body': body,
    'content_type': 'text/plain',
  };
  return utf8.encode(jsonEncode(json));
}

class ChatService {
  final ChatStore _store;
  final SyncScheduler _scheduler;
  final AuthClient _authClient;
  final Clock _clock;

  /// Current op_id generator. Swapped via [reseedForUser] when the
  /// authenticated user changes — see the class doc on [reseedForUser]
  /// for why the `userIdBits` embedded in every op_id must match the
  /// signed-in session.
  Uuid7Gen _uuidGen;

  /// [uuidGen] must be seeded with the authenticated user's 36-bit
  /// user_id (SPIKE_B_SYNC.md §4). Before login `main.dart` passes a
  /// 0-seeded gen; the UI must not call [sendMessage] until
  /// [reseedForUser] has run with the real user_id from OTP verify.
  ChatService({
    required ChatStore store,
    required SyncScheduler scheduler,
    required AuthClient authClient,
    required Uuid7Gen uuidGen,
    required Clock clock,
  })  : _store = store,
        _scheduler = scheduler,
        _authClient = authClient,
        _uuidGen = uuidGen,
        _clock = clock;

  /// Replace the internal op_id generator after login / phone rebind.
  ///
  /// Every outbound op embeds the signed-in user's 36-bit user_id in
  /// the UUIDv7 (SPIKE_B_SYNC.md §4) and the server rejects anything
  /// else as `prefix_mismatch` (SYNC_PROTOCOL.md §3). If a user logs
  /// in mid-session, the generator constructed at app boot still
  /// carries the pre-login zero bits; without this reseed the first
  /// send after login would be rejected.
  ///
  /// `main.dart` calls this on every `AuthService.authStateChange`
  /// emission where the user is now logged in.
  void reseedForUser(String userIdHex) {
    _uuidGen = Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(userIdHex));
  }

  /// Chat list hot path — SPIKE_A_SCHEMA.md §13.1 via
  /// [ChatStore.watchChannelList].
  Stream<List<ChannelListEntry>> watchChannels({int limit = 100}) =>
      _store.watchChannelList(limit: limit);

  /// Messages in one channel, newest-first, pending rows on top —
  /// SPIKE_A_SCHEMA.md §13.2 via [ChatStore.watchChannelMessages].
  Stream<List<MessageRow>> watchMessages(
    String channelId, {
    int limit = 200,
  }) =>
      _store.watchChannelMessages(channelId, limit: limit);

  /// §5.3 optimistic send.
  ///
  /// 1. Builds a pending [MessageRow] with a fresh client UUIDv7 and
  ///    a matching `op_id` (both UUIDv7, distinct).
  /// 2. Calls [ChatStore.enqueueLocalMessage] which atomically inserts
  ///    the message, the outbound op, and bumps the channel's
  ///    `last_activity_ms`.
  /// 3. Nudges the scheduler so Flow A picks the op up immediately if
  ///    the WS transport is connected. If offline, the op sits in the
  ///    queue until reconnect.
  ///
  /// The UI sees the pending message in [watchMessages] synchronously
  /// (same frame as the send-button tap) — local commit is the
  /// critical-path latency target (<100ms, V3_ARCHITECTURE
  /// "Performance targets").
  Future<void> sendMessage({
    required String channelId,
    required String body,
    required String authorUserId,
  }) async {
    final now = _clock.nowMs();
    final messageId = _uuidGen.next(nowMs: now);
    final opId = _uuidGen.next(nowMs: now);

    // Per-resource sequence number for this channel. v3.0 uses a
    // simple `MAX(resource_seq) + 1` against outbound_ops for the
    // channel. This is fine while the user's only active device
    // generates sends — the per-device monotone property
    // (V3_ARCHITECTURE decision 4) holds. Multi-device is v3.1+.
    final seqRow = await _store.db.rawQuery(
      'SELECT MAX(resource_seq) m FROM outbound_ops WHERE resource_id = ?',
      [channelId],
    );
    final maxSeq = seqRow.single['m'] as int?;
    final nextSeq = (maxSeq ?? 0) + 1;

    final message = MessageRow(
      messageId: messageId,
      channelId: channelId,
      authorUserId: authorUserId,
      body: body,
      contentType: 'text/plain',
      replyToMessageId: null,
      clientTimestampMs: now,
      serverTimestampMs: null,
      deliverySequence: null,
      state: MessageState.pending,
      stateUpdatedAt: now,
      isEdited: false,
      lastEditMs: null,
      tombstoned: false,
      tombstonePendingUntil: null,
    );

    final op = OutboundOpRow(
      opId: opId,
      transport: OpTransport.ws,
      kind: OpKind.chatPayload,
      restMethod: null,
      restPath: null,
      resourceId: channelId,
      resourceSeq: nextSeq,
      payload: _encodeChatPayload(messageId: messageId, body: body),
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: now,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: now,
      targetMessageId: messageId,
      targetChannelId: channelId,
    );

    await _store.enqueueLocalMessage(
      message: message,
      op: op,
      nowMs: now,
    );
    _scheduler.tickSoon();
  }

  /// Create a channel locally and enqueue a REST op to POST /v3.0/channels.
  ///
  /// The local channel row appears in [watchChannels] immediately; the
  /// REST op confirms it server-side. If the server rejects, the channel
  /// stays local (acceptable for v3.0 — no server-side delete yet).
  Future<String> createChannel({
    required String kind,
    required String ownerUserId,
    required List<String> memberUserIds,
    String? name,
  }) async {
    final now = _clock.nowMs();
    final channelId = _uuidGen.next(nowMs: now);
    final opId = _uuidGen.next(nowMs: now);

    await _store.insertChannel(
      channelId: channelId,
      kind: kind,
      ownerUserId: ownerUserId,
      createdAt: now,
      name: name,
    );

    final seqRow = await _store.db.rawQuery(
      'SELECT MAX(resource_seq) m FROM outbound_ops WHERE resource_id = ?',
      [channelId],
    );
    final maxSeq = seqRow.single['m'] as int?;
    final nextSeq = (maxSeq ?? 0) + 1;

    final payload = utf8.encode(jsonEncode({
      'channel_id': channelId,
      'kind': kind,
      'name': name,
      'members': memberUserIds,
    }));

    final op = OutboundOpRow(
      opId: opId,
      transport: OpTransport.rest,
      kind: OpKind.createChannel,
      restMethod: 'POST',
      restPath: '/v3.0/channels',
      resourceId: channelId,
      resourceSeq: nextSeq,
      payload: payload,
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: now,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: now,
      targetMessageId: null,
      targetChannelId: channelId,
    );

    await _store.enqueueOutboundOp(op);
    _scheduler.tickSoon();
    return channelId;
  }

  /// §10 — advances the local read marker and zeroes `unread_count`.
  /// Called on ChatScreen entry. v3.0 is local-only; v3.1 adds an
  /// outbound read-receipt op.
  Future<void> markRead(String channelId) =>
      _store.markChannelRead(channelId, _clock.nowMs());

  /// Discover contacts from the server and cache locally.
  ///
  /// Calls `POST /v3.0/contacts/lookup` (AUTH_CONTRACT §7.2) then
  /// upserts each match into the local `contacts` table. Returns the
  /// full local contact list (may include previously cached contacts).
  Future<List<ContactRow>> discoverContacts() async {
    final matches = await _authClient.lookupContacts([]);
    final now = _clock.nowMs();
    for (final m in matches) {
      await _store.upsertContact(
        userId: m.userId,
        username: m.username,
        displayName: m.username, // best we have from lookup
        nowMs: now,
      );
    }
    return _store.fetchContacts();
  }

  /// Create a group channel locally with [creatorUserId] as owner and
  /// [memberUserIds] (creator excluded — server adds the creator
  /// implicitly per SYNC_PROTOCOL §11.3) as members. Returns channel_id.
  ///
  /// Local membership records both the creator (role `owner`) and every
  /// id in [memberUserIds] (role `member`) so a fresh subscribe to
  /// `watchMemberChannels` shows the new group for the creator. (Live
  /// observers attached during the call may see a transient empty
  /// emission — `insertChannelMember` does not notify, so the post-
  /// `insertChannel` emit JOINs an empty membership. In production the
  /// caller `pushReplacement`s into the chat screen so the Groups tab
  /// stream is re-subscribed before the user looks at it.)
  Future<String> createGroup({
    required String name,
    required String creatorUserId,
    required List<String> memberUserIds,
  }) async {
    final channelId = await createChannel(
      kind: 'group',
      ownerUserId: creatorUserId,
      memberUserIds: memberUserIds,
      name: name,
    );

    final now = _clock.nowMs();
    await _store.insertChannelMember(
      channelId: channelId,
      userId: creatorUserId,
      role: 'owner',
      joinedAt: now,
    );
    for (final uid in memberUserIds) {
      await _store.insertChannelMember(
        channelId: channelId,
        userId: uid,
        role: 'member',
        joinedAt: now,
      );
    }
    return channelId;
  }

  /// Start or resume a DM with [peerUserId]. Returns the channel_id.
  ///
  /// If a DM channel already exists between the current user and the
  /// peer, returns it. Otherwise creates a new one locally and enqueues
  /// the REST op to `POST /v3.0/channels`.
  Future<String> startDirectMessage({
    required String localUserId,
    required String peerUserId,
    required String peerName,
  }) async {
    // Check for existing DM.
    final existing =
        await _store.findExistingDmChannel(localUserId, peerUserId);
    if (existing != null) return existing;

    // Create new channel.
    final channelId = await createChannel(
      kind: 'dm',
      ownerUserId: localUserId,
      memberUserIds: [peerUserId],
      name: peerName,
    );

    // Record both members locally.
    final now = _clock.nowMs();
    await _store.insertChannelMember(
      channelId: channelId,
      userId: localUserId,
      role: 'owner',
      joinedAt: now,
    );
    await _store.insertChannelMember(
      channelId: channelId,
      userId: peerUserId,
      role: 'member',
      joinedAt: now,
    );

    return channelId;
  }

  /// Wipe every message in [channelId] without removing the channel
  /// itself. The chat drops off the chat list (which filters channels
  /// with no `last_message_id`); the channel stays reachable via the
  /// Groups tab or contact picker, and a future inbound or outbound
  /// message brings the chat back.
  ///
  /// Safe for both DM and group channels. Used by:
  ///   - `chat_info` "Clear messages" on a DM
  ///   - chat-list multi-select "Clear messages" (any kind)
  Future<void> clearMessages(String channelId) =>
      _store.clearChannelMessages(channelId);

  /// Leave a group locally. Drops the channel and its membership / messages
  /// from this device. Throws if [channelId] is not a group.
  ///
  /// v3.0 is local-only; the server-side `delete_channel` op lands when
  /// group membership ops do. Until then, leaving a group on one device
  /// does not propagate — re-login or other devices will still see the
  /// channel.
  Future<void> leaveGroup(String channelId) => _store.leaveGroupLocal(channelId);

  /// Channels the current user is an active member of, filtered by
  /// `kind`. Powers the Groups tab in the new-chat picker.
  Stream<List<ChannelListEntry>> watchMemberChannels({
    required String userId,
    String? kind,
  }) =>
      _store.watchMemberChannels(userId: userId, kind: kind);

  /// Reactive failure surface — SPIKE_B_SYNC.md §10. The UI can bind a
  /// toast or inline retry affordance to this.
  Stream<List<OutboundOpRow>> watchFailures() => failureStream(_store);
}

/// Top-level helper so UI code doesn't need to import
/// `package:vartalap_sync` directly for the failure stream.
Stream<List<OutboundOpRow>> failureStream(ChatStore store) =>
    watchFailures(store);
