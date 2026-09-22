/// Two full client stacks against one strict mock server.
///
/// Everything the golden path proves with a single client and a scripted
/// peer, this file proves with two real ones: two in-memory
/// [ChatStore]s, two [AuthClient] / [WsTransport] / [RestTransport] /
/// [SyncScheduler] / [InboundReceiver] / [AuthService] / [ChatService]
/// sets, talking to each other through `tools/mock_server.dart`. Only
/// the secure storage and the connectivity signal are stubbed — and the
/// connectivity signal is the point: it is what lets a test say
/// "offline", queue work, and then watch the reconnect.
///
/// The scenarios here are the ones whose answer is settled under the
/// CURRENT channel-id scheme (client-minted UUIDv7, server upserts by
/// id). What happens when two people start the same DM while both
/// offline is an open question — see
/// decisions/DM_IDENTITY_EDGE_CASES.md and the branch that implements
/// it — so nothing here asserts either way on it.
@Timeout(Duration(minutes: 4))
library vartalap.dm_identity_test;

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

import '../tools/mock_server.dart';

const Duration budget = Duration(seconds: 20);

int _phoneCounter = 0;
String _freshPhone() => '+1555${++_phoneCounter + 2000000}';
int _nameCounter = 0;
String _freshUsername() => 'dm${++_nameCounter + 100000}';

void main() {
  late MockServer mock;

  setUpAll(() async {
    mock = await MockServer.start(seedPeer: false);
  });

  tearDownAll(() async {
    await mock.stop();
  });

  /// Two signed-up, username-picked, connected clients that know each
  /// other as contacts. Torn down with the test.
  Future<(_Client, _Client)> pair() async {
    final a = await _Client.boot(mock, label: 'A');
    final b = await _Client.boot(mock, label: 'B');
    addTearDown(() async {
      await a.shutdown();
      await b.shutdown();
    });
    await a.login();
    await b.login();
    await a.setUsername(_freshUsername());
    await b.setUsername(_freshUsername());
    await a.chat.discoverContacts(
      normalizedPhones: [b.phone],
      contactBookNamesByPhone: {b.phone: 'Bea'},
    );
    await b.chat.discoverContacts(
      normalizedPhones: [a.phone],
      contactBookNamesByPhone: {a.phone: 'Ana'},
    );
    return (a, b);
  }

  /// The premise every other test here rests on: the two stacks really
  /// are two. sqflite keys its open-database cache by path, so unless
  /// [ChatStore.open] turns that cache off for `:memory:`, both opens
  /// return one shared database and the pair silently becomes one
  /// device wearing two hats — a test that then "passes" proves
  /// nothing.
  test('0. the two stacks are independent', () async {
    final (a, b) = await pair();
    expect(a.userId, isNot(b.userId));
    expect(
      await b.dmChannelIds(),
      isEmpty,
      reason: "B's store must not see A's rows.",
    );

    // Hold the announcement so the only way B could know about A's new
    // channel is a shared database handle.
    mock.holdChannelCreatedFanout = true;
    addTearDown(() => mock.holdChannelCreatedFanout = false);
    final id = await a.startDm(b);
    await a.drain();
    expect(await a.hasChannel(id), isTrue);
    expect(
      await b.hasChannel(id),
      isFalse,
      reason: 'B may only learn about the channel over the wire, never by '
          "sharing a database handle with A. If this fails, every other "
          'test in this file is asserting on one device pretending to be '
          'two.',
    );

    mock.releaseChannelCreatedFanout();
    await b.drain();
    expect(
      await b.hasChannel(id),
      isTrue,
      reason: 'and over the wire it does arrive.',
    );
  });

  // ---- the reconnect tick, end to end ---------------------------------
  test('1. a queue written while offline drains on reconnect', () async {
    final (a, b) = await pair();
    final channelId = await a.startDm(b);
    await a.drain();
    await b.drain();
    expect(
      await b.hasChannel(channelId),
      isTrue,
      reason: 'the §10.2 ChannelCreated fanout gives B the channel.',
    );

    await a.goOffline();
    for (var i = 1; i <= 3; i++) {
      await a.chat.sendMessage(
        channelId: channelId,
        body: 'offline$i',
        authorUserId: a.userId,
      );
    }
    expect(
      await a.queuedOpCount(),
      3,
      reason: 'nothing leaves the device while both transports are down.',
    );

    // Reconnect and then do NOTHING else. No new message, no ACK, no
    // manual tick — the reconnect itself has to wake Flow A, and the
    // scheduler's 10s sweep only chases stuck `in_flight` rows, never
    // a `pending` one.
    await a.reconnectAndWait();

    expect(
      await a.queuedOpCount(),
      0,
      reason: 'the whole offline queue must drain on its own after the '
          'network returns. ${await a.opDebug(channelId)}',
    );
    await b.drain();
    expect(
      await b.bodiesIn(channelId),
      containsAllInOrder(const ['offline1', 'offline2', 'offline3']),
      reason: 'and reach B in the order A typed them — the queue is '
          'dispatched in (resource_id, resource_seq) order.',
    );
    expect(await a.deadLetteredOps(), isEmpty);
  });

  // ---- inbound dedup, over the real wire -------------------------------
  test('2. the same message delivered twice makes one bubble', () async {
    final (a, b) = await pair();
    final channelId = await a.startDm(b);
    await a.drain();
    await b.drain();
    await a.chat.sendMessage(
      channelId: channelId,
      body: 'only once',
      authorUserId: a.userId,
    );
    await a.drain();
    await b.drain();
    expect(await b.bodiesIn(channelId), ['only once']);
    await b.chat.markRead(channelId);
    await b.drain();

    // The same message_id again under a fresh op_id, which is what a
    // re-send looks like on the wire: the op_id dedup cannot catch it,
    // so the message_id has to.
    final messageId = (await b.store.fetchChannelMessages(channelId))
        .single
        .messageId;
    mock.injectPeerMessage(
      channelId: channelId,
      body: 'only once',
      senderUserId: a.userId,
    );
    await b.pullPendingSync();
    await b.drain();

    expect(
      (await b.store.fetchChannelMessages(channelId)).length,
      greaterThanOrEqualTo(1),
      reason: 'sanity: the channel still has its message.',
    );
    // Re-deliver the ORIGINAL message_id directly through the inbound
    // writer — the mock mints a fresh message_id per injection, so this
    // is the level at which "same message, new op" is expressible.
    await b.store.applyInboundMessage(
      localUserId: b.userId,
      channelId: channelId,
      opId: 'op-redelivered',
      messageId: messageId,
      senderUserId: a.userId,
      body: 'only once',
      contentType: 'text/plain',
      attachments: null,
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: 1,
      serverTimestampMs: 2,
      deliverySequence: 9999,
      nowMs: 3,
    );

    expect(
      (await b.store.fetchChannelMessages(channelId))
          .where((m) => m.messageId == messageId)
          .length,
      1,
      reason: 'a duplicate delivery must not add a second bubble.',
    );
    expect(
      await b.store.hasSeenOpId(channelId, 'op-redelivered'),
      isTrue,
      reason: 'and must still record the op as seen, so a re-fanout of it '
          'is not re-evaluated forever.',
    );
  });

  // ---- a create the server refuses -------------------------------------
  test('3. a permanently rejected create leaves no ghost chat', () async {
    final (a, _) = await pair();
    // §11.3: the creator must be in `members`. The strict mock answers
    // 403 `forbidden`, exactly as channel-ms does — the same shape the
    // client sees for an unknown peer or a username-key gate.
    final ghost = await a.chat.createChannel(
      kind: 'one_to_one',
      ownerUserId: 'deadbeef1',
      memberUserIds: const ['deadbeef2'],
      name: 'Nobody',
    );
    expect(
      await a.hasChannel(ghost),
      isTrue,
      reason: 'optimistic insert first — the row exists before the POST.',
    );
    await a.drain();

    expect(
      await a.hasChannel(ghost),
      isFalse,
      reason: 'a create the server will never accept must not leave a chat '
          'behind: nothing can retry it and nothing can be sent to it. '
          '${await a.channelDebug()}',
    );
    expect(await a.memberIds(ghost), isEmpty);
    expect(
      (await a.chatList()).map((e) => e.channelId),
      isNot(contains(ghost)),
      reason: 'and the chat list never shows it.',
    );
    final op = await a.createOpFor(ghost);
    expect(
      op,
      isNotNull,
      reason: 'the failed op survives so the user still learns why.',
    );
    expect(op!.status, isIn([OpStatus.rejected, OpStatus.deadLetter]));
    expect(op.lastError, 'forbidden');
  });

  // ---- roster is not identity ------------------------------------------
  test('4. groups with identical rosters stay distinct channels', () async {
    final (a, b) = await pair();
    final dm = await a.startDm(b);
    await a.drain();

    final g1 = await a.chat.createChannel(
      kind: 'group',
      ownerUserId: a.userId,
      memberUserIds: [b.userId],
      name: 'Same two people',
    );
    await a.drain();
    final g2 = await a.chat.createChannel(
      kind: 'group',
      ownerUserId: a.userId,
      memberUserIds: [b.userId],
      name: 'Same two people again',
    );
    await a.drain();

    expect(
      {dm, g1, g2},
      hasLength(3),
      reason: 'a roster is not an identity: two groups with the same two '
          'members, and a DM between those same two, are three channels.',
    );
    for (final id in [g1, g2]) {
      expect(
        mock.requests
            .where((r) =>
                r.path == '/v3.0/channels' && r.body['channel_id'] == id)
            .map((r) => r.status),
        contains(201),
        reason: 'each group create is a real 201 on the id it was sent '
            'with.',
      );
      expect(await a.hasChannel(id), isTrue);
      await b.drain();
      expect(
        await b.hasChannel(id),
        isTrue,
        reason: 'and each is announced to the other member.',
      );
    }
    expect(
      await a.dmChannelIds(),
      [dm],
      reason: "and no group row is ever read as the pair's DM.",
    );
  });

  // ---- local-only chat lifecycle ---------------------------------------
  test('5. a deleted or cleared chat reuses its channel', () async {
    final (a, b) = await pair();
    final channelId = await a.startDm(b);
    await a.drain();
    await a.chat.sendMessage(
      channelId: channelId,
      body: 'x',
      authorUserId: a.userId,
    );
    await a.drain();
    await b.drain();
    expect(await b.dmChannelIds(), [channelId]);

    final postsBefore = mock.requests
        .where((r) => r.method == 'POST' && r.path == '/v3.0/channels')
        .length;

    // "Delete chat" is local-only (V3_RELEASE_PLAN §6).
    await b.chat.deleteChat(channelId);
    expect(
      await b.startDm(a),
      channelId,
      reason: 'a locally deleted DM is still the same channel: starting it '
          'again must find it, not mint a second id.',
    );

    // Same for "Clear messages".
    await b.chat.clearMessages(channelId);
    expect(await b.startDm(a), channelId);

    await b.drain();
    expect(
      mock.requests
          .where((r) => r.method == 'POST' && r.path == '/v3.0/channels')
          .length,
      postsBefore,
      reason: 'and neither path may issue a second POST /v3.0/channels.',
    );
  });

  // ---- mock knobs -------------------------------------------------------
  test('6. the fanout knob holds the announcement past the REST answer',
      () async {
    final (a, b) = await pair();
    mock.holdChannelCreatedFanout = true;
    addTearDown(() => mock.holdChannelCreatedFanout = false);

    final channelId = await a.chat.createChannel(
      kind: 'group',
      ownerUserId: a.userId,
      memberUserIds: [b.userId],
      name: 'held',
    );
    await a.drain();
    expect(
      await a.hasChannel(channelId),
      isTrue,
      reason: 'the creator has its optimistic row and its 201.',
    );
    expect(
      await b.hasChannel(channelId),
      isFalse,
      reason: 'with the knob on, the announcement is parked: the REST '
          'response is already out and B still knows nothing. This is the '
          'ordering a test needs to be able to choose.',
    );

    mock.releaseChannelCreatedFanout();
    await b.drain();
    expect(
      await b.hasChannel(channelId),
      isTrue,
      reason: 'releasing it delivers the announcement as usual.',
    );
    expect(
      await b.memberIds(channelId),
      {a.userId, b.userId},
      reason: 'with the roster the announcement carried.',
    );
  });

  test('7. dropUndelivered loses exactly what was queued', () async {
    final (a, b) = await pair();
    final channelId = await a.startDm(b);
    await a.drain();
    await b.drain();

    await b.goOffline();
    for (var i = 1; i <= 3; i++) {
      await a.chat.sendMessage(
        channelId: channelId,
        body: 'queued$i',
        authorUserId: a.userId,
      );
      await a.drain();
    }
    expect(
      mock.state.undelivered[b.userId],
      isNotNull,
      reason: 'an offline recipient accumulates frames server-side.',
    );

    expect(
      mock.dropUndelivered(b.userId),
      greaterThanOrEqualTo(3),
      reason: 'the knob reports how many frames it threw away.',
    );
    expect(
      mock.state.undelivered[b.userId],
      isNull,
      reason: 'and the queue is empty afterwards.',
    );
    expect(
      mock.dropUndelivered(b.userId),
      0,
      reason: 'dropping an empty queue is a no-op, not a crash.',
    );

    // The point of the knob: this loss is invisible to the client. B
    // reconnects, pulls, and simply never learns about the three
    // messages. Asserted so the gap is documented rather than implied.
    await b.goOnline();
    await b.drain();
    expect(
      await b.bodiesIn(channelId),
      isEmpty,
      reason: 'a lost undelivered queue is silent data loss on v3.0: the '
          'pull is the only delivery path and it has nothing to hand '
          'over. Any recovery mechanism has to be tested against this.',
    );
  });
}

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 60));

/// One complete client stack, the way `main.dart initializeApp()` builds
/// it — except the store is in-memory and REST connectivity is a knob.
class _Client {
  final String label;
  final MockServer mock;
  final String phone;
  final ChatStore store;
  final AuthClient authClient;
  final AuthService authService;
  final WsTransport ws;
  final RestTransport rest;
  final SyncScheduler scheduler;
  final ChatService chat;
  final StreamController<bool> connectivity;
  InboundReceiver? inbound;
  late final StreamSubscription<TransportState> _wsStateSub;

  _Client._({
    required this.label,
    required this.mock,
    required this.phone,
    required this.store,
    required this.authClient,
    required this.authService,
    required this.ws,
    required this.rest,
    required this.scheduler,
    required this.chat,
    required this.connectivity,
  });

  String get userId => authService.currentUserId ?? '';

  static Future<_Client> boot(
    MockServer mock, {
    required String label,
    String? phone,
  }) async {
    // Decision 87: in-memory only, never a file. ChatStore.open turns
    // sqflite's per-path handle cache off for `:memory:`, which is what
    // makes two of these two rather than one — see test 0.
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final authClient = AuthClient(baseUrl: mock.apiUrl);
    final authService =
        AuthService(client: authClient, storage: _InMemoryStorage());
    await authService.init();

    final ws = WsTransport(endpoint: mock.wsUrl, auth: authClient);
    final connectivity = StreamController<bool>.broadcast();
    final rest = RestTransport(
      baseUrl: mock.apiUrl,
      auth: authClient,
      connectivityStream: connectivity.stream,
    );
    final scheduler = SyncScheduler(
      store: store,
      wsTransport: ws,
      restTransport: rest,
      backoff: const FixedBackoff(Duration(milliseconds: 40)),
      clock: Clock.system,
    );
    await scheduler.start();
    final chat = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: authClient,
      wsTransport: ws,
      uuidGen: Uuid7Gen(userIdBits: 0),
      clock: Clock.system,
    );
    final c = _Client._(
      label: label,
      mock: mock,
      phone: phone ?? _freshPhone(),
      store: store,
      authClient: authClient,
      authService: authService,
      ws: ws,
      rest: rest,
      scheduler: scheduler,
      chat: chat,
      connectivity: connectivity,
    );
    // main.dart App.initState: re-pull on every WS reconnect.
    c._wsStateSub = ws.state.listen((s) {
      if (s == TransportState.connected) unawaited(c.pullPendingSync());
    });
    return c;
  }

  Future<void> shutdown() async {
    await _wsStateSub.cancel();
    await inbound?.stop();
    await scheduler.stop();
    await ws.dispose();
    await rest.dispose();
    await connectivity.close();
    await authService.dispose();
    await store.close();
  }

  // ---- auth / connection ----------------------------------------------

  Future<void> login() async {
    await authService.sendOtp(phone);
    await authService.verifyOtp(phone, mock.sendOtpCodeFor(phone));
    chat.reseedForUser(userId);
    await rebuildInboundReceiver();
    await wsOnline();
  }

  Future<void> setUsername(String username) =>
      authService.setUsername(username);

  Future<void> rebuildInboundReceiver() async {
    final prev = inbound;
    inbound = null;
    chat.bindTypingSource(null);
    await prev?.stop();
    final next = InboundReceiver(
      store: store,
      pushes: ws.pushes,
      localUserId: userId,
    );
    await next.start();
    inbound = next;
    chat.bindTypingSource(next.typingEvents);
  }

  /// Offline = no socket and no network for REST. Anything enqueued
  /// from here parks in `outbound_ops`.
  Future<void> goOffline() async {
    connectivity.add(false);
    await ws.stop();
    await _pump();
  }

  Future<void> wsOnline() async {
    await ws.start();
    await waitFor(() => ws.currentState == TransportState.connected);
    await pullPendingSync();
    await _pump();
  }

  Future<void> restOnline() async {
    connectivity.add(true);
    await _pump();
  }

  Future<void> goOnline() async {
    await wsOnline();
    await restOnline();
    await _pump();
  }

  /// Bring the network back and then wait, touching nothing. No
  /// `tickSoon`, no fresh enqueue — whatever drains here drained
  /// because the reconnect itself woke the scheduler.
  Future<void> reconnectAndWait() async {
    await ws.start();
    await waitFor(() => ws.currentState == TransportState.connected);
    connectivity.add(true);
    await waitForAsync(() async => await queuedOpCount() == 0);
    await inbound?.drainPending();
    await _pump();
  }

  Future<void> pullPendingSync() async {
    try {
      for (final env in await rest.pullPendingSync()) {
        ws.injectPush(env);
      }
      await inbound?.drainPending();
    } finally {
      ws.endSyncBuffer();
    }
  }

  // ---- actions ---------------------------------------------------------

  Future<String> startDm(_Client peer) => chat.startDirectMessage(
        localUserId: userId,
        peerUserId: peer.userId,
        peerName: peer.label,
      );

  /// Wait until the outbound queue has nothing left to do and the
  /// inbound chain has settled.
  Future<void> drain() async {
    await waitForAsync(() async {
      await inbound?.drainPending();
      return await queuedOpCount() == 0;
    });
    await inbound?.drainPending();
    await _pump();
  }

  // ---- queries ---------------------------------------------------------

  Future<int> queuedOpCount() async {
    final rows = await store.db.rawQuery(
      "SELECT COUNT(*) c FROM outbound_ops "
      "WHERE status IN ('pending', 'retrying', 'in_flight')",
    );
    return (rows.single['c'] as int?) ?? 0;
  }

  Future<bool> hasChannel(String channelId) async => (await store.db.query(
        'channels',
        columns: const ['channel_id'],
        where: 'channel_id = ?',
        whereArgs: [channelId],
        limit: 1,
      ))
          .isNotEmpty;

  /// Every non-tombstoned `one_to_one` row, oldest first.
  Future<List<String>> dmChannelIds() async {
    final rows = await store.db.query(
      'channels',
      columns: const ['channel_id'],
      where: "kind = 'one_to_one' AND tombstoned = 0",
      orderBy: 'created_at',
    );
    return rows.map((r) => r['channel_id'] as String).toList();
  }

  Future<Set<String>> memberIds(String channelId) async {
    final rows = await store.db.query(
      'channel_members',
      columns: const ['user_id'],
      where: 'channel_id = ? AND removed_at IS NULL',
      whereArgs: [channelId],
    );
    return rows.map((r) => r['user_id'] as String).toSet();
  }

  Future<List<String>> bodiesIn(String channelId) async {
    final rows = await store.fetchChannelMessages(channelId);
    return [
      for (final m in rows.reversed)
        if (m.body != null) m.body!
    ];
  }

  Future<List<ChannelListEntry>> chatList() => store.fetchChannelList();

  Future<OutboundOpRow?> createOpFor(String channelId) async {
    final rows = await store.db.query(
      'outbound_ops',
      columns: const ['op_id'],
      where: 'resource_id = ? AND kind = ?',
      whereArgs: [channelId, OpKind.createChannel],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return store.fetchOutboundOp(rows.single['op_id'] as String);
  }

  Future<List<String>> deadLetteredOps() async {
    final rows = await store.db.query(
      'outbound_ops',
      columns: const ['op_id'],
      where: "status = 'dead_letter'",
    );
    return rows.map((r) => r['op_id'] as String).toList();
  }

  Future<String> channelDebug() async {
    final rows = await store.db.query(
      'channels',
      columns: const ['channel_id', 'kind', 'tombstoned', 'deleted_locally'],
    );
    return '$label channels: '
        '${rows.map((r) => '${r['channel_id']}/${r['kind']}'
            '${r['tombstoned'] == 1 ? '/tomb' : ''}'
            '${r['deleted_locally'] == 1 ? '/del' : ''}').join(' | ')}';
  }

  Future<String> opDebug(String resourceId) async {
    final rows = await store.db.query(
      'outbound_ops',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      orderBy: 'resource_seq',
    );
    final dump = rows
        .map((r) => 'seq=${r['resource_seq']} kind=${r['kind']} '
            'status=${r['status']} err=${r['last_error']}')
        .join(' | ');
    return '$label outbound_ops[$resourceId]: '
        '${dump.isEmpty ? '<empty>' : dump}';
  }

  // ---- waiting ---------------------------------------------------------

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

/// flutter_secure_storage has no platform channel under `flutter test`;
/// same in-memory stand-in the other suites use.
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
