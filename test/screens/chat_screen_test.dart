/// ChatScreen widget tests — the message long-press sheet (frame d3)
/// and the 5-second Undo window (V3_ARCHITECTURE decision 11).
///
/// Runs against a real [ChatStore] and a real [ChatService]; only the
/// transports are stubs, and they stay disconnected on purpose so every
/// outbound op parks in `outbound_ops` where the assertions can read it.
/// What the screen is being asked to prove is *which ops it enqueues*,
/// not what the wire does with them.
library vartalap.screens.chat_screen_test;

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

import '../fake_asset_cache.dart';

const String channelId = 'c-1';
const String localUserId = 'aaaaaaaaa';
const String peerUserId = 'bbbbbbbbb';
/// The production value. The commit timer is an ordinary Dart timer, so
/// a widget test can reach the other side of it by pumping the fake
/// clock — no reason to shorten the window under test.
const Duration undoWindow = Duration(seconds: 5);

void main() {
  setUpAll(sqfliteFfiInit);

  late ChatStore store;
  late SyncScheduler scheduler;
  late ChatService chat;

  /// sqflite_ffi resolves its futures off the widget-test fake clock, so
  /// every DB-touching beat needs a real-time breather before the next
  /// pump. One helper, used after every interaction.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pump();
  }

  Future<void> pumpChat(WidgetTester tester) async {
    await tester.runAsync(() async {
      store = await ChatStore.open(path: inMemoryDatabasePath);
      final ws = _StubTransport();
      scheduler = SyncScheduler(
        store: store,
        wsTransport: ws,
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
      await _insert(store, 'm-mine', localUserId, 'my own message', 1);
      await _insert(store, 'm-peer', peerUserId, 'their message', 2);
    });
    addTearDown(() async {
      // Unmount before closing: ChatScreen.dispose flushes a pending
      // delete, and it needs a live store to flush into.
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await scheduler.stop();
      await store.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        channelId: channelId,
        channelName: 'Peer',
        channelKind: 'dm',
        chatService: chat,
        authService: _FakeAuthService(),
        undoWindow: undoWindow,
      ),
    ));
    await settle(tester);
  }

  /// sqflite_ffi answers on the real event loop, which a widget test's
  /// fake clock never reaches — so every store read the assertions make
  /// has to run inside `runAsync`.
  Future<T> q<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<List<Map<String, Object?>>> ops(WidgetTester tester) =>
      q(tester, () => store.db.query('outbound_ops', orderBy: 'created_at'));

  /// Long-press and let the sheet's entry animation run. Every beat in
  /// this file is pumped by hand: the chat screen holds indeterminate
  /// progress indicators, which never settle.
  Future<void> longPress(WidgetTester tester, String body) async {
    await tester.longPress(find.text(body));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('sheet on my own message offers Edit and Delete; a peer '
      'message offers neither', (tester) async {
    await pumpChat(tester);

    await longPress(tester, 'my own message');
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await tester.pump(const Duration(milliseconds: 400));

    await longPress(tester, 'their message');
    expect(find.text('Reply'), findsOneWidget);
    expect(
      find.text('Edit'),
      findsNothing,
      reason: 'SYNC_PROTOCOL §6a.3: recipients drop an UPDATE that is not '
          "from the author, so editing someone else's message would be a "
          'button that provably does nothing.',
    );
    expect(find.text('Delete for everyone'), findsNothing);
  });

  testWidgets('React writes a local reaction row and enqueues REACTION_ADD; '
      'tapping the same emoji again removes it', (tester) async {
    await pumpChat(tester);
    await longPress(tester, 'their message');

    await tester.tap(find.byKey(const ValueKey('react-\u{1F44D}')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    final reactions = await q(tester, () => store.db.query('reactions'));
    expect(reactions, hasLength(1));
    expect(reactions.single['user_id'], localUserId);
    expect(reactions.single['emoji'], '\u{1F44D}');

    final added = (await ops(tester)).last;
    expect(added['kind'], OpKind.messageReaction);
    expect(
      _payload(added).type,
      pb.ChatPayloadType.TYPE_REACTION_ADD,
      reason: 'docs/proto/v3-chat-payload.proto: a reaction rides the same '
          'opaque ChatPayload as everything else.',
    );
    expect(_payload(added).messageId, 'm-peer');

    // The chip is rendered, and tapping it toggles our own reaction off.
    await settle(tester);
    expect(find.byKey(const ValueKey('chip-\u{1F44D}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chip-\u{1F44D}')));
    await settle(tester);

    expect(await q(tester, () => store.db.query('reactions')), isEmpty);
    expect(
      _payload((await ops(tester)).last).type,
      pb.ChatPayloadType.TYPE_REACTION_REMOVE,
    );
  });

  testWidgets('Edit loads the body into the composer and sends a '
      'MESSAGE_UPDATE marked edited', (tester) async {
    await pumpChat(tester);
    await longPress(tester, 'my own message');

    await tester.tap(find.text('Edit'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Editing message'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'my corrected message');
    await tester.tap(find.byIcon(Icons.check_rounded));
    await settle(tester);

    final row = await q(tester, () => store.fetchMessage('m-mine'));
    expect(row?.body, 'my corrected message');
    expect(row?.isEdited, isTrue);
    await settle(tester);
    expect(find.text('Editing message'), findsNothing);

    final op = (await ops(tester)).last;
    expect(op['kind'], OpKind.messageEdit);
    expect(_payload(op).type, pb.ChatPayloadType.TYPE_MESSAGE_UPDATE);
    expect(_payload(op).body, 'my corrected message');
  });

  testWidgets('Delete tombstones immediately and UNDO inside the window '
      'restores it without enqueueing anything', (tester) async {
    await pumpChat(tester);
    final opsBefore = (await ops(tester)).length;
    await longPress(tester, 'my own message');

    await tester.tap(find.text('Delete for everyone'));
    await tester.pump(const Duration(milliseconds: 400)); // sheet closes
    await settle(tester);

    // The snackbar is only shown once the local tombstone has landed,
    // so its entrance animation starts after `settle` — give it a frame
    // budget of its own or the UNDO tap below lands on nothing.
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('This message was deleted'), findsOneWidget);
    expect(find.text('Message deleted'), findsOneWidget);
    expect(
      (await q(tester, () => store.fetchMessage('m-mine')))?.tombstoned,
      isTrue,
    );
    expect(
      (await ops(tester)).length,
      opsBefore,
      reason: 'Decision 11: nothing goes on the wire until the window '
          'elapses — that is what makes Undo free.',
    );

    await tester.tap(find.text('UNDO'));
    await settle(tester);

    final restored = await q(tester, () => store.fetchMessage('m-mine'));
    expect(restored?.tombstoned, isFalse);
    expect(restored?.body, 'my own message');
    expect(
      (await ops(tester)).length,
      opsBefore,
      reason: 'An undone delete must never enqueue a MESSAGE_DELETE.',
    );
  });

  testWidgets('Delete left alone for the whole window enqueues '
      'MESSAGE_DELETE when the timer fires', (tester) async {
    await pumpChat(tester);
    final opsBefore = (await ops(tester)).length;
    await longPress(tester, 'my own message');

    await tester.tap(find.text('Delete for everyone'));
    await tester.pump(const Duration(milliseconds: 400)); // sheet closes
    await settle(tester);
    expect((await ops(tester)).length, opsBefore);

    // Past the far side of the undo window.
    await tester.pump(undoWindow);
    await settle(tester);

    final after = await ops(tester);
    expect(after, hasLength(opsBefore + 1));
    expect(after.last['kind'], OpKind.messageDelete);
    expect(after.last['target_message_id'], 'm-mine');
    expect(_payload(after.last).type, pb.ChatPayloadType.TYPE_MESSAGE_DELETE);
    expect(
      (await q(tester, () => store.fetchMessage('m-mine')))?.tombstoned,
      isTrue,
    );
  });

  testWidgets('an inbound image attachment renders inline; any other mime '
      'gets a file row', (tester) async {
    await pumpChat(tester);
    // The bubble resolves the attachment url through the asset cache;
    // hand it the bytes instead of a network round-trip.
    AssetCache.instance = FakeAssetCache({'shot.jpg': onePixelPng});
    addTearDown(() => AssetCache.instance = null);
    await tester.runAsync(() async {
      await _insertWithAttachment(store, 'm-img', 'image/jpeg', 'shot.jpg', 3);
      await _insertWithAttachment(store, 'm-doc', 'application/pdf',
          'accounts.pdf', 4);
    });
    await settle(tester);

    expect(
      find.byType(Image),
      findsOneWidget,
      reason: 'An image/* attachment renders as a picture, not a file row.',
    );
    expect(find.text('accounts.pdf'), findsOneWidget);
    expect(find.text('shot.jpg'), findsNothing);
  });
}

Future<void> _insertWithAttachment(
  ChatStore store,
  String messageId,
  String mimeType,
  String filename,
  int seq,
) =>
    store.applyInboundMessage(
      localUserId: localUserId,
      channelId: channelId,
      opId: 'seed-$messageId',
      messageId: messageId,
      senderUserId: peerUserId,
      body: 'see attached',
      contentType: 'text/plain',
      // Exactly the shape InboundReceiver stores: a ChatPayload whose
      // only populated field is the repeated Attachment.
      attachments: pb.ChatPayload(
        attachments: [
          pb.Attachment(
            url: 'https://example.invalid/$filename',
            mimeType: mimeType,
            filename: filename,
            sizeBytes: fixnum.Int64(2048),
          ),
        ],
      ).writeToBuffer(),
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: 1000 + seq,
      serverTimestampMs: 1000 + seq,
      deliverySequence: seq,
      nowMs: 1000 + seq,
    );

pb.ChatPayload _payload(Map<String, Object?> op) =>
    pb.ChatPayload.fromBuffer(op['payload'] as List<int>);

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
      deliverySequence: seq,
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

/// Never connects, so Flow A never dispatches and every enqueued op
/// stays readable in `outbound_ops`.
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
