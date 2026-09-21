/// Headless golden path, run against the strict mock server.
///
/// Boots the real service graph the way `lib/main.dart initializeApp()`
/// does — real [ChatStore] on a temp file (WAL path, not `:memory:`),
/// real [WsTransport] / [RestTransport] / [AuthClient] / [SyncScheduler]
/// / [InboundReceiver], the app's own [AuthService] + [ChatService] —
/// and drives it through the nine steps of the v3.0 golden path against
/// `tools/mock_server.dart` in strict mode.
///
/// This test is EXPECTED TO FAIL today. The mock enforces
/// docs/SYNC_PROTOCOL.md and docs/AUTH_CONTRACT.md; the client violates
/// four clauses of them. Each red assertion names the clause. Do not
/// "fix" the test — fix the client.
///
/// Each step is its own `test()` inside one ordered group sharing a
/// single harness, so one red step does not hide the eight others.
library vartalap.golden_path_test;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

import '../tools/mock_server.dart';

const String phoneA = '+15550100001';
const String phoneB = '+15550100002';
const String peerPhone = '+10000000000'; // the mock's seed peer
const String usernameA = 'golden_alice';
const Duration budget = Duration(seconds: 10);

/// A send the server accepted. `sent` OR any later lifecycle state:
/// the mock fans a `MessageStateChanged{DELIVERED}` to the author
/// immediately after the ACK (SYNC_PROTOCOL §10.2, mock_server
/// `_handleWsOp`), and SPIKE_A_SCHEMA §5.1 makes the lifecycle
/// monotonic, so `applyAckSuccess` must not pull the row back down to
/// `sent`. `rejected` is deliberately excluded.
final Matcher isAcked = isIn(const [
  MessageState.sent,
  MessageState.delivered,
  MessageState.read,
]);

late _Harness h;
late String userIdA;
late String peerUserId;
String dmChannelId = '';
String groupChannelId = '';
String peerCreatedChannelId = '';
String extraMemberId = '';
String keyedDmChannelId = '';

void main() {
  group('golden path (strict mock)', () {
    setUpAll(() async {
      h = await _Harness.boot();
    });

    tearDownAll(() async {
      await h.shutdown();
    });

    // ---- 1 --------------------------------------------------------------
    test('1. OTP send → verify → logged in', () async {
      await h.login(phoneA);

      expect(
        h.authService.isLoggedIn,
        isTrue,
        reason: 'AUTH_CONTRACT §3.2: a successful otp/verify must leave '
            'AuthService logged in (accesskey + user_id in memory).',
      );
      userIdA = h.authService.currentUserId ?? '';
      expect(
        RegExp(r'^[0-9a-f]{9}$').hasMatch(userIdA),
        isTrue,
        reason: 'AUTH_CONTRACT §2: user_id is exactly 9 lowercase hex '
            'characters (36 bits). Got "$userIdA".',
      );
    });

    // ---- 1b -------------------------------------------------------------
    test('1b. USERNAME_REQUIRED gate blocks channels until username set',
        () async {
      expect(
        h.authService.username,
        isNull,
        reason: 'AUTH_CONTRACT §3.2: otp/verify never picks a username; a '
            'fresh signup comes back with username: null.',
      );

      // Every non-exempt authenticated route is 403 while the handle is
      // unset — contact discovery is the one the picker hits first.
      AuthClientException? blocked;
      try {
        await h.chat.discoverContacts(
          normalizedPhones: const [peerPhone],
          contactBookNamesByPhone: const {peerPhone: 'Seed Peer'},
        );
      } on AuthClientException catch (e) {
        blocked = e;
      }
      expect(
        blocked?.statusCode,
        403,
        reason: 'AUTH_CONTRACT §2.4: every authenticated route except the '
            'users/me + username/check + auth/* exempt list must answer '
            '403 USERNAME_REQUIRED while username is null. Got '
            '${blocked?.statusCode} ${blocked?.errorCode}.',
      );
      expect(blocked?.errorCode, 'USERNAME_REQUIRED');

      // The mandatory step: PATCH /v3.0/users/me. It is on the exempt
      // list, so it works from inside the gate.
      await h.authService.setUsername(usernameA);
      expect(h.authService.username, usernameA);
      final patches = h.mock.requests
          .where((r) => r.method == 'PATCH' && r.path == '/v3.0/users/me')
          .toList();
      expect(
        patches.map((r) => r.body['username']),
        contains(usernameA),
        reason: 'AUTH_CONTRACT §4.5: PATCH /v3.0/users/me is the only path '
            'that writes username.',
      );

      // …and the gate is down.
      final contacts = await h.chat.discoverContacts(
        normalizedPhones: const [peerPhone],
        contactBookNamesByPhone: const {peerPhone: 'Seed Peer'},
      );
      expect(
        contacts,
        isNotEmpty,
        reason: 'AUTH_CONTRACT §2.4: with a username set the gate lifts and '
            'the previously-403 route succeeds.',
      );
    });

    // ---- 2 --------------------------------------------------------------
    test('2. discover peer → start DM → channel kind is one_to_one', () async {
      final contacts = await h.chat.discoverContacts(
        normalizedPhones: const [peerPhone],
        contactBookNamesByPhone: const {peerPhone: 'Seed Peer'},
      );
      peerUserId = h.mock.seedPeer.userId;
      expect(
        contacts.map((c) => c.userId),
        contains(peerUserId),
        reason: 'AUTH_CONTRACT §7.2: POST /v3.0/contacts/lookup must return '
            'the peer for the submitted SHA-256 phone hash.',
      );

      dmChannelId = await h.chat.startDirectMessage(
        localUserId: userIdA,
        peerUserId: peerUserId,
        peerName: 'Seed Peer',
      );
      final local = await h.channelRow(dmChannelId);
      expect(
        local?['kind'],
        'one_to_one',
        reason: 'SYNC_PROTOCOL §11.3: `kind` is "one_to_one" or "group". '
            'ChatService.startDirectMessage writes "${local?['kind']}" into '
            'the local channels row (lib/services/chat_service.dart, '
            'startDirectMessage → createChannel(kind: \'dm\')).',
      );

      await h.waitFor(() => h.channelPosts(dmChannelId).isNotEmpty);
      final posts = h.channelPosts(dmChannelId);
      expect(
        posts,
        isNotEmpty,
        reason: 'SYNC_PROTOCOL §11.3: starting a DM must issue '
            'POST /v3.0/channels.',
      );
      expect(
        posts.first.body['kind'],
        'one_to_one',
        reason: 'SYNC_PROTOCOL §11.3: the server rejects any `kind` outside '
            '{one_to_one, group} with 400 validation_failed. The client sent '
            'kind="${posts.first.body['kind']}" and the mock answered '
            '${posts.first.status}.',
      );
    });

    // ---- 2b -------------------------------------------------------------
    test('2b. find peer by @username (keyed) → contact upserted → DM',
        () async {
      // No key supplied: the handle exists but is gated (§4.5/§7.6).
      AuthClientException? gated;
      try {
        await h.chat.findByUsername(keyedPeerUsername);
      } on AuthClientException catch (e) {
        gated = e;
      }
      expect(
        gated?.errorCode,
        'USERNAME_KEY_REQUIRED',
        reason: 'CONTRACT ADDITION (mock_server._handleGetUserByUsername): a '
            '*missing* key answers 404 USERNAME_KEY_REQUIRED so the picker '
            'knows to show its Key field. Got ${gated?.errorCode}.',
      );

      // Wrong key: indistinguishable from "no such handle" (§7.6).
      AuthClientException? wrong;
      try {
        await h.chat.findByUsername(keyedPeerUsername, key: '0000');
      } on AuthClientException catch (e) {
        wrong = e;
      }
      expect(
        wrong?.errorCode,
        'USER_NOT_FOUND',
        reason: 'AUTH_CONTRACT §7.6: a wrong key MUST NOT be reported '
            'differently from a nonexistent username.',
      );

      final found =
          await h.chat.findByUsername(keyedPeerUsername, key: keyedPeerKey);
      expect(found.userId, keyedPeerUserId);
      expect(found.username, keyedPeerUsername);
      expect(
        found.displayLabel,
        '@$keyedPeerUsername',
        reason: 'AUTH_CONTRACT §2.4: with no contact-book entry the label '
            'is the handle. Never a phone number.',
      );

      final cached = (await h.store.fetchContacts())
          .where((c) => c.userId == keyedPeerUserId)
          .toList();
      expect(
        cached,
        isNotEmpty,
        reason: 'AUTH_CONTRACT §7.6 + §2.2: the client caches the resolved '
            '(username → user_id) pair as a local contact row.',
      );

      keyedDmChannelId = await h.chat.startDirectMessage(
        localUserId: userIdA,
        peerUserId: keyedPeerUserId,
        peerName: found.displayLabel,
      );
      final local = await h.channelRow(keyedDmChannelId);
      expect(local?['kind'], 'one_to_one');
      await h.waitFor(() => h.channelPosts(keyedDmChannelId).isNotEmpty);
      expect(
        h.channelPosts(keyedDmChannelId).firstOrNull?.status,
        201,
        reason: 'SYNC_PROTOCOL §11.3: a username-initiated DM is an ordinary '
            'POST /v3.0/channels once the handle has been resolved.',
      );
    });

    // ---- 3 --------------------------------------------------------------
    test('3. send text → ACK_SUCCESS → message_state=sent, payload is proto',
        () async {
      // Step 2's bug leaves the channel unknown server-side (the create
      // was rejected). Reconcile out of band so this step tests its own
      // clause instead of re-failing on §6a.3 membership.
      h.mock.ensureChannel(
        channelId: dmChannelId,
        kind: 'one_to_one',
        ownerUserId: userIdA,
        members: [userIdA, peerUserId],
        name: 'Seed Peer',
      );

      final msg = await h.sendAndSettle(dmChannelId, 'hello from golden path');

      expect(
        msg?.state,
        isAcked,
        reason: 'SYNC_PROTOCOL §5.3 + §8.1: a WS_OP must be answered '
            'ACK_SUCCESS and the local row promoted pending→sending→sent. '
            'State is ${msg?.state}. ${await h.opDebug(dmChannelId)}',
      );

      final envs = h.mock.envelopes
          .where((e) => e.channelId == dmChannelId)
          .toList();
      expect(
        envs,
        isNotEmpty,
        reason: 'SYNC_PROTOCOL §5.2: the message must reach the server as a '
            'WS_OP envelope.',
      );
      expect(
        _decodesAsChatPayload(envs.last.payload),
        isTrue,
        reason: 'SYNC_PROTOCOL §6a.1 + docs/proto/v3-chat-payload.proto: '
            'Envelope.payload is a ChatPayload protobuf (or a 0x53-prefixed '
            'ServerEventPayload, §10.2). ChatService._encodeChatPayload ships '
            'JSON instead: ${_preview(envs.last.payload)}. Server answered '
            '"${envs.last.rejectReason}".',
      );
    });

    // ---- 4 --------------------------------------------------------------
    test('4. two more messages on the same channel → all ACK_SUCCESS',
        () async {
      final second = await h.sendAndSettle(dmChannelId, 'second message');
      final third = await h.sendAndSettle(dmChannelId, 'third message');

      final seqs = h.mock.envelopes
          .where((e) => e.channelId == dmChannelId)
          .map((e) => '${e.resourceSeq}:${e.rejectReason ?? 'ok'}')
          .join(', ');

      expect(
        [second?.state, third?.state],
        everyElement(isAcked),
        reason: 'SYNC_PROTOCOL §6 (resource_seq per (user_id, resource_id) '
            'starts at 1, increments by exactly 1, never resets) and §6a.3 '
            'step 5 (payload must be a ChatPayload proto) must both hold for '
            'consecutive sends on one channel. Observed rejects for this '
            'channel (seq:outcome): $seqs. ${await h.opDebug(dmChannelId)}. '
            'NOTE: every send here is already rejected on the §6a.3 payload '
            'clause (step 3), which keeps the rejected op rows in '
            'outbound_ops and so hides the §6 breach on this channel. The §6 '
            'breach shows up in step 6, where the group-create op WAS acked: '
            'ChatStore.applyAckSuccess deletes the acked row, ChatService '
            're-derives resource_seq from MAX(resource_seq) over '
            'outbound_ops, the counter falls back to 1 and the server answers '
            'out_of_order.',
      );
    });

    // ---- 5 --------------------------------------------------------------
    test('5. peer inbound → message, chat-list preview, op_id_seen', () async {
      final seen = <List<MessageRow>>[];
      final sub = h.chat.watchMessages(dmChannelId).listen(seen.add);
      addTearDown(sub.cancel);
      await _pump();

      final injected = h.mock.injectPeerMessage(
        channelId: dmChannelId,
        body: 'ping from the peer',
      );

      await h.waitForAsync(() async =>
          (await h.store.fetchMessage(injected.messageId)) != null);

      expect(
        seen.any((batch) =>
            batch.any((m) => m.messageId == injected.messageId)),
        isTrue,
        reason: 'SYNC_PROTOCOL §10.1: an inbound WS_PUSH must be projected '
            'into messages and surface on watchChannelMessages.',
      );

      final list = await h.store.fetchChannelList();
      final entry =
          list.where((e) => e.channelId == dmChannelId).firstOrNull;
      expect(
        entry?.lastMessagePreview,
        'ping from the peer',
        reason: 'SPIKE_A_SCHEMA §13.1: the chat-list preview must follow the '
            'newest message. Got "${entry?.lastMessagePreview}".',
      );

      expect(
        await h.store.hasSeenOpId(dmChannelId, injected.opId),
        isTrue,
        reason: 'SYNC_PROTOCOL §7.2: the receiver records the applied op_id '
            'in the channel op_id_seen set so a re-fanout is dropped.',
      );
    });

    // ---- 6 --------------------------------------------------------------
    test('6. group create → member added → group message ACK_SUCCESS',
        () async {
      groupChannelId = await h.chat.createGroup(
        name: 'Golden Group',
        creatorUserId: userIdA,
        memberUserIds: [peerUserId],
      );
      await h.waitFor(() => h.channelPosts(groupChannelId).isNotEmpty);
      final post = h.channelPosts(groupChannelId).firstOrNull;
      expect(
        post?.status,
        201,
        reason: 'SYNC_PROTOCOL §11.3: POST /v3.0/channels with kind="group" '
            'and resource_seq=1 must be accepted. Got ${post?.status} '
            '(${post?.body}).',
      );

      // §10.2 ChannelCreated fanout: a channel somebody else created.
      peerCreatedChannelId = 'peer-created-${DateTime.now().millisecondsSinceEpoch}';
      h.mock.ensureChannel(
        channelId: peerCreatedChannelId,
        kind: 'group',
        ownerUserId: peerUserId,
        members: [peerUserId, userIdA],
        name: 'Peer Group',
        announce: true,
      );
      await h.waitForAsync(
          () async => (await h.channelRow(peerCreatedChannelId)) != null);
      expect(
        await h.channelRow(peerCreatedChannelId),
        isNotNull,
        reason: 'SYNC_PROTOCOL §10.2: a ChannelCreated server event '
            '(payload[0]==0x53) must materialize the channel locally.',
      );

      // §10.2 ChannelMemberAdded fanout.
      extraMemberId = h.mock.state.getOrCreateUser('+15550199999').userId;
      h.mock.addChannelMember(groupChannelId, extraMemberId);
      await h.waitForAsync(() async => (await h.store
              .fetchChannelMembers(groupChannelId))
          .any((m) => m.userId == extraMemberId));
      final members = await h.store.fetchChannelMembers(groupChannelId);
      expect(
        members.map((m) => m.userId),
        contains(extraMemberId),
        reason: 'SYNC_PROTOCOL §10.2: a ChannelMemberAdded server event must '
            'be applied to channel_members. Have '
            '${members.map((m) => m.userId).toList()}.',
      );

      final groupMsg = await h.sendAndSettle(groupChannelId, 'group hello');
      final seqs = h.mock.envelopes
          .where((e) => e.channelId == groupChannelId)
          .map((e) => '${e.resourceSeq}:${e.rejectReason ?? 'ok'}')
          .join(', ');
      expect(
        groupMsg?.state,
        isAcked,
        reason: 'SYNC_PROTOCOL §6 + §6a.3: the group-create REST op consumed '
            'resource_seq=1 on this channel and its outbound row was deleted '
            'on ACK_SUCCESS, so ChatService re-derives resource_seq=1 for the '
            'first group message and the server rejects it. '
            'Envelopes (seq:outcome): $seqs. ${await h.opDebug(groupChannelId)}',
      );
    });

    // ---- 7 --------------------------------------------------------------
    test('7. leave group → local tombstone + DELETE /v3.0/channels/{id}',
        () async {
      await h.chat.leaveGroup(groupChannelId);

      expect(
        await h.channelRow(groupChannelId),
        isNull,
        reason: 'SYNC_PROTOCOL §11.3 + chat_service.leaveGroup: leaving a '
            'group drops the local channel row (cascading members/messages) '
            'before the server confirms.',
      );

      await h.waitFor(() => h.mock.requests.any((r) =>
          r.method == 'DELETE' && r.path == '/v3.0/channels/$groupChannelId'));
      final del = h.mock.requests
          .where((r) =>
              r.method == 'DELETE' &&
              r.path == '/v3.0/channels/$groupChannelId')
          .toList();
      expect(
        del,
        isNotEmpty,
        reason: 'SYNC_PROTOCOL §11.3: group leave must issue '
            'DELETE /v3.0/channels/$groupChannelId. Requests seen: '
            '${h.mock.requests.map((r) => '${r.method} ${r.path}').toList()}.',
      );
    });

    // ---- 8 --------------------------------------------------------------
    test('8. logout wipes the local store', () async {
      await h.authService.logout();
      await _pump();

      final counts = await h.counts();
      expect(
        counts,
        {'channels': 0, 'messages': 0, 'contacts': 0},
        reason: 'AUTH_CONTRACT §8: logout destroys the local account state — '
            'the on-device store must hold no channels, messages or contacts '
            'for the signed-out account. AuthService.logout only clears '
            'secure storage (lib/services/auth_service.dart), the ChatStore '
            'is left intact. Got $counts.',
      );
    });

    // ---- 9 --------------------------------------------------------------
    test('9. login as a different phone → store still empty, new user_id',
        () async {
      await h.login(phoneB);
      final userIdB = h.authService.currentUserId ?? '';

      expect(
        userIdB,
        isNot(userIdA),
        reason: 'AUTH_CONTRACT §2: a different phone maps to a different '
            'user_id.',
      );
      final counts = await h.counts();
      expect(
        counts,
        {'channels': 0, 'messages': 0, 'contacts': 0},
        reason: 'AUTH_CONTRACT §8: a second account must never see the first '
            "account's data. The store still holds $counts from $userIdA.",
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Harness — the lib/main.dart initializeApp() wiring, minus the widgets.
// ---------------------------------------------------------------------------

class _Harness {
  final MockServer mock;
  final Directory tmpDir;
  final ChatStore store;
  final AuthClient authClient;
  final AuthService authService;
  final WsTransport ws;
  final RestTransport rest;
  final SyncScheduler scheduler;
  final ChatService chat;
  InboundReceiver? inbound;
  late final StreamSubscription<TransportState> _wsStateSub;

  _Harness._({
    required this.mock,
    required this.tmpDir,
    required this.store,
    required this.authClient,
    required this.authService,
    required this.ws,
    required this.rest,
    required this.scheduler,
    required this.chat,
  });

  static Future<_Harness> boot() async {
    final mock = await MockServer.start(); // strict: true, seed peer on
    final tmpDir = await Directory.systemTemp.createTemp('vartalap_golden');
    // Real file path, not inMemoryDatabasePath — we want the WAL pragmas
    // in ChatStore.open to be exercised.
    final store = await ChatStore.open(path: '${tmpDir.path}/vartalap_v3.db');

    final authClient = AuthClient(baseUrl: mock.apiUrl);
    final authService =
        AuthService(client: authClient, storage: _InMemoryStorage());
    await authService.init();

    final ws = WsTransport(endpoint: mock.wsUrl, auth: authClient);
    final rest = RestTransport(baseUrl: mock.apiUrl, auth: authClient);

    final scheduler = SyncScheduler(
      store: store,
      wsTransport: ws,
      restTransport: rest,
      backoff: const FixedBackoff(Duration(milliseconds: 50)),
      clock: Clock.system,
    );
    await scheduler.start();
    await ws.start(); // no accesskey yet → stays disconnected

    final chat = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: authClient,
      wsTransport: ws,
      uuidGen: Uuid7Gen(userIdBits: 0),
      clock: Clock.system,
    );

    final h = _Harness._(
      mock: mock,
      tmpDir: tmpDir,
      store: store,
      authClient: authClient,
      authService: authService,
      ws: ws,
      rest: rest,
      scheduler: scheduler,
      chat: chat,
    );
    // main.dart App.initState: re-pull on every WS reconnect.
    h._wsStateSub = ws.state.listen((s) {
      if (s == TransportState.connected) unawaited(h.pullPendingSync());
    });
    return h;
  }

  Future<void> shutdown() async {
    await _wsStateSub.cancel();
    await inbound?.stop();
    await scheduler.stop();
    await ws.dispose();
    await rest.dispose();
    await authService.dispose();
    await store.close();
    await mock.stop();
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// AppServices.pullPendingSync.
  Future<void> pullPendingSync() async {
    try {
      final envelopes = await rest.pullPendingSync();
      for (final env in envelopes) {
        ws.injectPush(env);
      }
      await inbound?.drainPending();
    } finally {
      ws.endSyncBuffer();
    }
  }

  /// AppServices.rebuildInboundReceiverForUser.
  Future<void> rebuildInboundReceiverForUser(String userIdHex) async {
    final prev = inbound;
    inbound = null;
    chat.bindTypingSource(null);
    await prev?.stop();
    final next = InboundReceiver(
      store: store,
      pushes: ws.pushes,
      localUserId: userIdHex,
    );
    await next.start();
    inbound = next;
    chat.bindTypingSource(next.typingEvents);
  }

  /// AUTH_CONTRACT §3.1/§3.2 plus the post-login wiring `App.initState`
  /// runs off authStateChange (reseed op_id bits, rebuild the receiver,
  /// connect the WS, pull the queue).
  Future<void> login(String phone) async {
    await authService.sendOtp(phone);
    await authService.verifyOtp(phone, mock.sendOtpCodeFor(phone));
    final userId = authService.currentUserId!;
    chat.reseedForUser(userId);
    await rebuildInboundReceiverForUser(userId);
    await ws.start();
    await waitFor(() => ws.currentState == TransportState.connected);
    await pullPendingSync();
    await _pump();
  }

  // ---- queries ---------------------------------------------------------

  Future<Map<String, Object?>?> channelRow(String channelId) async {
    final rows = await store.db.query(
      'channels',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<Map<String, int>> counts() async {
    Future<int> count(String table) async {
      final r = await store.db.rawQuery('SELECT COUNT(*) c FROM $table');
      return (r.single['c'] as int?) ?? 0;
    }

    return {
      'channels': await count('channels'),
      'messages': await count('messages'),
      'contacts': await count('contacts'),
    };
  }

  List<RecordedRequest> channelPosts(String channelId) => mock.requests
      .where((r) =>
          r.method == 'POST' &&
          r.path == '/v3.0/channels' &&
          r.body['channel_id'] == channelId)
      .toList();

  /// Dump the outbound queue for a resource — the detail that turns a
  /// bare "expected sent, got rejected" into a named contract breach.
  Future<String> opDebug(String resourceId) async {
    final rows = await store.db.query(
      'outbound_ops',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      orderBy: 'resource_seq',
    );
    final dump = rows
        .map((r) => 'seq=${r['resource_seq']} status=${r['status']} '
            'err=${r['last_error']}')
        .join(' | ');
    return 'outbound_ops[$resourceId]: ${dump.isEmpty ? '<empty>' : dump}';
  }

  /// Send [body] and wait until the optimistic row leaves
  /// pending/sending (ACK or reject). Sequential by design: the
  /// scheduler is per-resource serial and a permanent reject cascades
  /// onto every later-sequenced op on the same resource.
  Future<MessageRow?> sendAndSettle(String channelId, String body) async {
    await chat.sendMessage(
      channelId: channelId,
      body: body,
      authorUserId: authService.currentUserId!,
    );
    String? messageId;
    await waitForAsync(() async {
      final rows = await store.fetchChannelMessages(channelId);
      final row = rows.where((m) => m.body == body).firstOrNull;
      messageId = row?.messageId;
      return row != null &&
          row.state != MessageState.pending &&
          row.state != MessageState.sending;
    });
    if (messageId == null) return null;
    return store.fetchMessage(messageId!);
  }

  // ---- waiting ---------------------------------------------------------

  /// Poll [cond] until true or [timeout]. Never throws — the caller's
  /// `expect` produces the failure message, so the spec reference stays
  /// attached to the assertion.
  Future<void> waitFor(bool Function() cond,
      {Duration timeout = budget}) async {
    final sw = Stopwatch()..start();
    while (!cond() && sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> waitForAsync(Future<bool> Function() cond,
      {Duration timeout = budget}) async {
    final sw = Stopwatch()..start();
    while (!(await cond()) && sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 50));

bool _decodesAsChatPayload(List<int> payload) {
  if (payload.isEmpty) return false;
  if (payload[0] == 0x53) return true; // §10.2 server event
  try {
    return pb.ChatPayload.fromBuffer(payload).type !=
        pb.ChatPayloadType.TYPE_UNSPECIFIED;
  } catch (_) {
    return false;
  }
}

String _preview(List<int> payload) {
  try {
    return '"${utf8.decode(payload)}"';
  } catch (_) {
    return '${payload.length} opaque bytes';
  }
}

/// flutter_secure_storage has no platform channel under `flutter test`;
/// same in-memory stand-in the existing auth_service_test uses.
class _InMemoryStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      '_InMemoryStorage.${invocation.memberName} — not implemented for tests',
    );
  }
}
