/// Live location's bubble and the chat-info switch (SYNC_PROTOCOL §21).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/screens/chat/rich_messages.dart';
import 'package:vartalap/screens/chat_info/live_location_controls.dart';
import 'package:vartalap/services/live_location.dart';
import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart'
    show InboundEnvelope;

const _self = 'aaaaaaaaa';
const _peer = 'bbbbbbbbb';

class _FakePlatform extends LiveLocationPlatform {
  @override
  Future<String> start(
          {bool background = false,
          String? refusedTitle,
          String? title}) async =>
      'started';

  @override
  Future<void> changed() async {}
}

void main() {
  setUpAll(sqfliteFfiInit);

  late ChatStore store;
  late LiveLocation live;
  final dm = dmChannelId(_self, _peer);

  /// sqflite_ffi answers off the widget-test clock: a real-time breather
  /// between pumps.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    await tester.pump();
  }

  Future<T> q<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      store = await ChatStore.open(path: inMemoryDatabasePath);
      await store.insertChannel(
          channelId: dm, kind: 'one_to_one', ownerUserId: _self, createdAt: 1);
      live = LiveLocation(
          store: store,
          selfUserId: _self,
          tick: () {},
          platform: _FakePlatform());
    });
    LiveLocation.instance = live;
    addTearDown(() async {
      LiveLocation.instance = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(store.close);
    });
  }

  Widget card(String body, {bool mine = false, String? messageId}) =>
      MaterialApp(
        home: Scaffold(
          body: RichMessageView(
            contentType: kLiveLocationType,
            body: body,
            tint: Colors.black,
            messageId: messageId,
            mine: mine,
          ),
        ),
      );

  group('bubble', () {
    testWidgets("someone else's share: until when, how fresh, View",
        (tester) async {
      await open(tester);
      final now = DateTime.now().millisecondsSinceEpoch;
      await tester.pumpWidget(card(
        LiveShare(
          untilMs: now + 3600000,
          point: const GeoPoint(12.9, 77.6),
          atMs: now - 2 * 60000 - 5000,
        ).encode(),
        messageId: 'm1',
      ));
      expect(find.text('Live location'), findsOneWidget);
      expect(find.textContaining('Live until '), findsOneWidget);
      expect(find.text('Updated 2 min ago'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Stop sharing'), findsNothing);
    });

    testWidgets('ended, waiting and unreadable shares say so', (tester) async {
      await open(tester);
      final now = DateTime.now().millisecondsSinceEpoch;
      await tester.pumpWidget(card(
          LiveShare(untilMs: now + 60000, endedMs: now).encode(),
          messageId: 'm1'));
      expect(find.text('Live location ended'), findsOneWidget);
      expect(find.text('View'), findsNothing, reason: 'nothing to show');

      await tester.pumpWidget(
          card(LiveShare(untilMs: now + 60000).encode(), messageId: 'm2'));
      expect(find.text('Waiting for the first position'), findsOneWidget);

      await tester.pumpWidget(card('{oops', messageId: 'm3'));
      expect(find.text('Unreadable location'), findsOneWidget);
    });

    testWidgets('our own share: Stop sharing, after a confirm, ends it',
        (tester) async {
      await open(tester);
      await q(tester, () => live.share(dm, const Duration(hours: 1)));
      final s = (await q(tester, live.shares)).single;
      await tester.pumpWidget(
          card(s.share.encode(), mine: true, messageId: s.messageId));
      expect(find.textContaining('Updated'), findsNothing,
          reason: "the sharer's own position is the service's");

      await tester.tap(find.text('Stop sharing'));
      await tester.pumpAndSettle();
      expect(find.text('Stop sharing live location?'), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await settle(tester);
      expect(await q(tester, live.shares), isEmpty);
    });

    testWidgets('View opens the position with Open in Maps', (tester) async {
      await open(tester);
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await q(tester, () async {
        const id = '0190aaaa-bbbb-7ccc-8ddd-000000000001';
        await store.applyInboundMessage(
          localUserId: _self,
          channelId: dm,
          opId: '0190aaaa-bbbb-7ccc-8ddd-000000000002',
          messageId: id,
          senderUserId: _peer,
          body: LiveShare(
                  untilMs: now + 3600000,
                  point: const GeoPoint(12.9, 77.6, accuracyM: 20),
                  atMs: now)
              .encode(),
          contentType: kLiveLocationType,
          attachments: null,
          forwardSource: null,
          replyToMessageId: null,
          clientTimestampMs: now,
          serverTimestampMs: now,
          nowMs: now,
        );
        return id;
      });
      final body = (await q(tester, () => store.fetchMessage(id)))!.body!;
      await tester.pumpWidget(card(body, messageId: id));
      await tester.tap(find.text('View'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text('Open in Maps'), findsOneWidget);
      expect(find.text('Updated just now'), findsOneWidget);
      expect(find.textContaining('Accurate to 20 m'), findsOneWidget);
      expect(find.text('Stop sharing'), findsNothing);
    });
  });

  group('chat info', () {
    Widget controls({required Future<bool> Function() ask}) => MaterialApp(
          home: Scaffold(
            body: ListView(children: [
              LiveLocationControls(
                channelId: dm,
                peerUserId: _peer,
                peerName: 'Rahul',
                live: live,
                askAllTheTime: ask,
              ),
            ]),
          ),
        );

    Future<List<pb.ChatPayload>> queued(WidgetTester tester) => q(
        tester,
        () async => [
              for (final r
                  in await store.db.query('outbound_ops', orderBy: 'rowid'))
                pb.ChatPayload.fromBuffer(r['payload'] as List<int>)
            ]);

    testWidgets(
        'the switch asks for "all the time", then allows Rahul and '
        'tells his phone; off revokes', (tester) async {
      await open(tester);
      var asked = 0;
      await tester.pumpWidget(controls(ask: () async {
        asked++;
        return true;
      }));
      await settle(tester);
      final tile = find.text('Let Rahul turn on my live location');
      expect(tile, findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.textContaining('Allow all the time'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(asked, 1);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue);
      expect(await q(tester, () => live.allows(_peer)), isTrue);
      final [permission] = await queued(tester);
      expect(permission.liveLocationAllowed, isTrue);

      await tester.tap(tile);
      await settle(tester);
      expect(await q(tester, () => live.allows(_peer)), isFalse);
      expect((await queued(tester)).last.liveLocationAllowed, isFalse);
    });

    testWidgets('without "all the time" the switch stays off', (tester) async {
      await open(tester);
      await tester.pumpWidget(controls(ask: () async => false));
      await settle(tester);
      await tester.tap(find.text('Let Rahul turn on my live location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse);
      expect(await q(tester, () => live.allows(_peer)), isFalse);
      expect(await queued(tester), isEmpty);
    });

    testWidgets(
        'when Rahul allows us: Turn on asks his phone for the time '
        'picked', (tester) async {
      await open(tester);
      await q(tester, () async {
        final allow = pb.ChatPayload(
            version: 1,
            type: pb.ChatPayloadType.TYPE_LIVE_LOCATION_PERMISSION,
            liveLocationAllowed: true);
        await live.apply(
            InboundEnvelope(
              opId: '0190aaaa-bbbb-7ccc-8ddd-000000000003',
              channelId: dm,
              senderUserId: _peer,
              payload: allow.writeToBuffer(),
            ),
            allow);
      });
      await tester.pumpWidget(controls(ask: () async => true));
      await settle(tester);
      expect(find.text("Rahul's live location"), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 hour'));
      await settle(tester);
      final [control] = await queued(tester);
      expect(control.type, pb.ChatPayloadType.TYPE_LIVE_LOCATION_CONTROL);
      expect(control.liveLocationDurationSec, 3600);
    });
  });
}
