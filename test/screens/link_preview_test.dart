/// Link previews in the chat (SYNC_PROTOCOL §27): the composer's card and
/// what is sent with it, and the card in a text bubble.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/chat/link_preview.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/link_preview.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const _channelId = 'c-1';
const _me = 'aaaaaaaaa';
const _peer = 'bbbbbbbbb';

pb.ChatLinkPreview _preview(String url) => pb.ChatLinkPreview(
      url: url,
      title: 'Example title',
      description: 'Example description',
      siteName: 'Example',
    );

/// A 300×157 JPEG, as a shrunk og:image.
const _ogJpeg =
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA0JCgsKCA0LCgsODg0PEyAVExISEycc'
  'HhcgLikxMC4pLSwzOko+MzZGNywtQFdBRkxOUlNSMj5aYVpQYEpRUk//2wBDAQ4O'
  'DhMREyYVFSZPNS01T09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09P'
  'T09PT09PT09PT09PT0//wAARCACdASwDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEA'
  'AAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIh'
  'MUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6'
  'Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZ'
  'mqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx'
  '8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREA'
  'AgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAV'
  'YnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hp'
  'anN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPE'
  'xcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwCj'
  'RRRXvHiBRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUU'
  'UAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFAH/9k=';

void main() {
  setUpAll(sqfliteFfiInit);

  late List<String> fetched;
  setUp(() {
    fetched = [];
    linkPreviewFetcher = (url) async {
      fetched.add(url);
      return _preview(url);
    };
  });
  tearDown(() => linkPreviewFetcher = fetchLinkPreview);

  group('composer', () {
    late TextEditingController input;
    late ComposerLinkPreview controller;
    var enabled = true;

    Future<void> pumpComposer(WidgetTester tester) async {
      input = TextEditingController();
      enabled = true;
      controller = ComposerLinkPreview(input, enabled: () => enabled);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            ComposerLinkPreviewCard(controller: controller),
            TextField(controller: input),
          ]),
        ),
      ));
    }

    testWidgets(
        'a typed link shows its preview after a moment; the ✕ '
        'drops it', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(
          find.byType(TextField), 'see https://www.example.com/a ok');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Example title'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(fetched, ['https://www.example.com/a']);
      expect(find.text('Example title'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(
          controller.previewFor(input.text)?.url, 'https://www.example.com/a');

      await tester.tap(find.byTooltip('Remove preview'));
      await tester.pump();
      expect(find.text('Example title'), findsNothing);
      expect(controller.previewFor(input.text), isNull);
      // More typing after the same link does not bring it back.
      await tester.enterText(
          find.byType(TextField), 'see https://www.example.com/a ok!');
      await tester.pump(const Duration(seconds: 1));
      expect(fetched, hasLength(1));
      expect(find.text('Example title'), findsNothing);
    });

    testWidgets('editing the link away removes it; only the first link',
        (tester) async {
      await pumpComposer(tester);
      await tester.enterText(
          find.byType(TextField), 'https://a.test/1 and https://b.test/2');
      await tester.pump(const Duration(seconds: 1));
      expect(fetched, ['https://a.test/1']);
      expect(find.text('Example title'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'no link now');
      await tester.pump();
      expect(find.text('Example title'), findsNothing);
      expect(controller.value, isNull);
    });

    testWidgets('nothing is fetched while previews are off', (tester) async {
      await pumpComposer(tester);
      enabled = false;
      await tester.enterText(find.byType(TextField), 'https://a.test/1');
      await tester.pump(const Duration(seconds: 1));
      expect(fetched, isEmpty);
      expect(find.text('Example title'), findsNothing);
    });
  });

  group('chat screen', () {
    late ChatStore store;
    late SyncScheduler scheduler;
    late ChatService chat;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)));
      }
      await tester.pump();
    }

    Future<void> pumpChat(WidgetTester tester,
        {required List<(String, String, pb.ChatLinkPreview?)> seed}) async {
      await tester.runAsync(() async {
        store = await ChatStore.open(path: inMemoryDatabasePath);
        scheduler = SyncScheduler(
          store: store,
          wsTransport: _StubTransport(),
          restTransport: _StubTransport(),
          backoff: const FixedBackoff(Duration(milliseconds: 10)),
        );
        final auth = AuthClient(baseUrl: Uri.parse('https://example.invalid'));
        chat = ChatService(
          store: store,
          scheduler: scheduler,
          authClient: auth,
          wsTransport: WsTransport(
              endpoint: Uri.parse('ws://example.invalid'), auth: auth),
          uuidGen: Uuid7Gen(userIdBits: 0xAAAAAAAAA),
          clock: Clock.system,
        );
        await store.insertChannel(
          channelId: _channelId,
          kind: 'one_to_one',
          ownerUserId: _me,
          createdAt: 1000,
        );
        final base = DateTime.now().millisecondsSinceEpoch - 60000;
        for (final (i, (id, body, preview)) in seed.indexed) {
          await store.applyInboundMessage(
            localUserId: _me,
            channelId: _channelId,
            opId: 'seed-$id',
            messageId: id,
            senderUserId: _peer,
            body: body,
            contentType: 'text/plain',
            attachments: null,
            forwardSource: null,
            replyToMessageId: null,
            clientTimestampMs: base + i,
            serverTimestampMs: base + i,
            nowMs: base + i,
            linkPreview: preview?.writeToBuffer(),
          );
        }
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        await scheduler.stop();
        await store.close();
      });
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [chatRouteObserver],
        home: ChatScreen(
          channelId: _channelId,
          channelName: 'Peer',
          channelKind: 'dm',
          chatService: chat,
          authService: _FakeAuthService(),
        ),
      ));
      await settle(tester);
    }

    testWidgets(
        'a bubble shows its preview above the text, only while the '
        'link is still the first in it', (tester) async {
      await pumpChat(tester, seed: [
        (
          '0190aaaa-0000-7000-8000-00000000b001',
          'read https://www.example.com/x',
          _preview('https://www.example.com/x'),
        ),
        (
          '0190aaaa-0000-7000-8000-00000000b002',
          'edited, the link is gone',
          _preview('https://other.test/y'),
        ),
      ]);
      expect(find.byType(LinkPreviewCard), findsOneWidget);
      expect(find.text('Example title'), findsOneWidget);
      expect(find.text('Example description'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      // Above the text, inside the same bubble.
      expect(
          tester.getTopLeft(find.byType(LinkPreviewCard)).dy,
          lessThan(tester
              .getTopLeft(find.textContaining('read https://www.example.com/x',
                  findRichText: true))
              .dy));
    });

    testWidgets(
        'sending attaches the ready preview to the message and its '
        'payload', (tester) async {
      await pumpChat(tester, seed: []);
      await tester.enterText(
          find.byType(TextField), 'look https://example.com/p');
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text('Example title'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await settle(tester);
      expect(fetched, ['https://example.com/p']);

      final rows =
          (await tester.runAsync(() => store.db.query('outbound_ops')))!;
      final payload =
          pb.ChatPayload.fromBuffer(rows.single['payload'] as List<int>);
      expect(payload.body, 'look https://example.com/p');
      expect(payload.linkPreview.title, 'Example title');
      final msg = (await tester.runAsync(() => store.db.query('messages')))!;
      expect(msg.single['link_preview'], isNotNull);
      // The composer's card went with the text; the bubble has its own.
      expect(find.text('Example title'), findsOneWidget);
      expect(find.byType(LinkPreviewCard), findsOneWidget);
    });

    testWidgets('a preview with an image lays out inside the bubble',
        (tester) async {
      // A height-capped, unbounded-width image failed the bubble's
      // intrinsic sizing and left the whole bubble blank on a phone.
      await pumpChat(tester, seed: [
        (
          '0190aaaa-0000-7000-8000-00000000b003',
          'see https://www.example.com/x',
          _preview('https://www.example.com/x')
            ..imageJpeg = base64Decode(_ogJpeg),
        ),
      ]);
      // let the JPEG decode so the image takes part in layout
      await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 300)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Example title'), findsOneWidget);
    });

    testWidgets('a forward keeps the preview', (tester) async {
      const id = '0190aaaa-0000-7000-8000-00000000b001';
      await pumpChat(tester, seed: [
        (id, 'https://example.com/f', _preview('https://example.com/f')),
      ]);
      final payload = (await tester.runAsync(() async {
        await chat.forwardMessages(
          messages: [(await store.fetchMessage(id))!],
          channelIds: [_channelId],
          authorUserId: _me,
        );
        return (await store.db.query('outbound_ops')).single['payload'];
      }))! as List<int>;
      await settle(tester); // the chat redraws with the forward
      final sent = pb.ChatPayload.fromBuffer(payload);
      expect(sent.type, pb.ChatPayloadType.TYPE_MESSAGE_FORWARD);
      expect(sent.linkPreview.url, 'https://example.com/f');
      expect(sent.linkPreview.title, 'Example title');
    });
  });
}

class _FakeAuthService extends AuthService {
  _FakeAuthService()
      : super(
          client: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          storage: _NoopStorage(),
        );

  @override
  String? get currentUserId => _me;
}

class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

/// Never connects: every op stays in `outbound_ops` to be read.
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
