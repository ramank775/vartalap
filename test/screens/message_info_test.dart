/// Message info (SYNC_PROTOCOL §25.2): who got and read an own message.
library vartalap.screens.message_info_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/screens/chat/message_info.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const self = '0a11ce001';
const group = '0190aaaa-0000-7000-8000-0000000000b1';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets(
      'a group message lists who read it, who got it, and how many '
      'have neither', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    late ChatStore store;
    late SyncScheduler scheduler;
    late ChatService chat;
    await tester.runAsync(() async {
      store = await ChatStore.open(path: inMemoryDatabasePath);
      scheduler = SyncScheduler(
        store: store,
        wsTransport: _Offline(),
        restTransport: _Offline(),
        backoff: const FixedBackoff(Duration(milliseconds: 10)),
      );
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
        clock: Clock.system,
      );
      await store.insertChannel(
          channelId: group, kind: 'group', ownerUserId: self, createdAt: 1);
      for (final m in [self, 'asha', 'ravi', 'meena']) {
        await store.insertChannelMember(
            channelId: group, userId: m, role: 'member', joinedAt: 1);
      }
      await store.applyInboundMessage(
        localUserId: self,
        channelId: group,
        opId: 'op-1',
        messageId: 'm-1',
        senderUserId: self,
        body: 'dinner at 8',
        contentType: null,
        attachments: null,
        forwardSource: null,
        replyToMessageId: null,
        clientTimestampMs: now,
        serverTimestampMs: now,
        nowMs: now,
      );
      for (final (user, read) in [('asha', true), ('ravi', false)]) {
        await store.db.rawUpdate(
            'UPDATE channel_members SET delivered_up_to = ?'
            '${read ? ', read_up_to = ?' : ''} WHERE user_id = ?',
            [now, if (read) now, user]);
        await store.recordReceipt(
            channelId: group, userId: user, read: read, upTo: now, atMs: now);
      }
    });
    addTearDown(() => tester.runAsync(() async {
          await scheduler.stop();
          await store.close();
        }));
    final message = (await tester.runAsync(() => store.fetchMessage('m-1')))!;

    await tester.pumpWidget(MaterialApp(
      home: MessageInfoScreen(
        chatService: chat,
        message: message,
        group: true,
        nameOf: (id) => id.toUpperCase(),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }

    expect(find.text('dinner at 8'), findsOneWidget);
    expect(find.text('Read by'), findsOneWidget);
    expect(find.text('ASHA'), findsOneWidget);
    expect(find.text('Delivered to'), findsOneWidget);
    expect(find.text('RAVI'), findsOneWidget);
    expect(find.text('1 remaining'), findsOneWidget, reason: 'Meena');
    expect(find.textContaining('Today, '), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
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
