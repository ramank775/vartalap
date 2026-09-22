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
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// Build the WS_OP payload for an outbound text message — a
/// `ChatPayload{TYPE_MESSAGE_CREATE}` protobuf (SYNC_PROTOCOL §6a.1,
/// docs/proto/v3-chat-payload.proto). This is what the server and
/// every recipient's InboundReceiver decode; anything else is
/// rejected `validation_failed`.
Uint8List _encodeChatPayload({
  required String messageId,
  required String body,
  String? replyToMessageId,
}) =>
    pb.ChatPayload(
      version: 1,
      type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
      messageId: messageId,
      body: body,
      contentType: 'text/plain',
      replyToMessageId: replyToMessageId,
    ).writeToBuffer();

/// The other four ChatPayload types (SYNC_PROTOCOL §6a,
/// docs/proto/v3-chat-payload.proto). Same envelope, same opacity to
/// the server — recipients dispatch on `type` in InboundReceiver and
/// enforce authorship for UPDATE / DELETE themselves (§6a.3).
Uint8List _encodeChatOp({
  required pb.ChatPayloadType type,
  required String messageId,
  String? body,
  String? emoji,
}) =>
    pb.ChatPayload(
      version: 1,
      type: type,
      messageId: messageId,
      body: body,
      contentType: body == null ? null : 'text/plain',
      emoji: emoji,
    ).writeToBuffer();

/// Build the WS_OP payload for an outbound typing indicator — a
/// `ChatPayload{TYPE_TYPING}` (decision 56: the gateway refuses any
/// client-authored `0x53` server event, SYNC_PROTOCOL §10.2). The
/// routing distinguisher is the envelope's `ephemeral` flag, not the
/// payload bytes; channel/sender/timestamp ride on the envelope.
Uint8List _encodeTyping({required bool isTyping}) => pb.ChatPayload(
      version: 1,
      type: pb.ChatPayloadType.TYPE_TYPING,
      isTyping: isTyping,
    ).writeToBuffer();

/// Build the WS_OP payload for an outbound read receipt — a
/// `ChatPayload{TYPE_READ_RECEIPT}` naming the read-up-to message
/// (decision 56). A normal, non-ephemeral op: it is ACKed and it
/// consumes a `resource_seq` on the channel. The server fans the
/// opaque bytes on; every recipient flips its OWN messages at or
/// before the marker to read.
Uint8List _encodeReadReceipt({required String messageId}) => pb.ChatPayload(
      version: 1,
      type: pb.ChatPayloadType.TYPE_READ_RECEIPT,
      messageId: messageId,
    ).writeToBuffer();

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

  /// Presigned-upload / download cache for attachments and avatars.
  /// Also published as [AssetCache.instance] for widgets that cannot
  /// reach a service (see [_installAssetPipeline]).
  late final AssetCache assets;

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
        _clock = clock {
    _installAssetPipeline();
  }

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
    // Trim 4: the dispatcher names the other participant on every op
    // that targets a derived DM channel, and "other" is relative to
    // the signed-in user.
    _scheduler.selfUserId = userIdHex;
  }

  /// Chat list hot path — SPIKE_A_SCHEMA.md §13.1 via
  /// [ChatStore.watchChannelList].
  Stream<List<ChannelListEntry>> watchChannels({int limit = 100}) =>
      _store.watchChannelList(limit: limit);

  /// Messages in one channel, newest-first, pending rows on top —
  /// SPIKE_A_SCHEMA.md §13.2 via [ChatStore.watchChannelMessages].
  /// Pass a [window] for a growable page ("load older" without a
  /// second live query) — see [MessageWindow].
  Stream<List<MessageRow>> watchMessages(
    String channelId, {
    int limit = 200,
    MessageWindow? window,
  }) =>
      _store.watchChannelMessages(channelId, limit: limit, window: window);

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
    String? replyToMessageId,
  }) async {
    final now = _clock.nowMs();
    final messageId = _uuidGen.next(nowMs: now);
    final opId = _uuidGen.next(nowMs: now);

    final message = MessageRow(
      messageId: messageId,
      channelId: channelId,
      authorUserId: authorUserId,
      body: body,
      contentType: 'text/plain',
      replyToMessageId: replyToMessageId,
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
      payload: _encodeChatPayload(
        messageId: messageId,
        body: body,
        replyToMessageId: replyToMessageId,
      ),
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

  /// Create a **group** locally and enqueue a REST op to
  /// POST /v3.0/channels.
  ///
  /// The local channel row appears in [watchChannels] immediately; the
  /// REST op confirms it server-side. If the server rejects, the channel
  /// stays local (acceptable for v3.0 — no server-side delete yet).
  ///
  /// Trim 4: there is no `kind` to choose any more. A DM is never
  /// created — its id is derived from the pair (see
  /// [startDirectMessage]) and the server keeps no row for it — so
  /// `POST /v3.0/channels` takes groups and nothing else.
  Future<String> createChannel({
    required String ownerUserId,
    required List<String> memberUserIds,
    String? name,
  }) async {
    const kind = 'group';
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

    final payload = utf8.encode(jsonEncode({
      'channel_id': channelId,
      'kind': kind,
      'name': name,
      // SYNC_PROTOCOL §11.3: the roster the server stores is the one it
      // is sent, and the creator must be in it — the real gateway
      // answers 403 `forbidden` ("creator must be in members") when it
      // isn't. A Set keeps the call idempotent if a caller passes the
      // owner in [memberUserIds] too.
      'members': <String>{ownerUserId, ...memberUserIds}.toList(),
    }));

    final op = OutboundOpRow(
      opId: opId,
      transport: OpTransport.rest,
      kind: OpKind.createChannel,
      restMethod: 'POST',
      restPath: '/v3.0/channels',
      resourceId: channelId,
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
  /// message) enqueues an outbound `ChatPayload{TYPE_READ_RECEIPT}` so
  /// the author's tick flips to read on their device. Best-effort: if
  /// the op enqueue fails the local read marker still moves.
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
    final op = OutboundOpRow(
      opId: opId,
      transport: OpTransport.ws,
      kind: OpKind.chatPayload,
      restMethod: null,
      restPath: null,
      resourceId: channelId,
      payload: _encodeReadReceipt(messageId: messageId),
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
    final opId = _uuidGen.next(nowMs: now);
    final payload = _encodeTyping(isTyping: isTyping);
    if (!isDmChannelId(channelId)) {
      _wsTransport.sendEphemeral(
        opId: opId,
        channelId: channelId,
        payload: payload,
        clientTimestampMs: now,
      );
      return;
    }
    // Trim 4: a DM has no channel row for the server to check the
    // sender against, so even a typing frame names its peer. The
    // lookup is async; the call stays fire-and-forget.
    unawaited(_store.dmPeer(channelId, localUserId).then((peer) {
      if (peer == null) return;
      _wsTransport.sendEphemeral(
        opId: opId,
        channelId: channelId,
        payload: payload,
        clientTimestampMs: now,
        peer: peer,
      );
    }));
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
        // AUTH_CONTRACT §7.2: a phone-hash match reveals user_id and
        // username, nothing else. Seeding display_name from the handle
        // would mask the §2.4 `@username` rung of the resolver.
        phoneHash: m.phoneHash,
        contactBookName: hashByName[m.phoneHash],
        nowMs: now,
      );
    }
    return _store.fetchContacts();
  }

  /// `GET /v3.0/users/by-username/{username}` — AUTH_CONTRACT §7.6.
  ///
  /// The one network-bound discovery path for somebody who is not in
  /// the address book. Caches the resolved profile as a local contact
  /// row (no `contactBookName` — we have no address-book entry for
  /// them) and returns it, so the caller can open Contact info or start
  /// a DM straight away.
  ///
  /// Throws [AuthClientException]; `errorCode == 'USERNAME_KEY_REQUIRED'`
  /// means the handle exists but is gated by a 4-digit key (§4.5) and
  /// the caller should ask for one. A wrong key is indistinguishable
  /// from a nonexistent handle — both are a plain `USER_NOT_FOUND`.
  Future<ContactRow> findByUsername(String username, {String? key}) async {
    final profile = await _authClient.lookupByUsername(username, key: key);
    final userId = profile['user_id'] as String;
    final now = _clock.nowMs();
    final existing = (await _store.fetchContacts())
        .where((c) => c.userId == userId)
        .firstOrNull;
    await _store.upsertContact(
      userId: userId,
      username: profile['username'] as String?,
      displayName: profile['displayName'] as String?,
      avatarUrl: profile['avatarUrl'] as String?,
      statusText: profile['statusText'] as String?,
      // upsertContact is INSERT OR REPLACE — carry the address-book
      // fields forward so a handle lookup never erases them.
      phoneHash: existing?.phoneHash,
      contactBookName: existing?.contactBookName,
      nowMs: now,
    );
    return (await _store.fetchContacts())
        .firstWhere((c) => c.userId == userId);
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
  /// Trim 4: the id is **derived** from the pair —
  /// `dmChannelId(localUserId, peerUserId)` — so this never talks to
  /// the network. There is no create op, no server-side row and no
  /// second id to reconcile: both sides compute the same channel
  /// offline, which is what makes "we both started this chat while
  /// offline" a non-event rather than a merge.
  ///
  /// All this does locally is make sure the projection rows exist so
  /// the chat list, the member list and the outbound peer lookup have
  /// something to read.
  Future<String> startDirectMessage({
    required String localUserId,
    required String peerUserId,
    required String peerName,
  }) async {
    final channelId = dmChannelId(localUserId, peerUserId);
    await _ensureDmChannel(
      channelId: channelId,
      localUserId: localUserId,
      peerUserId: peerUserId,
      peerName: peerName,
    );
    return channelId;
  }

  /// Idempotent local materialization of a derived DM channel.
  /// `INSERT OR IGNORE` semantics: re-opening an existing DM leaves its
  /// history, its unread count and its local flags alone.
  Future<void> _ensureDmChannel({
    required String channelId,
    required String localUserId,
    required String peerUserId,
    required String peerName,
  }) async {
    if (await _store.channelExists(channelId)) return;
    final now = _clock.nowMs();
    await _store.insertChannel(
      channelId: channelId,
      kind: 'one_to_one',
      ownerUserId: localUserId,
      createdAt: now,
      name: peerName,
    );
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

  /// Leave a group (decision 9/80): `DELETE /v3.0/channels/{id}/members/
  /// {selfUserId}`, for owners too — the server promotes the
  /// longest-standing admin (else the longest-standing member) and
  /// re-announces them as owner. Locally the channel row is dropped
  /// straight away (cascading members + messages) for an optimistic UI.
  ///
  /// The server's eventual `ChannelMemberRemoved` fanout reaches the
  /// remaining members; the leaver's own copy of that fanout is a no-op
  /// because the local channel row is already gone.
  Future<void> leaveGroup(
    String channelId, {
    required String selfUserId,
  }) =>
      _channelMembershipOp(
        channelId: channelId,
        caller: 'leaveGroup',
        kind: OpKind.removeMember,
        method: 'DELETE',
        path: '/v3.0/channels/$channelId/members/$selfUserId',
        payload: const [],
        applyLocal: () => _store.leaveGroupLocal(channelId),
      );

  /// Delete a group for everyone (decision 9, owner only):
  /// `DELETE /v3.0/channels/{id}`. The server hard-deletes and fans
  /// `ChannelDeleted`; locally the channel is tombstoned now, the same
  /// write that fanout makes on every other member.
  Future<void> deleteGroup(String channelId) => _channelMembershipOp(
        channelId: channelId,
        caller: 'deleteGroup',
        kind: OpKind.deleteChannel,
        method: 'DELETE',
        path: '/v3.0/channels/$channelId',
        payload: const [],
        applyLocal: () => _store.deleteGroupLocal(channelId),
      );

  /// Promote or demote a member (decision 80):
  /// `PATCH /v3.0/channels/{id}/members/{user_id}` with
  /// `{role: "admin"|"member"}`. Owner and admins only — the server
  /// answers 403 otherwise, and a terminal reject puts the local row
  /// back (`ChatStore._rollbackMemberRole`).
  Future<void> setMemberRole({
    required String channelId,
    required String userId,
    required String role,
  }) =>
      _channelMembershipOp(
        channelId: channelId,
        caller: 'setMemberRole',
        kind: OpKind.setMemberRole,
        method: 'PATCH',
        path: '/v3.0/channels/$channelId/members/$userId',
        payload: utf8.encode(jsonEncode({'role': role})),
        applyLocal: () => _store.setMemberRoleLocal(
          channelId: channelId,
          userId: userId,
          role: role,
        ),
      );

  /// The shape all three group-membership writes share: refuse to touch
  /// a DM, enqueue the REST op, apply the local projection, kick the
  /// scheduler. Resolving the channel kind up front keeps the outbound
  /// queue clean even though the store methods re-validate.
  Future<void> _channelMembershipOp({
    required String channelId,
    required String caller,
    required String kind,
    required String method,
    required String path,
    required List<int> payload,
    required Future<void> Function() applyLocal,
  }) async {
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
    final channelKind = rows.single['kind'] as String;
    if (channelKind != 'group') {
      throw StateError(
        '$caller called on non-group channel ($channelKind). '
        'DM channels must not be deleted — clear messages instead.',
      );
    }

    final now = _clock.nowMs();
    final op = OutboundOpRow(
      opId: _uuidGen.next(nowMs: now),
      transport: OpTransport.rest,
      kind: kind,
      restMethod: method,
      restPath: path,
      resourceId: channelId,
      // RestTransport tolerates an empty payload — it sends just the
      // standard op_id / resource_seq / client_timestamp_ms envelope
      // fields with no endpoint-specific body.
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
    await applyLocal();
    _scheduler.tickSoon();
  }

  /// Active members of [channelId], joined with the local contact row
  /// where one exists. Powers the chat-info member list.
  Future<List<ChannelMemberRow>> fetchChannelMembers(String channelId) =>
      _store.fetchChannelMembers(channelId);

  /// One-shot read of the channels [userId] is a member of, optionally
  /// filtered by [kind]. The reactive variant is [watchMemberChannels].
  Future<List<ChannelListEntry>> fetchMemberChannels({
    required String userId,
    String? kind,
  }) =>
      _store.fetchMemberChannels(userId: userId, kind: kind);

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

  // --- Message actions — V3_RELEASE_PLAN §4.3 / §4.4 --------------------

  /// One outbound WS op carrying a ChatPayload. [kind] is local-only
  /// bookkeeping (see [OpKind.messageEdit]); the wire shape is the same
  /// for every type.
  OutboundOpRow _chatOp({
    required String kind,
    required String channelId,
    required String messageId,
    required Uint8List payload,
    required int nowMs,
  }) =>
      OutboundOpRow(
        opId: _uuidGen.next(nowMs: nowMs),
        transport: OpTransport.ws,
        kind: kind,
        restMethod: null,
        restPath: null,
        resourceId: channelId,
        payload: payload,
        status: OpStatus.pending,
        attempts: 0,
        nextRetryAt: nowMs,
        dispatchedAt: null,
        lastError: null,
        acknowledgedAt: null,
        createdAt: nowMs,
        targetMessageId: messageId,
        targetChannelId: channelId,
      );

  /// Toggle [emoji] from [userId] on [messageId] — REACTION_ADD when
  /// [add], REACTION_REMOVE otherwise. Local row first, op second, one
  /// transaction. Non-destructive, so no undo window (decision 11).
  Future<void> reactToMessage({
    required String channelId,
    required String messageId,
    required String userId,
    required String emoji,
    required bool add,
  }) async {
    final now = _clock.nowMs();
    await _store.enqueueReaction(
      messageId: messageId,
      userId: userId,
      emoji: emoji,
      add: add,
      nowMs: now,
      op: _chatOp(
        kind: OpKind.messageReaction,
        channelId: channelId,
        messageId: messageId,
        payload: _encodeChatOp(
          type: add
              ? pb.ChatPayloadType.TYPE_REACTION_ADD
              : pb.ChatPayloadType.TYPE_REACTION_REMOVE,
          messageId: messageId,
          emoji: emoji,
        ),
        nowMs: now,
      ),
    );
    _scheduler.tickSoon();
  }

  /// Replace the body of one of the local user's own messages —
  /// MESSAGE_UPDATE. Recipients drop it unless we are the author
  /// (SYNC_PROTOCOL §6a.3), so the caller must gate the UI on
  /// authorship too; this is the second line of defence, not the first.
  Future<void> editMessage({
    required String channelId,
    required String messageId,
    required String newBody,
  }) async {
    final now = _clock.nowMs();
    await _store.enqueueMessageEdit(
      messageId: messageId,
      newBody: newBody,
      nowMs: now,
      op: _chatOp(
        kind: OpKind.messageEdit,
        channelId: channelId,
        messageId: messageId,
        payload: _encodeChatOp(
          type: pb.ChatPayloadType.TYPE_MESSAGE_UPDATE,
          messageId: messageId,
          body: newBody,
        ),
        nowMs: now,
      ),
    );
    _scheduler.tickSoon();
  }

  /// Decision 11 — delete for everyone, with a [undoWindow] during
  /// which nothing has been sent. The caller is responsible for calling
  /// [commitDelete] when the window elapses (or [undoDelete] before
  /// that); [sweepExpiredDeletes] is the backstop for a caller that
  /// never got the chance.
  Future<void> deleteMessage({
    required String messageId,
    Duration undoWindow = const Duration(seconds: 5),
  }) async {
    final now = _clock.nowMs();
    await _store.beginTombstone(
      messageId: messageId,
      pendingUntilMs: now + undoWindow.inMilliseconds,
      nowMs: now,
    );
  }

  /// Undo inside the window. Enqueues nothing, and cancels the delete
  /// that [commitDelete] would otherwise have sent.
  Future<void> undoDelete(String messageId) =>
      _store.undoTombstone(messageId: messageId, nowMs: _clock.nowMs());

  /// The window elapsed — enqueue MESSAGE_DELETE. No-op if an Undo got
  /// there first. Returns true iff an op was enqueued.
  Future<bool> commitDelete({
    required String channelId,
    required String messageId,
  }) async {
    final now = _clock.nowMs();
    final committed = await _store.commitTombstone(
      messageId: messageId,
      op: _chatOp(
        kind: OpKind.messageDelete,
        channelId: channelId,
        messageId: messageId,
        payload: _encodeChatOp(
          type: pb.ChatPayloadType.TYPE_MESSAGE_DELETE,
          messageId: messageId,
        ),
        nowMs: now,
      ),
    );
    if (committed) _scheduler.tickSoon();
    return committed;
  }

  /// Commit every delete in [channelId] whose window elapsed while
  /// nobody was watching (screen closed, app killed). Called on chat
  /// open so a tombstone can never strand un-enqueued.
  Future<void> sweepExpiredDeletes(String channelId) async {
    for (final messageId in await _store.expiredTombstones(
      channelId: channelId,
      nowMs: _clock.nowMs(),
    )) {
      await commitDelete(channelId: channelId, messageId: messageId);
    }
  }

  /// SPIKE_B_SYNC.md §10 — user tapped Retry on a failed op. Clones it
  /// into a fresh pending op (new op_id, so the server treats it as a
  /// new intent) and dismisses the failed row.
  Future<void> retryFailedOp(String opId) async {
    final now = _clock.nowMs();
    await _store.manualRetry(
      failedOpId: opId,
      newOpId: _uuidGen.next(nowMs: now),
      nowMs: now,
    );
    _scheduler.tickSoon();
  }

  /// User saw the failure (toast shown) — stop re-reporting it.
  Future<void> dismissFailure(String opId) =>
      _store.acknowledgeFailure(opId: opId, nowMs: _clock.nowMs());

  // --- local-only chat settings ------------------------------------------
  //
  // Pin, mute and delete-chat are device-local metadata
  // (V3_ARCHITECTURE decision 3 offline matrix). None of them enqueues
  // an outbound op, so none of them can fail or need a connection —
  // which is why they have no error path and no "needs a connection"
  // affordance in the UI.

  /// Pin [channelId] to the top of the chat list, or unpin it.
  Future<void> setPinned(String channelId, bool pinned) =>
      _store.setChannelPinned(channelId, pinned);

  /// Mute [channelId] until [untilMs] (epoch ms). `null` unmutes;
  /// [kMuteAlways] is the sheet's "Always" option.
  ///
  /// Gating the ntfy wake on this value is server-side work
  /// (V3_RELEASE_PLAN open item 13); today the flag only drives the
  /// outline unread badge and the group-info mute bar.
  Future<void> setMuted(String channelId, int? untilMs) =>
      _store.setChannelMuted(channelId, untilMs);

  /// "Delete chat" — local-only, and not "leave group". Erases history
  /// and drops the row from Chats; membership is untouched, the group
  /// keeps showing under Groups, and the next message brings the chat
  /// back. See [leaveGroup] for the server-op counterpart.
  Future<void> deleteChat(String channelId) =>
      _store.deleteChatLocal(channelId);

  /// One channel plus its local settings — powers the group-info
  /// header. Null when the channel is not in the local store.
  Future<ChannelListEntry?> fetchChannel(String channelId) =>
      _store.fetchChannel(channelId);

  /// Image messages in [channelId], newest first. Powers "Media, links
  /// and docs".
  Future<List<MessageRow>> fetchMedia(String channelId) =>
      _store.fetchChannelMedia(channelId);

  /// Non-image attachments in [channelId], newest first — the file list
  /// under the media grid.
  Future<List<MessageRow>> fetchFiles(String channelId) =>
      _store.fetchChannelFiles(channelId);

  // --- attachments and photos — V3_RELEASE_PLAN §4.2 ---------------------
  //
  // Everything here is local-first in the same sense as [sendMessage]:
  // the row (or the avatar) points at the picked file on disk the
  // instant the user picks it, and an `asset_upload` op swaps in the
  // media-ms fileId once the bytes are up. The upload is a real op, so
  // it retries, backs off, and dead-letters like anything else.

  /// Wire the asset client, cache, and upload adapter together. Called
  /// from the constructor because `main.dart` has already built (and
  /// started) the scheduler by then — see [SyncScheduler.assetTransport].
  void _installAssetPipeline() {
    final client = AssetClient(
      baseUrl: _authClient.baseUrl,
      auth: _authClient,
    );
    assets = AssetCache(client: client);
    AssetCache.instance = assets;
    _scheduler.assetTransport = AssetUploadTransport(
      client: client,
      network: _wsTransport,
      onUploaded: _onAssetUploaded,
    );
  }

  /// `messages.attachments` for one file: a `ChatPayload` carrying only
  /// the repeated field, the same shape InboundReceiver writes.
  static Uint8List _encodeAttachments(Map<String, dynamic> spec, String url) =>
      pb.ChatPayload(
        attachments: [
          pb.Attachment(
            url: url,
            mimeType: spec['mime'] as String,
            sizeBytes: fixnum.Int64(spec['size'] as int),
            filename: spec['name'] as String? ?? '',
            width: spec['width'] as int? ?? 0,
            height: spec['height'] as int? ?? 0,
          ),
        ],
      ).writeToBuffer();

  /// MESSAGE_CREATE carrying an attachment. Separate from
  /// [_encodeChatPayload] only because `content_type` is the file's
  /// type here, not `text/plain`.
  static Uint8List _encodeAttachmentCreate({
    required String messageId,
    required Map<String, dynamic> spec,
    required String url,
  }) =>
      pb.ChatPayload(
        version: 1,
        type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
        messageId: messageId,
        body: spec['body'] as String? ?? '',
        contentType: spec['mime'] as String,
        attachments: pb.ChatPayload.fromBuffer(_encodeAttachments(spec, url))
            .attachments,
        replyToMessageId: spec['replyTo'] as String?,
      ).writeToBuffer();

  OutboundOpRow _uploadOp({
    required Map<String, dynamic> spec,
    required String resourceId,
    required String? messageId,
    required String? channelId,
    required int nowMs,
  }) =>
      OutboundOpRow(
        opId: _uuidGen.next(nowMs: nowMs),
        transport: OpTransport.asset,
        kind: OpKind.assetUpload,
        restMethod: null,
        restPath: null,
        // Deliberately NOT the channel: `resource_seq` is per
        // (user, resource) and strictly monotonic on the wire
        // (SYNC_PROTOCOL §6). An upload never reaches the server, so
        // spending a channel sequence number on one would leave a hole
        // the server reads as `out_of_order`.
        resourceId: resourceId,
        payload: utf8.encode(jsonEncode(spec)),
        status: OpStatus.pending,
        attempts: 0,
        nextRetryAt: nowMs,
        dispatchedAt: null,
        lastError: null,
        acknowledgedAt: null,
        createdAt: nowMs,
        targetMessageId: messageId,
        targetChannelId: channelId,
      );

  /// Send [path] as an attachment. The file must already live somewhere
  /// durable — use [AssetCache.importPicked] on whatever the picker
  /// returns, because the picker's temp copy can be swept before the
  /// upload runs.
  ///
  /// Returns the new message_id.
  Future<String> sendAttachment({
    required String channelId,
    required String authorUserId,
    required String path,
    String? caption,
    String? replyToMessageId,
    int width = 0,
    int height = 0,
  }) async {
    final now = _clock.nowMs();
    final messageId = _uuidGen.next(nowMs: now);
    final file = File(path);
    final size = await file.length();
    if (size > AssetClient.maxUploadBytes) {
      throw ArgumentError(
        'Attachment is ${size ~/ (1024 * 1024)} MB; the limit is '
        '${AssetClient.maxUploadBytes ~/ (1024 * 1024)} MB.',
      );
    }
    final spec = <String, dynamic>{
      'then': 'message',
      'path': path,
      'ext': extForPath(path),
      'mime': mimeForPath(path),
      'size': size,
      'name': path.split('/').last,
      'category': 'message',
      'width': width,
      'height': height,
      'body': caption ?? '',
      if (replyToMessageId != null) 'replyTo': replyToMessageId,
    };

    // The bubble points at the local file until the upload lands, so a
    // photo is visible in the thread the moment it is picked.
    final message = MessageRow(
      messageId: messageId,
      channelId: channelId,
      authorUserId: authorUserId,
      body: caption,
      contentType: spec['mime'] as String,
      replyToMessageId: replyToMessageId,
      clientTimestampMs: now,
      serverTimestampMs: null,
      deliverySequence: null,
      state: MessageState.pending,
      stateUpdatedAt: now,
      isEdited: false,
      lastEditMs: null,
      tombstoned: false,
      tombstonePendingUntil: null,
      attachments: _encodeAttachments(spec, path),
    );

    await _store.enqueueLocalMessage(
      message: message,
      op: _uploadOp(
        spec: spec,
        resourceId: 'asset:$messageId',
        messageId: messageId,
        channelId: channelId,
        nowMs: now,
      ),
      nowMs: now,
    );
    _scheduler.tickSoon();
    return messageId;
  }

  /// Set the signed-in user's photo. Shows immediately (local path),
  /// then becomes the fileId and a `PATCH /v3.0/users/me` once uploaded
  /// — whose `ProfileEdited` fanout tells everyone we share a channel
  /// with (AUTH_CONTRACT §4.5, SYNC_PROTOCOL §10.2).
  Future<void> setOwnAvatar(String path) =>
      _enqueueAvatarUpload(path: path, then: 'profile', channelId: null);

  /// Same for a group photo — `PATCH /v3.0/channels/{id}`, fanned out
  /// as `ChannelEdited`.
  Future<void> setChannelAvatar({
    required String channelId,
    required String path,
  }) async {
    await _store.setChannelAvatar(channelId, path);
    await _enqueueAvatarUpload(
      path: path,
      then: 'channel',
      channelId: channelId,
    );
  }

  Future<void> _enqueueAvatarUpload({
    required String path,
    required String then,
    required String? channelId,
  }) async {
    final now = _clock.nowMs();
    final size = await File(path).length();
    if (then == 'profile') await _writeOwnAvatar(path);
    await _store.enqueueOutboundOp(_uploadOp(
      spec: {
        'then': then,
        'path': path,
        'ext': extForPath(path),
        'mime': mimeForPath(path),
        'size': size,
        'name': path.split('/').last,
        'category': 'profile',
      },
      resourceId: 'asset:$path',
      messageId: null,
      channelId: channelId,
      nowMs: now,
    ));
    _scheduler.tickSoon();
  }

  /// The upload finished: [fileId] is now a real media-ms object, so
  /// whatever was waiting on it can go out. Runs before the upload op's
  /// own ACK is processed, so the follow-up op is durable by the time
  /// the upload op is retired.
  Future<void> _onAssetUploaded(String opId, String fileId) async {
    final op = await _store.fetchOutboundOp(opId);
    if (op == null) return;
    final spec = jsonDecode(utf8.decode(op.payload)) as Map<String, dynamic>;
    // The bytes are already in memory under the local path — keep them
    // so the bubble doesn't re-download what it just uploaded.
    assets.rekey(spec['path'] as String, fileId);
    final now = _clock.nowMs();

    switch (spec['then'] as String?) {
      case 'message':
        final messageId = op.targetMessageId!;
        final channelId = op.targetChannelId!;
        await _store.setMessageAttachments(
          messageId: messageId,
          attachments: _encodeAttachments(spec, fileId),
        );
        await _store.enqueueOutboundOp(OutboundOpRow(
          opId: _uuidGen.next(nowMs: now),
          transport: OpTransport.ws,
          kind: OpKind.chatPayload,
          restMethod: null,
          restPath: null,
          resourceId: channelId,
          payload: _encodeAttachmentCreate(
            messageId: messageId,
            spec: spec,
            url: fileId,
          ),
          status: OpStatus.pending,
          attempts: 0,
          nextRetryAt: now,
          dispatchedAt: null,
          lastError: null,
          acknowledgedAt: null,
          createdAt: now,
          targetMessageId: messageId,
          targetChannelId: channelId,
        ));
      case 'profile':
        await _writeOwnAvatar(fileId);
        await _store.enqueueOutboundOp(_restOp(
          kind: OpKind.editProfile,
          method: 'PATCH',
          path: '/v3.0/users/me',
          resourceId: 'me',
          channelId: null,
          body: {'avatarUrl': fileId},
          nowMs: now,
        ));
      case 'channel':
        final channelId = op.targetChannelId!;
        await _store.setChannelAvatar(channelId, fileId);
        await _store.enqueueOutboundOp(_restOp(
          kind: OpKind.editChannel,
          method: 'PATCH',
          path: '/v3.0/channels/$channelId',
          resourceId: channelId,
          channelId: channelId,
          body: {'avatarUrl': fileId},
          nowMs: now,
        ));
    }
    _scheduler.tickSoon();
  }

  OutboundOpRow _restOp({
    required String kind,
    required String method,
    required String path,
    required String resourceId,
    required String? channelId,
    required Map<String, dynamic> body,
    required int nowMs,
  }) =>
      OutboundOpRow(
        opId: _uuidGen.next(nowMs: nowMs),
        transport: OpTransport.rest,
        kind: kind,
        restMethod: method,
        restPath: path,
        resourceId: resourceId,
        payload: utf8.encode(jsonEncode(body)),
        status: OpStatus.pending,
        attempts: 0,
        nextRetryAt: nowMs,
        dispatchedAt: null,
        lastError: null,
        acknowledgedAt: null,
        createdAt: nowMs,
        targetMessageId: null,
        targetChannelId: channelId,
      );

  /// Own avatar, local copy. Not in `contacts` — that table is other
  /// people, and a self row would show up in the new-chat picker.
  ///
  /// ponytail: `shared_preferences`, because the one place that owns
  /// own-profile persistence (`AuthService`) writes secure storage and
  /// an avatar pointer is not a secret. Move it there if own-profile
  /// fields ever need to be read atomically together.
  static const String _ownAvatarKey = 'v3.avatarUrl';

  Future<void> _writeOwnAvatar(String value) async {
    try {
      (await SharedPreferences.getInstance())
          .setString(_ownAvatarKey, value);
    } catch (_) {
      // No platform channel (widget tests) — the avatar just isn't
      // remembered across restarts there.
    }
  }

  /// The signed-in user's photo: a local path until the upload lands,
  /// then the media-ms fileId. Null when they have never set one.
  Future<String?> ownAvatarUrl() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_ownAvatarKey);
    } catch (_) {
      return null;
    }
  }
}

/// "Always" in the mute sheet — a `muted_until_ms` far enough out that
/// it never elapses, so the same `until > now` comparison covers every
/// mute option and no "muted forever" special case is needed.
const int kMuteAlways = 253402300800000; // 9999-01-01T00:00:00Z

/// Top-level helper so UI code doesn't need to import
/// `package:vartalap_sync` directly for the failure stream.
Stream<List<OutboundOpRow>> failureStream(ChatStore store) =>
    watchFailures(store);
