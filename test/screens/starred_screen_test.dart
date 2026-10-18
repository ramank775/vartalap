/// Starred messages: the Star action in the chat's selection bar, the
/// star glyph in a bubble, and the Starred messages screen.
///
/// Same harness as chat_screen_test.dart: a real [ChatStore] and
/// [ChatService] over in-memory sqlite, transports stubbed and never
/// connected. Starring is local-only, so nothing here reaches them.
library vartalap.screens.starred_screen_test;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/starred/starred.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const String channelId = 'c-1';
const String localUserId = 'aaaaaaaaa';
const String peerUserId = 'bbbbbbbbb';

void main() {
  setUpAll(sqfliteFfiInit);

  late ChatStore store;
  late SyncScheduler scheduler;
  late ChatService chat;

  /// sqflite_ffi resolves its futures off the widget-test fake clock, so
  /// every DB-touching beat needs a real-time breather before the next
  /// pump.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pump();
  }

  Future<T> q<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  /// A DM with "Peer" holding one message each way, and [home] on top.
  Future<void> pump(WidgetTester tester, Widget Function() home) async {
    await tester.runAsync(() async {
      store = await ChatStore.open(path: inMemoryDatabasePath);
      scheduler = SyncScheduler(
        store: store,
        wsTransport: _StubTransport(),
        restTransport: _StubTransport(),
        backoff: const FixedBackoff(Duration(milliseconds: 10)),
      );
      chat = ChatService(
        store: store,
        scheduler: scheduler,
        authClient: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
        wsTransport: WsTransport(
          endpoint: Uri.parse('ws://example.invalid'),
          auth: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
        ),
        uuidGen: Uuid7Gen(userIdBits: 0xAAAAAAAAA),
        clock: Clock.system,
      );
      await store.insertChannel(
        channelId: channelId,
        kind: 'one_to_one',
        ownerUserId: localUserId,
        createdAt: 1000,
      );
      await store.insertChannelMember(
        channelId: channelId,
        userId: peerUserId,
        role: 'member',
        joinedAt: 1000,
      );
      await store.upsertContact(
        userId: peerUserId,
        contactBookName: 'Peer',
        nowMs: 1000,
      );
      await _insert(store, 'm-mine', localUserId, 'my own message', 1);
      await _insert(store, 'm-peer', peerUserId, 'their message', 2);
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await scheduler.stop();
      await store.close();
    });
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [chatRouteObserver],
      home: home(),
    ));
    await settle(tester);
  }

  Future<void> longPress(WidgetTester tester, String text) async {
    await tester.longPress(find.textContaining(text));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Star in the selection bar puts a star by the time; Unstar '
      'takes it off', (tester) async {
    await pump(
      tester,
      () => ChatScreen(
        channelId: channelId,
        channelName: 'Peer',
        channelKind: 'one_to_one',
        chatService: chat,
        authService: _FakeAuthService(),
      ),
    );
    expect(find.byIcon(Icons.star), findsNothing);

    await longPress(tester, 'their message');
    expect(find.byTooltip('Unstar'), findsNothing);
    await tester.tap(find.byTooltip('Star'));
    await settle(tester);
    expect(find.byTooltip('Star'), findsNothing,
        reason: 'starring lets go of the selection');
    expect(find.byIcon(Icons.star), findsOneWidget,
        reason: 'the glyph in the bubble');
    expect((await q(tester, () => store.fetchMessage('m-peer')))!.starredAtMs,
        isNotNull);

    // A mixed selection offers Star, not Unstar.
    await longPress(tester, 'their message');
    // The reaction bar's follower layer confuses tap()'s hit-test probe;
    // the tap itself lands, as the count shows.
    await tester.tap(find.textContaining('my own message'),
        warnIfMissed: false);
    await settle(tester);
    expect(find.text('2'), findsOneWidget);
    expect(find.byTooltip('Star'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel'));
    await settle(tester);

    await longPress(tester, 'their message');
    await tester.tap(find.byTooltip('Unstar'));
    await settle(tester);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('Starred messages lists what is starred, unstars on a '
      'long-press and opens the chat at the message', (tester) async {
    await pump(
      tester,
      () => StarredMessagesScreen(
        chatService: chat,
        authService: _FakeAuthService(),
      ),
    );
    expect(find.textContaining('Tap and hold on any message'), findsOneWidget);

    await q(tester, () => chat.setStarred(['m-mine', 'm-peer'], true));
    await settle(tester);
    expect(find.textContaining('Tap and hold'), findsNothing);
    expect(find.text('You ▸ Peer'), findsOneWidget);
    expect(find.text('Peer ▸ You'), findsOneWidget);

    await longPress(tester, 'my own message');
    await tester.tap(find.text('Unstar'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400)); // sheet closes
    expect(find.text('my own message'), findsNothing);
    expect(find.text('their message'), findsOneWidget);

    await tester.tap(find.text('their message'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400)); // route animates
    await settle(tester);
    final opened = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(opened.channelId, channelId);
    expect(opened.initialMessageId, 'm-peer');
    expect(find.textContaining('my own message'), findsOneWidget,
        reason: 'the chat itself, not the list');
  });
}

Future<void> _insert(
  ChatStore store,
  String messageId,
  String authorUserId,
  String body,
  int seq,
) =>
    store.applyInboundMessage(
      localUserId: localUserId,
      channelId: channelId,
      opId: 'seed-$messageId',
      messageId: messageId,
      senderUserId: authorUserId,
      body: body,
      contentType: 'text/plain',
      attachments: null,
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: 1000 + seq,
      serverTimestampMs: 1000 + seq,
      nowMs: 1000 + seq,
    );

class _FakeAuthService extends AuthService {
  _FakeAuthService()
      : super(
          client: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          storage: _NoopStorage(),
        );

  @override
  String? get currentUserId => localUserId;
}

class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

class _StubTransport implements Transport {
  @override
  TransportState get currentState => TransportState.disconnected;

  @override
  Stream<TransportState> get state => const Stream.empty();

  @override
  Stream<AckFrame> get acks => const Stream.empty();

  @override
  Future<void> send(OutboundFrame frame) async {}
}
