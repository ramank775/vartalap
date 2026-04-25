/// ChatService is a thin adapter; the interesting properties are
/// end-to-end: an optimistic send lands a pending row that the chat
/// list + chat screen streams see, and reseedForUser swaps the
/// user_id bits embedded in op_ids (SPIKE_B_SYNC.md §4).
///
/// These tests run against a real ChatStore (in-memory sqlite) and a
/// real SyncScheduler with stub transports. No mocking library — the
/// scheduler's gate test uses the same hand-written _StubTransport
/// shape.
library vartalap.services.chat_service_test;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  setUpAll(() {
    // sqflite_common_ffi needs explicit init under flutter_test; the
    // package tests wire this through ChatStore.open but we double-tap
    // it here to cover direct factory access on the test isolate.
    sqfliteFfiInit();
  });

  test('sendMessage inserts a pending message and emits on the watchers',
      () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final clock = FakeClock(1000000);
    final ws = _StubTransport();
    final rest = _StubTransport(connected: false);

    final scheduler = SyncScheduler(
      store: store,
      wsTransport: ws,
      restTransport: rest,
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
      clock: clock,
    );
    await scheduler.start();

    final chat = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: AuthClient(baseUrl: Uri.parse('http://localhost')),
      uuidGen: Uuid7Gen(userIdBits: 0xABCDEF012),
      clock: clock,
    );

    const channelId = 'c-1';
    const userId = 'u-self';

    await store.insertChannel(
      channelId: channelId,
      kind: 'one_to_one',
      ownerUserId: userId,
      createdAt: clock.nowMs(),
    );

    // Subscribe BEFORE send so we catch the initial emit + the post-
    // send re-emit. The chat-list stream emits on every
    // `channels`/`messages` mutation; here we care about the one
    // after enqueueLocalMessage.
    final chatList = <List<ChannelListEntry>>[];
    final messages = <List<MessageRow>>[];
    final chatListSub = chat.watchChannels().listen(chatList.add);
    final messagesSub = chat.watchMessages(channelId).listen(messages.add);

    // Let the initial emits settle.
    await _pumpEventQueue();

    await chat.sendMessage(
      channelId: channelId,
      body: 'hello world',
      authorUserId: userId,
    );

    await _pumpEventQueue();

    expect(chatList, isNotEmpty);
    final latestChannels = chatList.last;
    expect(latestChannels, hasLength(1));
    expect(latestChannels.single.channelId, channelId);
    expect(latestChannels.single.lastMessagePreview, 'hello world');

    // First non-empty emit is the pending insert (the next emit races
    // with Flow A's pending→sending transition triggered by tickSoon).
    final firstWithMessage =
        messages.firstWhere((m) => m.isNotEmpty);
    expect(firstWithMessage, hasLength(1));
    expect(firstWithMessage.single.body, 'hello world');
    expect(firstWithMessage.single.state, MessageState.pending);
    expect(firstWithMessage.single.authorUserId, userId);

    await chatListSub.cancel();
    await messagesSub.cancel();
    await scheduler.stop();
    await store.close();
  });

  test('createGroup inserts channel + members and enqueues CHANNEL_CREATE op',
      () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final clock = FakeClock(3000000);
    final ws = _StubTransport();
    final rest = _StubTransport(connected: false);
    final scheduler = SyncScheduler(
      store: store,
      wsTransport: ws,
      restTransport: rest,
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
      clock: clock,
    );
    await scheduler.start();

    final chat = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: AuthClient(baseUrl: Uri.parse('http://localhost')),
      uuidGen: Uuid7Gen(userIdBits: 0xA1B2C3D4E),
      clock: clock,
    );

    const creator = 'u-creator';
    final members = ['u-alice', 'u-bob', 'u-carol'];

    final channelId = await chat.createGroup(
      name: 'Weekend Trip',
      creatorUserId: creator,
      memberUserIds: members,
    );

    // Channel row.
    final channels = await store.db
        .query('channels', where: 'channel_id = ?', whereArgs: [channelId]);
    expect(channels, hasLength(1));
    expect(channels.single['kind'], 'group');
    expect(channels.single['name'], 'Weekend Trip');
    expect(channels.single['owner_user_id'], creator);

    // Membership: creator + 3 members.
    final memberRows = await store.db.query(
      'channel_members',
      where: 'channel_id = ? AND removed_at IS NULL',
      whereArgs: [channelId],
    );
    expect(memberRows, hasLength(4));
    final memberIds =
        memberRows.map((r) => r['user_id'] as String).toSet();
    expect(memberIds, {creator, ...members});
    final creatorRow =
        memberRows.firstWhere((r) => r['user_id'] == creator);
    expect(creatorRow['role'], 'owner');

    // Outbound op: REST CHANNEL_CREATE, resource_seq=1.
    final ops = await store.db.query('outbound_ops',
        where: 'resource_id = ?', whereArgs: [channelId]);
    expect(ops, hasLength(1));
    expect(ops.single['transport'], 'rest');
    expect(ops.single['rest_method'], 'POST');
    expect(ops.single['rest_path'], '/v3.0/channels');
    expect(ops.single['resource_seq'], 1);

    // Fresh subscribe to the Groups tab watcher surfaces the new group
    // for the creator. Subscribing post-createGroup mirrors the real-
    // app flow: the screen pushReplaces into ChatScreen, so the Groups
    // tab stream is re-subscribed on its next visit.
    final groups = <List<ChannelListEntry>>[];
    final groupsSub = chat
        .watchMemberChannels(userId: creator, kind: 'group')
        .listen(groups.add);
    await _pumpEventQueue();
    expect(groups.last, hasLength(1));
    expect(groups.last.single.channelId, channelId);
    expect(groups.last.single.kind, 'group');
    expect(groups.last.single.name, 'Weekend Trip');

    await groupsSub.cancel();
    await scheduler.stop();
    await store.close();
  });

  test(
      'reseedForUser swaps the user_id bits embedded in subsequent op_ids',
      () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final clock = FakeClock(2000000);
    final ws = _StubTransport();
    final rest = _StubTransport(connected: false);
    final scheduler = SyncScheduler(
      store: store,
      wsTransport: ws,
      restTransport: rest,
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
      clock: clock,
    );
    await scheduler.start();

    final chat = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: AuthClient(baseUrl: Uri.parse('http://localhost')),
      // Boot seed: zero bits, as main.dart does pre-login.
      uuidGen: Uuid7Gen(userIdBits: 0),
      clock: clock,
    );

    const channelId = 'c-1';
    await store.insertChannel(
      channelId: channelId,
      kind: 'one_to_one',
      ownerUserId: 'u-0',
      createdAt: clock.nowMs(),
    );

    // Pre-reseed send. op_id embeds zero bits — SYNC_PROTOCOL §3 the
    // server would reject this as prefix_mismatch if it escaped to
    // the wire.
    await chat.sendMessage(
      channelId: channelId,
      body: 'pre-login',
      authorUserId: 'u-0',
    );

    // Simulate OTP verify completing mid-session.
    const userIdHex = 'a3f2e8c5d'; // 9 hex chars — AUTH_CONTRACT §2
    chat.reseedForUser(userIdHex);

    clock.advance(const Duration(milliseconds: 5));
    await chat.sendMessage(
      channelId: channelId,
      body: 'post-login',
      authorUserId: 'u-1',
    );

    final ops = await store.db.query('outbound_ops',
        orderBy: 'resource_seq ASC');
    expect(ops, hasLength(2));

    final preOpId = ops[0]['op_id'] as String;
    final postOpId = ops[1]['op_id'] as String;

    // Bit layout per SPIKE_B_SYNC.md §4:
    //   2 bits variant (10) | 36 bits user_id | 4 bits device | 18 bits random
    // lives inside bytes 8..13. Extract the 36-bit user_id from the
    // canonical UUID string.
    expect(_extractUserIdBits(preOpId), 0);
    expect(_extractUserIdBits(postOpId),
        Uuid7Gen.parseUserIdHex(userIdHex));

    await scheduler.stop();
    await store.close();
  });
}

/// Pulls the 36-bit user_id field out of a UUIDv7 produced by
/// [Uuid7Gen]. Mirrors the encoder at uuid7.dart:56-70.
int _extractUserIdBits(String uuid) {
  final hex = uuid.replaceAll('-', '');
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  // byte 8: 2 bits variant | top 6 bits of user_id (of 36)
  // byte 9..11: middle 24 bits
  // byte 12 high nibble: bottom 6 bits of user_id
  final top6 = bytes[8] & 0x3F;
  final mid8a = bytes[9];
  final mid8b = bytes[10];
  final mid8c = bytes[11];
  final bottom6 = (bytes[12] >> 2) & 0x3F;
  return (top6 << 30) |
      (mid8a << 22) |
      (mid8b << 14) |
      (mid8c << 6) |
      bottom6;
}

Future<void> _pumpEventQueue() async {
  // Two full event-queue spins — first for the StreamController
  // delivery, second for the listener's async rebuild of its
  // subscription callback chain.
  await Future<void>.delayed(const Duration(milliseconds: 5));
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

class _StubTransport implements Transport {
  final _ackCtrl = StreamController<AckFrame>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();
  TransportState _state;

  _StubTransport({bool connected = true})
      : _state = connected
            ? TransportState.connected
            : TransportState.disconnected;

  @override
  Future<void> send(OutboundFrame frame) async {}

  @override
  Stream<AckFrame> get acks => _ackCtrl.stream;

  @override
  Stream<TransportState> get state => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;
}
