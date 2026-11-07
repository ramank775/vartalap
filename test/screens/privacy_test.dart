/// Decision 223, track F: Settings › Privacy's presence rows and the DM header's
/// "online" / "last seen" line; last seen by labels (decision 226).
library vartalap.screens.privacy_test;

import 'dart:convert';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/screens/chat/presence_line.dart';
import 'package:vartalap/screens/settings/privacy.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const self = '0a11ce001';
const bob = '0b0b00002';

void main() {
  setUpAll(sqfliteFfiInit);

  late ChatStore store;
  late WsTransport ws;
  late ChatService chat;

  /// The bodies of `PATCH /users/me`; [offline] fails every request.
  final patches = <Map<String, dynamic>>[];
  var offline = false;
  final server = MockClient((req) async {
    if (offline) throw http.ClientException('offline');
    if (req.method == 'PATCH') {
      patches.add(jsonDecode(req.body) as Map<String, dynamic>);
    }
    return http.Response('{}', 200);
  });

  Future<void> openChat(WidgetTester tester) async {
    patches.clear();
    offline = false;
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      store = await ChatStore.open(path: inMemoryDatabasePath);
      final dm = dmChannelId(self, bob);
      await store.insertChannel(
          channelId: dm, kind: 'one_to_one', ownerUserId: self, createdAt: 1);
      for (final m in [self, bob]) {
        await store.insertChannelMember(
            channelId: dm, userId: m, role: 'member', joinedAt: 1);
      }
    });
    ws = WsTransport(
      endpoint: Uri.parse('ws://example.invalid/wss'),
      auth: AuthClient(baseUrl: Uri.parse('http://example.invalid')),
    );
    chat = ChatService(
      store: store,
      scheduler: SyncScheduler(
        store: store,
        wsTransport: _Offline(),
        restTransport: _Offline(),
        backoff: const FixedBackoff(Duration(milliseconds: 10)),
      ),
      authClient:
          AuthClient(baseUrl: Uri.parse('http://localhost'), httpClient: server)
            ..restoreSession(accesskey: 'a', userId: self),
      wsTransport: ws,
      uuidGen: Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(self)),
      clock: Clock.system,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      chat.stopPresence();
      await tester.runAsync(store.close);
    });
  }

  /// Real time for the store, then a frame.
  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  void presenceFrom(String from, {bool online = false, int lastSeenMs = 0}) =>
      ws.injectPush(InboundEnvelope(
        opId: '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0001',
        channelId: dmChannelId(self, from),
        senderUserId: from,
        peer: self,
        payload: [
          0x53,
          ...pb.ServerEventPayload(
            type: pb.ServerEventType.PRESENCE,
            presence: pb.Presence(
                userId: from,
                online: online,
                lastSeenMs: fixnum.Int64(lastSeenMs)),
          ).writeToBuffer(),
        ],
        ephemeral: true,
        flags: FrameClass.presence.flags,
      ));

  group('presenceText', () {
    testWidgets('online, today, yesterday, this week, then the date',
        (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox.shrink();
        }),
      ));
      final now = DateTime(2026, 11, 6, 15, 0);
      String? at(DateTime t) => presenceText(
          context, (online: false, lastSeenMs: t.millisecondsSinceEpoch),
          now: now);

      expect(presenceText(context, (online: true, lastSeenMs: 5)), 'online');
      expect(presenceText(context, null), isNull);
      expect(presenceText(context, (online: false, lastSeenMs: 0)), isNull);
      expect(at(DateTime(2026, 11, 6, 10, 42)), 'last seen today at 10:42 AM');
      expect(
          at(DateTime(2026, 11, 5, 22, 5)), 'last seen yesterday at 10:05 PM');
      expect(at(DateTime(2026, 11, 2, 9, 0)), 'last seen Monday at 9:00 AM');
      expect(at(DateTime(2026, 10, 12, 9, 0)), 'last seen Oct 12, 2026');
    });
  });

  testWidgets('the header line shows the watched peer, and typing wins',
      (tester) async {
    await openChat(tester);
    Widget line({required bool typing}) => MaterialApp(
          home: Scaffold(
            body: PresenceLine(
              chatService: chat,
              channelId: dmChannelId(self, bob),
              typing: typing,
              color: Colors.white,
            ),
          ),
        );
    await tester.pumpWidget(line(typing: false));
    await settle(tester);
    expect(find.byType(Text), findsNothing, reason: 'nothing known yet');

    presenceFrom(bob, online: true);
    await settle(tester);
    expect(find.text('online'), findsOneWidget);

    await tester.pumpWidget(line(typing: true));
    expect(find.text('typing…'), findsOneWidget);
    expect(find.text('online'), findsNothing);

    await tester.pumpWidget(line(typing: false));
    presenceFrom(bob);
    await settle(tester);
    expect(find.byType(Text), findsNothing, reason: 'the server says nothing');
  });

  testWidgets('Privacy: last seen from the server, changed through it',
      (tester) async {
    await openChat(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          PresencePrivacyRows(authService: _FakeAuthService(), chatService: chat),
        ]),
      ),
    ));
    await settle(tester);
    expect(find.text('Everyone'), findsOneWidget);

    await tester.tap(find.text('Last seen and online'));
    await tester.pumpAndSettle();
    expect(find.text('My contacts'), findsOneWidget);
    expect(find.text('My contacts except…'), findsOneWidget);
    expect(find.text('Only share with…'), findsOneWidget);
    expect(find.textContaining("you won't be able to see other people's"),
        findsOneWidget);
    await tester.tap(find.text('Nobody'));
    await settle(tester);
    await settle(tester);
    await tester.pumpAndSettle();
    expect(patches, [
      {'presence': 'nobody'}
    ]);
    expect(find.text('Nobody'), findsOneWidget);

    offline = true;
    await tester.tap(find.text('Last seen and online'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My contacts'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't change it"), findsOneWidget);
    expect(find.text('Nobody'), findsOneWidget, reason: 'unchanged');
  });

  testWidgets('Privacy: only share with the people in labels (decision 226)',
      (tester) async {
    await openChat(tester);
    final family = (await tester.runAsync(chat.fetchLabels))!
        .firstWhere((l) => l.name == 'Family');
    await tester.runAsync(() => chat.setLabelMembers(family.labelId, {bob}));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          PresencePrivacyRows(authService: _FakeAuthService(), chatService: chat),
        ]),
      ),
    ));
    await settle(tester);

    await tester.tap(find.text('Last seen and online'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only share with…'));
    await tester.pumpAndSettle();
    expect(find.text('Only share with'), findsOneWidget, reason: 'the picker');
    expect(find.text('1 person'), findsOneWidget);
    await tester.tap(find.text('Family'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    await tester.pumpAndSettle();
    expect(patches.last, {
      'presence': 'only',
      'presenceUsers': [bob],
    });
    expect(find.text('Only share with Family'), findsOneWidget);

    // the picked one again opens its labels, ticked
    await tester.tap(find.text('Last seen and online'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only share with…'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, 'Family'))
            .value,
        isTrue);
    await tester.tap(find.text('OK'));
    await settle(tester);
    await settle(tester);
  });

  testWidgets('Privacy: the read receipts and typing switches', (tester) async {
    await openChat(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          PresencePrivacyRows(
              authService: _FakeAuthService(), chatService: chat),
        ]),
      ),
    ));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Read receipts are always sent for group'),
        findsOneWidget);

    await tester.tap(find.text('Read receipts'));
    await tester.tap(find.text('Typing indicator'));
    await tester.pumpAndSettle();
    expect(chat.readReceipts.value, isFalse);
    expect(chat.typingIndicator.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kReadReceiptsPrefKey), isFalse);
    expect(prefs.getBool(kTypingIndicatorPrefKey), isFalse);
    final switches =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(switches.map((s) => s.value), [false, false]);
  });
}

class _FakeAuthService extends AuthService {
  _FakeAuthService()
      : super(
          client: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          storage: _NoopStorage(),
        );

  @override
  Future<String> presenceSetting() async => 'everyone';
}

class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

class _Offline implements Transport {
  @override
  TransportState get currentState => TransportState.disconnected;

  @override
  Stream<TransportState> get state => const Stream.empty();

  @override
  Stream<AckFrame> get acks => const Stream.empty();

  @override
  Future<void> send(OutboundFrame frame) async {}
}
