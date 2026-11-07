/// Share-to: what the Android side hands over, and the flow from "Send
/// to…" through the send preview into ChatService (a real store, nothing
/// connected, so every send stays readable in the store).
library vartalap.screens.share_to_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/chat/share_to.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart'
    show sealedAttachmentOverhead;
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const me = 'aaaaaaaaa';
const peer = 'bbbbbbbbb';
const family = '0190aaaa-0000-7000-8000-0000000000c1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('share_to_test');
    AssetCache.dirProvider = () async => Directory('${tmp.path}/assets');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Files the Android side copied, in a share folder of their own.
  SharedItems shared({List<String> names = const [], String text = ''}) {
    final dir = Directory('${tmp.path}/share')..createSync();
    return SharedItems(
      dir: dir.path,
      text: text,
      paths: [
        for (final (i, n) in names.indexed)
          (File('${dir.path}/$i/$n')
                ..createSync(recursive: true)
                ..writeAsBytesSync(List.filled(2048, i)))
              .path,
      ],
    );
  }

  group('SharedItems', () {
    test('reads what the Android side took, and what it left out', () {
      final s = SharedItems.fromMap({
        'dir': '/cache/share/1',
        'files': ['/cache/share/1/0/a.jpg', '/cache/share/1/1/b.pdf'],
        'text': '  https://example.org/x  ',
        'tooBig': ['film.mp4'],
        'tooMany': 3,
        'unreadable': 1,
      });
      expect(s.paths, ['/cache/share/1/0/a.jpg', '/cache/share/1/1/b.pdf']);
      expect(s.text, 'https://example.org/x');
      expect(s.dir, '/cache/share/1');
      expect(s.isEmpty, isFalse);
      expect(
          s.leftOut,
          'Too big to send (over 25 MB): film.mp4\n'
          'You can send up to 30 files at a time. 3 were left out.\n'
          "1 file couldn't be read.");
    });

    test('a share with nothing usable is empty and says nothing', () {
      final s = SharedItems.fromMap({'files': <Object?>[], 'text': null});
      expect(s.isEmpty, isTrue);
      expect(s.leftOut, isNull);
    });

    test('discard deletes the copies, and twice is fine', () async {
      final s = shared(names: ['a.jpg']);
      await s.discard();
      expect(Directory(s.dir!).existsSync(), isFalse);
      await s.discard();
    });
  });

  test('photos and videos go as media; the rest as documents', () {
    for (final p in ['a.jpg', 'b.PNG', 'c.gif', 'd.mp4', 'e.mov']) {
      expect(isSharedMedia('/x/$p'), isTrue, reason: p);
    }
    for (final p in ['a.pdf', 'b.mp3', 'c.zip', 'd.docx', 'noext']) {
      expect(isSharedMedia('/x/$p'), isFalse, reason: p);
    }
  });

  test('listenForShares takes the launch share, then each one after', () async {
    const channel = MethodChannel('vartalap/share');
    final asked = <Object?>[];
    var n = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked.add(call.arguments);
      n++;
      return {
        'files': <String>[],
        'text': 'share $n',
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final got = <String>[];
    listenForShares((s) => got.add(s.text));
    await pumpEventQueue();
    expect(got, ['share 1']);
    expect(asked.single, {
      'maxBytes': AssetClient.maxUploadBytes - sealedAttachmentOverhead,
      'maxFiles': kMaxShareFiles,
    });

    // MainActivity.onNewIntent: a share while the app runs
    await messenger.handlePlatformMessage(
        'vartalap/share',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('ready')),
        (_) {});
    await pumpEventQueue();
    expect(got, ['share 1', 'share 2']);
  });

  group('the flow', () {
    late ChatStore store;
    late ChatService chat;

    /// sqflite_ffi and file copies answer on the real event loop.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)));
      }
      await tester.pump();
    }

    /// A group we are in and a connected person; [share] starts from a
    /// home screen, as main.dart starts it, by [user].
    Future<void> start(WidgetTester tester, SharedItems share,
        {String? user = me}) async {
      await tester.runAsync(() async {
        store = await ChatStore.open(path: inMemoryDatabasePath);
        chat = ChatService(
          store: store,
          scheduler: SyncScheduler(
            store: store,
            wsTransport: _Offline(),
            restTransport: _Offline(),
            backoff: const FixedBackoff(Duration(milliseconds: 10)),
          ),
          authClient: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          wsTransport: WsTransport(
            endpoint: Uri.parse('ws://example.invalid'),
            auth: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          ),
          uuidGen: Uuid7Gen(userIdBits: 0xAAAAAAAAA),
          clock: Clock.system,
        );
        await store.insertChannel(
            channelId: family,
            kind: 'group',
            ownerUserId: me,
            createdAt: 1000,
            name: 'Family');
        await store.insertChannelMember(
            channelId: family, userId: me, role: 'owner', joinedAt: 1);
        await store.upsertContact(userId: peer, username: 'peer', nowMs: 1);
        await store
            .replaceConnections(connected: [peer], blocked: [], invites: []);
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        await store.close();
      });
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [chatRouteObserver],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => sendShared(Navigator.of(context), share,
                  chatService: chat, authService: _Auth(user)),
              child: const Text('chat list'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('chat list'));
      await settle(tester);
    }

    /// Oldest first.
    Future<List<MessageRow>> sentTo(
            WidgetTester tester, String channelId) async =>
        (await tester.runAsync(() => store.fetchChannelMessages(channelId)))!
            .reversed
            .toList();

    pb.Attachment attachment(MessageRow m) =>
        pb.ChatPayload.fromBuffer(m.attachments!).attachments.single;

    Future<void> pick(WidgetTester tester, List<String> chats) async {
      expect(find.text('Send to…'), findsOneWidget);
      for (final c in chats) {
        await tester.tap(find.text(c));
        await settle(tester);
      }
      await tester.tap(find.byTooltip('Send'));
      await settle(tester);
    }

    testWidgets(
        'photos and a PDF to one chat: preview, caption on the first, the '
        'photo sized as media, the PDF byte for byte, then the chat opens',
        (tester) async {
      // The Android side of preparePhoto (MediaPrep.kt).
      const media = MethodChannel('vartalap/media');
      messenger.setMockMethodCallHandler(media, (call) async {
        final args = call.arguments as Map;
        if (call.method != 'photo') return null;
        File(args['out'] as String).writeAsBytesSync([1, 2, 3]);
        return [640, 480];
      });
      addTearDown(() => messenger.setMockMethodCallHandler(media, null));
      final share = shared(names: ['beach.jpg', 'report.pdf']);
      await start(tester, share);

      await pick(tester, ['Family']);
      // The send preview, both items in its strip.
      await tester.tap(find.bySemanticsLabel('report.pdf'));
      await tester.pump();
      expect(find.text('report.pdf'), findsOneWidget, reason: 'its card');
      expect(find.byTooltip('Standard quality'), findsOneWidget,
          reason: 'a photo is among them: HD is on offer');
      await tester.enterText(find.byType(TextField), 'Goa trip');
      await tester.tap(find.bySemanticsLabel('Send'));
      await settle(tester);
      await settle(tester);

      expect(find.byType(ChatScreen), findsOneWidget);
      final sent = await sentTo(tester, family);
      expect([for (final m in sent) m.contentType],
          ['image/jpeg', 'application/pdf']);
      expect([for (final m in sent) m.body], ['Goa trip', null]);
      final photo = attachment(sent[0]);
      expect((photo.width, photo.height), (640, 480),
          reason: 'sized by preparePhoto, as from the gallery');
      expect(photo.sizeBytes.toInt(), 3);
      final pdf = attachment(sent[1]);
      expect(pdf.filename, 'report.pdf');
      expect(pdf.sizeBytes.toInt(), 2048, reason: 'byte for byte');
      expect(Directory(share.dir!).existsSync(), isFalse,
          reason: 'the copies go once sent');
    });

    testWidgets(
        'back from the preview returns to the picker; back again '
        'gives up and deletes the copies', (tester) async {
      final share = shared(names: ['a.mp4']);
      await start(tester, share);
      await pick(tester, ['@peer']);
      await tester.tap(find.byTooltip('Cancel'));
      await settle(tester);
      expect(find.text('Send to…'), findsOneWidget);

      await tester.pageBack();
      await settle(tester);
      expect(find.text('chat list'), findsOneWidget);
      expect(Directory(share.dir!).existsSync(), isFalse);
      expect(await sentTo(tester, dmChannelId(me, peer)), isEmpty);
    });

    testWidgets('a link to one chat waits in its composer, unsent',
        (tester) async {
      await start(tester, shared(text: 'https://example.org/news'));
      await pick(tester, ['@peer']);

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'https://example.org/news'),
          findsOneWidget);
      expect(await sentTo(tester, dmChannelId(me, peer)), isEmpty);
    });

    testWidgets(
        'a link to several chats goes to each as a message, and the '
        'chat list shows', (tester) async {
      await start(tester, shared(text: 'https://example.org/news'));
      await pick(tester, ['Family', '@peer']);

      expect(find.text('chat list'), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);
      for (final c in [family, dmChannelId(me, peer)]) {
        final sent = await sentTo(tester, c);
        expect([for (final m in sent) m.body], ['https://example.org/news'],
            reason: c);
      }
    });

    testWidgets('signed out: nothing opens and the copies go', (tester) async {
      final share = shared(names: ['a.jpg']);
      await start(tester, share, user: null);
      expect(find.text('Send to…'), findsNothing);
      expect(Directory(share.dir!).existsSync(), isFalse);
    });

    testWidgets('what was left out is said up front', (tester) async {
      await start(
          tester,
          const SharedItems(
              text: 'hi', tooBig: ['film.mp4'], tooMany: 0, unreadable: 0));
      expect(
          find.text('Too big to send (over 25 MB): film.mp4'), findsOneWidget);
      expect(find.text('Send to…'), findsOneWidget);
    });
  });
}

class _Auth extends AuthService {
  final String? user;
  _Auth(this.user)
      : super(
          client: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          storage: _NoStorage(),
        );

  @override
  String? get currentUserId => user;
}

class _NoStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

/// Never connects, so every op stays queued.
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
