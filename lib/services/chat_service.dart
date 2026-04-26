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
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
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

/// Build the WS_OP payload for an outbound typing indicator. Same
/// `0x53 || ServerEventPayload{Typing}` shape as other server-event
/// envelopes; the routing distinguisher is the envelope's `ephemeral`
/// flag, not the payload bytes. Channel/sender/timestamp ride on the
/// envelope, not duplicated in the body.
Uint8List _encodeTyping({required bool isTyping}) {
  final sep = pb.ServerEventPayload(
    version: 1,
    type: pb.ServerEventType.TYPING,
    typing: pb.Typing(isTyping: isTyping),
  );
  return Uint8List.fromList([0x53, ...sep.writeToBuffer()]);
}

/// Build the WS_OP payload for an outbound read receipt — a
/// `ServerEventPayload{MessageStateChanged}` prefixed with the §10.2
/// `0x53` distinguisher byte. Server fans this verbatim to the rest of
/// the channel; the original message's author flips their tick to read.
Uint8List _encodeReadReceipt({
  required String channelId,
  required String messageId,
  required int nowMs,
}) {
  final sep = pb.ServerEventPayload(
    version: 1,
    type: pb.ServerEventType.MESSAGE_STATE_CHANGED,
    messageStateChanged: pb.MessageStateChanged(
      channelId: channelId,
      messageId: messageId,
      newState: pb.MessageStateValue.MESSAGE_STATE_READ,
      changedAtMs: fixnum.Int64(nowMs),
    ),
  );
  return Uint8List.fromList([0x53, ...sep.writeToBuffer()]);
}

class ChatService {
  final ChatStore _store;
  final SyncScheduler _scheduler;
  final AuthClient _authClient;
  final Clock _clock;
  final WsTransport _wsTransport;

  /// Broadcast passthrough for inbound typing events. main.dart wires
  /// every InboundReceiver instance (built/rebuilt per login) into this
  /// controller via [bindTypingSource], so chat screens can subscribe
  /// once and stay correct across logout/login cycles.
  final StreamController<TypingEvent> _typingCtrl =
      StreamController<TypingEvent>.broadcast();
  StreamSubscription<TypingEvent>? _typingSub;

  Stream<TypingEvent> get typingEvents => _typingCtrl.stream;

  /// Replace the inbound typing source. Cancels the previous bridge if
  /// any. Pass `null` to detach (e.g. on logout while the screen is
  /// already torn down). Idempotent.
  void bindTypingSource(Stream<TypingEvent>? source) {
    _typingSub?.cancel();
    _typingSub = null;
    if (source == null) return;
    _typingSub = source.listen((e) {
      if (!_typingCtrl.isClosed) _typingCtrl.add(e);
    });
  }

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
    required WsTransport wsTransport,
    required Uuid7Gen uuidGen,
    required Clock clock,
  })  : _store = store,
        _scheduler = scheduler,
        _authClient = authClient,
        _wsTransport = wsTransport,
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

  /// Advances the local read marker, zeroes `unread_count`, and (if
  /// the user is logged in and the channel has at least one peer
  /// message) enqueues an outbound `MessageStateChanged{READ}` so the
  /// author's tick flips to read on their device. Best-effort: if the
  /// op enqueue fails the local read marker still moves.
  Future<void> markRead(String channelId) async {
    final now = _clock.nowMs();
    await _store.markChannelRead(channelId, now);
    final localUserId = _authClient.currentUserId;
    if (localUserId == null) return;
    final messageId = await _store.latestPeerMessageId(
      channelId: channelId,
      localUserId: localUserId,
    );
    if (messageId == null) return;

    final opId = _uuidGen.next(nowMs: now);
    final seqRow = await _store.db.rawQuery(
      'SELECT MAX(resource_seq) m FROM outbound_ops WHERE resource_id = ?',
      [channelId],
    );
    final maxSeq = seqRow.single['m'] as int?;
    final nextSeq = (maxSeq ?? 0) + 1;

    final op = OutboundOpRow(
      opId: opId,
      transport: OpTransport.ws,
      kind: OpKind.chatPayload,
      restMethod: null,
      restPath: null,
      resourceId: channelId,
      resourceSeq: nextSeq,
      payload: _encodeReadReceipt(
        channelId: channelId,
        messageId: messageId,
        nowMs: now,
      ),
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: now,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: now,
      // Read receipt doesn't target a local message row — the ACK just
      // deletes the op (scheduler's null-targetMessageId branch).
      targetMessageId: null,
      targetChannelId: channelId,
    );
    await _store.enqueueOutboundOp(op);
    _scheduler.tickSoon();
  }

  /// Fire-and-forget typing indicator. Constructs an ephemeral envelope
  /// (no `outbound_ops` row, no retry, no ACK) and writes it directly
  /// to the WS. If the WS isn't connected the call is a no-op — the
  /// recipient's "is typing" indicator will time out on its own.
  void notifyTyping({
    required String channelId,
    required bool isTyping,
  }) {
    final localUserId = _authClient.currentUserId;
    if (localUserId == null) return;
    final now = _clock.nowMs();
    // localUserId is read only to gate the call (don't fire when
    // logged out — the embedded uuid_v7 user_id bits would be wrong).
    // It does not appear in the encoded payload — the server stamps
    // sender_user_id on the envelope at fanout.
    if (localUserId.isEmpty) return;
    _wsTransport.sendEphemeral(
      opId: _uuidGen.next(nowMs: now),
      channelId: channelId,
      payload: _encodeTyping(isTyping: isTyping),
      clientTimestampMs: now,
    );
  }

  /// Discover contacts from the server and cache locally.
  ///
  /// SHA-256-hashes each E.164 phone in [normalizedPhones] per
  /// AUTH_CONTRACT §7.2, calls `POST /v3.0/contacts/lookup`, then
  /// upserts each match into the local `contacts` table. Returns the
  /// full local contact list.
  ///
  /// If [normalizedPhones] is empty, returns the cached local list
  /// without firing a server call (the screen passes an empty list
  /// when contacts permission is denied or the address book has no
  /// phone numbers).
  Future<List<ContactRow>> discoverContacts({
    List<String> normalizedPhones = const [],
    Map<String, String> contactBookNamesByPhone = const {},
  }) async {
    if (normalizedPhones.isEmpty) {
      return _store.fetchContacts();
    }
    // Hash each normalized phone, keeping a hash→name map so the
    // server's per-hash matches can recover the device-side label.
    final hashByName = <String, String>{};
    final hashes = normalizedPhones.map((p) {
      final h = sha256.convert(utf8.encode(p)).toString();
      final name = contactBookNamesByPhone[p];
      if (name != null && name.isNotEmpty) hashByName[h] = name;
      return h;
    }).toList();
    final matches = await _authClient.lookupContacts(hashes);
    final now = _clock.nowMs();
    for (final m in matches) {
      await _store.upsertContact(
        userId: m.userId,
        username: m.username,
        displayName: m.username,
        phoneHash: m.phoneHash,
        contactBookName: hashByName[m.phoneHash],
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

  /// Leave a group: enqueue a REST `DELETE /v3.0/channels/{id}` op for
  /// the server to drop our membership, then locally drop the channel +
  /// cascade for an optimistic UI. Throws if [channelId] is not a group.
  ///
  /// The server's eventual `ChannelMemberRemoved` fanout reaches the
  /// remaining members; the leaver's own copy of that fanout is a no-op
  /// because the local channel row is already gone.
  Future<void> leaveGroup(String channelId) async {
    // Resolve channel kind first so we never enqueue a DELETE op for a
    // DM. `leaveGroupLocal` re-validates and throws on non-group, but
    // doing the check up front keeps the outbound queue clean.
    final rows = await _store.db.query(
      'channels',
      columns: const ['kind'],
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    if (rows.isEmpty) {
      // Channel already gone locally — nothing to do, no op to enqueue.
      return;
    }
    final kind = rows.single['kind'] as String;
    if (kind != 'group') {
      throw StateError(
        'leaveGroup called on non-group channel ($kind). '
        'DM channels must not be deleted — clear messages instead.',
      );
    }

    final now = _clock.nowMs();
    final opId = _uuidGen.next(nowMs: now);

    final seqRow = await _store.db.rawQuery(
      'SELECT MAX(resource_seq) m FROM outbound_ops WHERE resource_id = ?',
      [channelId],
    );
    final maxSeq = seqRow.single['m'] as int?;
    final nextSeq = (maxSeq ?? 0) + 1;

    final op = OutboundOpRow(
      opId: opId,
      transport: OpTransport.rest,
      kind: OpKind.deleteChannel,
      restMethod: 'DELETE',
      restPath: '/v3.0/channels/$channelId',
      resourceId: channelId,
      resourceSeq: nextSeq,
      // RestTransport tolerates an empty payload — it sends just the
      // standard op_id / resource_seq / client_timestamp_ms envelope
      // fields with no endpoint-specific body.
      payload: const [],
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
    await _store.leaveGroupLocal(channelId);
    _scheduler.tickSoon();
  }

  /// Active members of [channelId], joined with the local contact row
  /// where one exists. Powers the chat-info member list.
  Future<List<ChannelMemberRow>> fetchChannelMembers(String channelId) =>
      _store.fetchChannelMembers(channelId);

  /// Substring search restricted to [channelId]. Powers chat-info's
  /// "Search in conversation" sheet.
  Future<List<MessageRow>> searchInChannel({
    required String channelId,
    required String query,
    int limit = 200,
  }) =>
      _store.searchChannelMessages(
        channelId: channelId,
        query: query,
        limit: limit,
      );

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
