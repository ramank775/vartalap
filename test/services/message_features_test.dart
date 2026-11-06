/// Decision 222's message features through ChatService: a real store, a
/// scheduler whose transports never connect, so every op stays queued
/// for the assertions to read.
library vartalap.services.message_features_test;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const self = '0a11ce001';
const bob = '0b0b00002';
const t0 = 1700000000000;

void main() {
  setUpAll(sqfliteFfiInit);

  late ChatStore store;
  late SyncScheduler scheduler;
  late ChatService chat;
  late FakeClock clock;
  final dm = dmChannelId(self, bob);

  setUp(() async {
    store = await ChatStore.open(path: inMemoryDatabasePath);
    clock = FakeClock(t0);
    scheduler = SyncScheduler(
      store: store,
      wsTransport: _Offline(),
      restTransport: _Offline(),
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
      clock: clock,
    );
    await scheduler.start();
    chat = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: AuthClient(baseUrl: Uri.parse('http://localhost'))
        ..restoreSession(accesskey: 'a', userId: self),
      wsTransport: WsTransport(
        endpoint: Uri.parse('ws://example.invalid/wss'),
        auth: AuthClient(baseUrl: Uri.parse('http://example.invalid')),
      ),
      uuidGen: Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(self)),
      clock: clock,
    );
    await store.insertChannel(
        channelId: dm, kind: 'one_to_one', ownerUserId: self, createdAt: 1);
    for (final m in [self, bob]) {
      await store.insertChannelMember(
          channelId: dm, userId: m, role: 'member', joinedAt: 1);
    }
  });

  tearDown(() async {
    await scheduler.stop();
    await store.close();
  });

  /// The newest message in the chat.
  Future<MessageRow> newest() async =>
      (await store.fetchChannelMessages(dm, limit: 1)).single;

  /// [chat.sendMessage], then the server's ack at [ackAt].
  Future<MessageRow> sent(String body, {int? ackAt}) async {
    await chat.sendMessage(channelId: dm, body: body, authorUserId: self);
    final m = await newest();
    if (ackAt != null) {
      final op = (await store.db.query('outbound_ops',
              where: 'target_message_id = ?', whereArgs: [m.messageId]))
          .single;
      await store.applyAckSuccess(
          opId: op['op_id'] as String,
          messageId: m.messageId,
          serverTimestampMs: ackAt,
          nowMs: ackAt);
    }
    return (await store.fetchMessage(m.messageId))!;
  }

  test('edit history: every own edit keeps the body it replaced', () async {
    final m = await sent('meet at 5', ackAt: t0);
    clock.advance(const Duration(minutes: 1));
    await chat.editMessage(
        channelId: dm, messageId: m.messageId, newBody: 'meet at 6');
    clock.advance(const Duration(minutes: 1));
    await chat.editMessage(
        channelId: dm, messageId: m.messageId, newBody: 'meet at 7');
    expect([for (final v in await chat.messageVersions(m.messageId)) v.body],
        ['meet at 7', 'meet at 6', 'meet at 5']);
  });

  group('delete for everyone within 5 minutes', () {
    test(
        'offered for an unsent message, and for one sent under 5 minutes '
        'ago; not past that, nor for someone else\'s', () async {
      final unsent = await sent('not yet out');
      clock.advance(const Duration(hours: 1));
      expect(chat.canDeleteForEveryone(unsent, self), isTrue,
          reason: 'not acknowledged: it can always be cancelled');

      final m = await sent('out', ackAt: clock.nowMs());
      clock.advance(const Duration(minutes: 4, seconds: 59));
      expect(chat.canDeleteForEveryone(m, self), isTrue);
      clock.advance(const Duration(seconds: 1));
      expect(chat.canDeleteForEveryone(m, self), isFalse);
      expect(chat.canDeleteForEveryone(m, bob), isFalse);
    });

    test(
        'a delete committed late (the app died in the undo window) carries '
        'the window\'s time in its op id', () async {
      final m = await sent('oops', ackAt: t0);
      clock.advance(const Duration(minutes: 4));
      await chat.deleteMessage(messageId: m.messageId);
      final pressedEnd = clock.nowMs() + 5000;
      // Reopened a day later: the sweep commits it.
      clock.advance(const Duration(days: 1));
      await chat.sweepExpiredDeletes(dm);
      final op = (await store.db.query('outbound_ops',
              where: 'kind = ?', whereArgs: [OpKind.messageDelete]))
          .single;
      expect(uuid7Ms(op['op_id'] as String), pressedEnd);
      expect(op['created_at'], clock.nowMs(),
          reason: 'its retry budget starts now');
    });

    test('delete for me removes the row and queues nothing', () async {
      final m = await sent('mine', ackAt: t0);
      final opsBefore = (await store.db.query('outbound_ops')).length;
      await chat.deleteForMe([m.messageId]);
      expect(await store.fetchMessage(m.messageId), isNull);
      expect(await store.db.query('outbound_ops'), hasLength(opsBefore));
    });
  });
}

class _Offline implements Transport {
  @override
  Future<void> send(OutboundFrame frame) async {}

  @override
  Stream<AckFrame> get acks => const Stream.empty();

  @override
  Stream<TransportState> get state => const Stream.empty();

  @override
  TransportState get currentState => TransportState.disconnected;
}
