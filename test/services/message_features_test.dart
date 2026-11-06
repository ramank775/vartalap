/// Decision 222's message features through ChatService: a real store, a
/// scheduler whose transports never connect, so every op stays queued
/// for the assertions to read.
library vartalap.services.message_features_test;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
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

  group('timed messages', () {
    test(
        'a timed send carries its timer; the sweep deletes it when due, '
        'not before', () async {
      await chat.sendMessage(
          channelId: dm, body: 'OTP 1234', authorUserId: self, timerSec: 1);
      final m = await newest();
      expect(m.timerSec, 1);
      final op = (await store.db.query('outbound_ops')).single;
      expect(
          ttlSecOf(OutboundOpRow(
            opId: op['op_id'] as String,
            transport: OpTransport.ws,
            kind: OpKind.chatPayload,
            restMethod: null,
            restPath: null,
            resourceId: dm,
            payload: op['payload'] as List<int>,
            status: OpStatus.pending,
            attempts: 0,
            nextRetryAt: 0,
            dispatchedAt: null,
            lastError: null,
            acknowledgedAt: null,
            createdAt: 0,
            targetMessageId: m.messageId,
            targetChannelId: dm,
          )),
          1);
      await store.applyAckSuccess(
          opId: op['op_id'] as String,
          messageId: m.messageId,
          serverTimestampMs: t0,
          nowMs: t0);

      chat.startExpiry();
      addTearDown(chat.stopExpiry);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await store.fetchMessage(m.messageId), isNotNull);
      // Its second is up; the armed timer fires on real time.
      clock.advance(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(await store.fetchMessage(m.messageId), isNull);
    });
  });

  group('secure messages', () {
    Future<pb.ChatPayload> sentPayload() async => pb.ChatPayload.fromBuffer(
        (await store.db.query('outbound_ops')).last['payload'] as List<int>);

    test(
        'screen lock: the box and its key go in the payload, the secret '
        'never in a body; this phone opens its own copy', () async {
      await chat.sendSecure(
          channelId: dm, secret: 'PIN 4321', authorUserId: self, timerSec: 60);
      final p = await sentPayload();
      expect([p.contentType, p.hasBody(), p.secureKey.length, p.timerSec],
          [kSecureType, false, 32, 60]);
      expect(openSecret(p.secureBox, key: p.secureKey), 'PIN 4321');
      final m = await newest();
      expect([m.body, m.contentType, m.timerSec], [null, kSecureType, 60]);
      expect(ChatService.secureUnlock(m), SecureUnlock.screenLock);
      expect(await chat.openSecure(m), 'PIN 4321');
      expect(await store.searchMessages(query: '4321'), isEmpty);
    });

    test(
        'password: no key travels; the right password opens it, a wrong '
        'one does not', () async {
      await chat.sendSecure(
          channelId: dm,
          secret: 'door code 1985',
          authorUserId: self,
          password: 'tulip');
      final p = await sentPayload();
      expect(p.hasSecureKey(), isFalse);
      final m = await newest();
      expect(ChatService.secureUnlock(m), SecureUnlock.password);
      expect(await chat.openSecure(m, password: 'tulip'), 'door code 1985');
      await expectLater(
          chat.openSecure(m, password: 'rose'), throwsA(isA<SecretLocked>()));
    });
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
