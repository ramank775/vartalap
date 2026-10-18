/// ChatScreen widget tests — the message long-press sheet (frame d3)
/// and the 5-second Undo window (V3_ARCHITECTURE decision 11).
///
/// Runs against a real [ChatStore] and a real [ChatService]; only the
/// transports are stubs, and they stay disconnected on purpose so every
/// outbound op parks in `outbound_ops` where the assertions can read it.
/// What the screen is being asked to prove is *which ops it enqueues*,
/// not what the wire does with them.
library vartalap.screens.chat_screen_test;

import 'dart:async';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> pumpChat(
    WidgetTester tester, {
    Future<void> Function()? seed,
    String? initialMessageId,
  }) async {
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
      await seed?.call();
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
      navigatorObservers: [chatRouteObserver],
      home: ChatScreen(
        channelId: channelId,
        channelName: 'Peer',
        channelKind: 'dm',
        chatService: chat,
        authService: _FakeAuthService(),
        undoWindow: undoWindow,
        initialMessageId: initialMessageId,
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

  /// Long-press (selects the message: the app bar turns into its
  /// actions) and let it settle. Every beat in this file is pumped by
  /// hand: the chat screen holds indeterminate progress indicators,
  /// which never settle.
  Future<void> longPress(WidgetTester tester, String body) async {
    await tester.longPress(find.textContaining(body));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a bubble shows the server time, not the sender\'s clock',
      (tester) async {
    await pumpChat(tester);
    await q(
      tester,
      () => store.applyInboundMessage(
        localUserId: localUserId,
        channelId: channelId,
        opId: 'seed-late',
        messageId: 'm-late',
        senderUserId: peerUserId,
        body: 'sent late',
        contentType: 'text/plain',
        attachments: null,
        forwardSource: null,
        replyToMessageId: null,
        // The sender's phone said 5:47; the server accepted it at 5:53.
        clientTimestampMs: DateTime(2026, 10, 11, 17, 47).millisecondsSinceEpoch,
        serverTimestampMs: DateTime(2026, 10, 11, 17, 53).millisecondsSinceEpoch,
        nowMs: DateTime(2026, 10, 11, 17, 53).millisecondsSinceEpoch,
      ),
    );
    await settle(tester);

    expect(find.text('5:53 PM'), findsOneWidget);
    expect(find.text('5:47 PM'), findsNothing);
  });

  testWidgets('long-pressing my own message offers Edit and Delete; a '
      'peer message offers neither', (tester) async {
    await pumpChat(tester);

    await longPress(tester, 'my own message');
    expect(find.byTooltip('Reply'), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Delete for everyone'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel')); // let go of it
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Edit'), findsNothing);

    await longPress(tester, 'their message');
    expect(find.byTooltip('Reply'), findsOneWidget);
    expect(
      find.byTooltip('Edit'),
      findsNothing,
      reason: 'SYNC_PROTOCOL §6a.3: recipients drop an UPDATE that is not '
          "from the author, so editing someone else's message would be a "
          'button that provably does nothing.',
    );
    expect(find.byTooltip('Delete for everyone'), findsNothing);
  });

  testWidgets('tapping more messages while selecting adds them; the '
      'actions narrow to what fits all of them', (tester) async {
    await pumpChat(tester);
    await longPress(tester, 'my own message');
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.textContaining('their message'));
    await settle(tester);
    expect(find.text('2'), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Reply'), findsNothing,
        reason: 'Reply and Edit need exactly one message.');
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Delete for everyone'), findsNothing,
        reason: 'One of the two is not mine to delete.');

    await tester.tap(find.textContaining('their message'));
    await settle(tester);
    expect(find.text('1'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget);

    await tester.tap(find.textContaining('my own message'));
    await settle(tester);
    expect(find.byTooltip('Cancel'), findsNothing,
        reason: 'Letting go of the last one ends the selection.');
  });

  testWidgets('copying several messages gives WhatsApp-style lines, oldest '
      'first', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpChat(tester);

    // Picked newest first; copied oldest first.
    await longPress(tester, 'their message');
    await tester.tap(find.textContaining('my own message'));
    await settle(tester);
    await tester.tap(find.byTooltip('Copy'));
    await settle(tester);

    final lines = copied!.split('\n');
    expect(lines, hasLength(2));
    expect(lines[0], matches(RegExp(r'^\[.+\] You: my own message$')));
    expect(lines[1], matches(RegExp(r'^\[.+\] Peer: their message$')));
  });

  testWidgets('deleting several selected messages tombstones them all and '
      'one UNDO brings them all back', (tester) async {
    await pumpChat(tester);
    await q(tester,
        () => _insert(store, 'm-mine-2', localUserId, 'my second message', 3));
    await settle(tester);
    final opsBefore = (await ops(tester)).length;

    await longPress(tester, 'my own message');
    await tester.tap(find.textContaining('my second message'));
    await settle(tester);
    await tester.tap(find.byTooltip('Delete for everyone'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('2 messages deleted'), findsOneWidget);
    for (final id in ['m-mine', 'm-mine-2']) {
      expect((await q(tester, () => store.fetchMessage(id)))?.tombstoned,
          isTrue);
    }
    expect((await ops(tester)).length, opsBefore,
        reason: 'Decision 11: nothing is sent inside the undo window.');

    await tester.tap(find.text('UNDO'));
    await settle(tester);
    for (final id in ['m-mine', 'm-mine-2']) {
      expect((await q(tester, () => store.fetchMessage(id)))?.tombstoned,
          isFalse);
    }
    expect((await ops(tester)).length, opsBefore);
  });

  testWidgets('swiping a message right starts a reply to it',
      (tester) async {
    await pumpChat(tester);
    // The composer's reply preview is the only plain Text with the body.
    expect(find.text('their message'), findsNothing);

    await tester.drag(find.textContaining('their message'),
        const Offset(120, 0));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('their message'), findsOneWidget);
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

    await tester.tap(find.byTooltip('Edit'));
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

  testWidgets('confirming an edit with the text unchanged sends nothing',
      (tester) async {
    await pumpChat(tester);
    final before = (await ops(tester)).length;
    await longPress(tester, 'my own message');
    await tester.tap(find.byTooltip('Edit'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byIcon(Icons.check_rounded));
    await settle(tester);

    expect(find.text('Editing message'), findsNothing);
    expect((await ops(tester)).length, before);
    expect((await q(tester, () => store.fetchMessage('m-mine')))?.isEdited,
        isFalse);
  });

  testWidgets('Delete tombstones immediately and UNDO inside the window '
      'restores it without enqueueing anything', (tester) async {
    await pumpChat(tester);
    final opsBefore = (await ops(tester)).length;
    await longPress(tester, 'my own message');

    await tester.tap(find.byTooltip('Delete for everyone'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    // The snackbar is only shown once the local tombstone has landed,
    // so its entrance animation starts after `settle` — give it a frame
    // budget of its own or the UNDO tap below lands on nothing.
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('This message was deleted'), findsOneWidget);
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

    await tester.tap(find.byTooltip('Delete for everyone'));
    await tester.pump(const Duration(milliseconds: 400));
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

  testWidgets('an inbound voice note shows a play button and its length',
      (tester) async {
    await pumpChat(tester);
    await tester.runAsync(() => _insertWithAttachment(
        store, 'm-voice', 'audio/mp4', 'voice.m4a', 3,
        durationMs: 7000, contentType: kVoiceNoteType));
    await settle(tester);

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(
      find.text('00:07'),
      findsOneWidget,
      reason: 'Idle, the bubble shows the length the sender recorded.',
    );
    expect(find.text('voice.m4a'), findsNothing);
    expect(find.byIcon(Icons.headphones), findsNothing);
  });

  testWidgets('an audio file plays inline under its name',
      (tester) async {
    await pumpChat(tester);
    await tester.runAsync(() => _insertWithAttachment(
        store, 'm-song', 'audio/mpeg', 'song.mp3', 3,
        durationMs: 185000, contentType: 'audio/mpeg'));
    await settle(tester);

    expect(find.byIcon(Icons.headphones), findsOneWidget);
    expect(find.text('song.mp3'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('03:05'), findsOneWidget);
  });

  group('read only once the user can see it', () {
    Future<int> unread(WidgetTester tester) => q(tester,
        () async => (await store.fetchChannel(channelId))!.unreadCount);

    void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
      for (final s in states) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
    }

    testWidgets('a message that lands in the background waits for the '
        'app to come back', (tester) async {
      await pumpChat(tester);
      expect(await unread(tester), 0, reason: 'Opening the chat read it.');

      lifecycle(tester, const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      await tester.runAsync(
          () => _insert(store, 'm-away', peerUserId, 'while away', 3));
      await settle(tester);
      expect(await unread(tester), 1);

      lifecycle(tester, const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await settle(tester);
      expect(await unread(tester), 0);
    });

    testWidgets('a message that lands under another screen waits for it '
        'to close', (tester) async {
      await pumpChat(tester);
      final nav = Navigator.of(tester.element(find.byType(ChatScreen)));
      unawaited(nav.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Chat info')))));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.runAsync(
          () => _insert(store, 'm-under', peerUserId, 'under it', 3));
      await settle(tester);
      expect(await unread(tester), 1);

      nav.pop();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(await unread(tester), 0);
    });
  });

  testWidgets('the send button is a mic until there is something to send',
      (tester) async {
    await pumpChat(tester);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsNothing);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(
      find.byIcon(Icons.mic),
      findsOneWidget,
      reason: 'Whitespace sends nothing, so it is still a mic.',
    );
  });

  group('in-chat search', () {
    final searchField = find.descendant(
        of: find.byType(AppBar), matching: find.byType(EditableText));
    final up = find.widgetWithIcon(IconButton, Icons.keyboard_arrow_up);
    final down = find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down);
    bool enabled(WidgetTester tester, Finder button) =>
        tester.widget<IconButton>(button).onPressed != null;

    /// The marked runs inside [body]'s bubble.
    List<String> marked(WidgetTester tester, String body) {
      final out = <String>[];
      tester.widget<Text>(find.textContaining(body)).textSpan!.visitChildren(
        (s) {
          if (s is TextSpan && s.style?.backgroundColor != null) {
            out.add(s.text!);
          }
          return true;
        },
      );
      return out;
    }

    /// The current hit flashes its row.
    bool flashed(WidgetTester tester, String body) {
      final row = tester.widget<AnimatedContainer>(find
          .ancestor(
              of: find.textContaining(body),
              matching: find.byType(AnimatedContainer))
          .first);
      return (row.decoration as BoxDecoration?)?.color != Colors.transparent;
    }

    /// A jump pages through frames and, past the loaded page, the store.
    /// Bare frames first: on a phone the jump reaches the end of the page
    /// before the store has the next one.
    Future<void> jumped(WidgetTester tester, String to) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      // Real store reads in between: wait for the landing, not a fixed
      // count, or a loaded machine runs out of frames first.
      bool landed() =>
          find.textContaining(to).hitTestable().evaluate().isNotEmpty &&
          flashed(tester, to);
      for (var i = 0; i < 6 || (i < 40 && !landed()); i++) {
        await settle(tester);
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> openSearch(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Search in conversation'));
      await tester.pump();
    }

    testWidgets('the search icon turns the app bar into a search field; '
        'back brings the bar back and leaves the composer alone',
        (tester) async {
      await pumpChat(tester);
      await tester.tap(find.byType(TextField)); // the composer
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await openSearch(tester);
      expect(find.text('Search…'), findsOneWidget);
      expect(find.byTooltip('Search in conversation'), findsNothing);
      expect(up, findsOneWidget);
      expect(down, findsOneWidget);
      expect(tester.widget<EditableText>(searchField).focusNode.hasFocus,
          isTrue);
      expect(find.textContaining('their message'), findsOneWidget,
          reason: 'The chat stays underneath.');

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(find.byTooltip('Search in conversation'), findsOneWidget);
      expect(find.text('Search…'), findsNothing);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode
            .hasFocus,
        isFalse,
        reason: 'Focus must not fall back to the composer: that pops the '
            'keyboard on the way out of search.',
      );
      expect(tester.testTextInput.isVisible, isFalse);

      // System back leaves search too, not the chat.
      await openSearch(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byTooltip('Search in conversation'), findsOneWidget);
      expect(find.text('Search…'), findsNothing);
    });

    testWidgets('a search jumps to the newest hit and marks every hit; the '
        'arrows walk older and newer, past the loaded page, and stop at '
        'the ends', (tester) async {
      await pumpChat(tester);
      await tester.runAsync(() async {
        await _insert(store, 'm-a1', peerUserId, 'an apple a day', 3);
        // More than a page between the oldest hit and the rest.
        for (var i = 4; i < 64; i++) {
          await _insert(store, 'm-f$i', peerUserId, 'filler $i', i);
        }
        // A card's body is not its words.
        await _insert(store, 'm-card', peerUserId,
            'BEGIN:VCARD\nVERSION:3.0\nFN:Apple Seed\nEND:VCARD', 64,
            contentType: 'text/vcard');
        await _insert(store, 'm-a2', localUserId, 'APPLE pie', 65);
        await _insert(store, 'm-a3', peerUserId, 'apple tart', 66);
      });
      await settle(tester);

      await openSearch(tester);
      await tester.enterText(searchField, 'apple');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await jumped(tester, 'apple tart');

      expect(flashed(tester, 'apple tart'), isTrue);
      expect(marked(tester, 'apple tart'), ['apple']);
      expect(marked(tester, 'APPLE pie'), ['APPLE']);
      expect(marked(tester, 'filler 63'), isEmpty);
      expect(enabled(tester, down), isFalse);
      expect(enabled(tester, up), isTrue);

      await tester.tap(up);
      await jumped(tester, 'APPLE pie');
      expect(flashed(tester, 'APPLE pie'), isTrue);
      expect(enabled(tester, down), isTrue);

      await tester.tap(up);
      await jumped(tester, 'an apple a day');
      expect(find.textContaining('an apple a day').hitTestable(),
          findsOneWidget,
          reason: 'Jumping grows the window to a hit outside it.');
      expect(flashed(tester, 'an apple a day'), isTrue);
      expect(enabled(tester, up), isFalse,
          reason: 'Three hits: the card does not count.');

      await tester.tap(down);
      await jumped(tester, 'APPLE pie');
      expect(find.textContaining('APPLE pie').hitTestable(), findsOneWidget);
      await tester.tap(down);
      await jumped(tester, 'apple tart');
      expect(flashed(tester, 'apple tart'), isTrue);
      expect(enabled(tester, down), isFalse);

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(marked(tester, 'apple tart'), isEmpty);
      expect(flashed(tester, 'apple tart'), isFalse);
    });

    testWidgets('opened at a message from outside, the chat pages back to '
        'it and flashes it', (tester) async {
      await pumpChat(
        tester,
        initialMessageId: 'm-old',
        seed: () async {
          await _insert(store, 'm-old', peerUserId, 'way back', 3);
          for (var i = 4; i < 64; i++) {
            await _insert(store, 'm-f$i', peerUserId, 'filler $i', i);
          }
        },
      );
      await jumped(tester, 'way back');
      expect(find.textContaining('way back').hitTestable(), findsOneWidget);
      expect(flashed(tester, 'way back'), isTrue);
    });

    testWidgets('typing a query with no hit says so', (tester) async {
      await pumpChat(tester);
      await openSearch(tester);
      await tester.enterText(searchField, 'zebra');
      await tester.pump(const Duration(milliseconds: 400)); // the debounce
      await settle(tester);

      expect(find.text('No results found'), findsOneWidget);
      expect(enabled(tester, up), isFalse);
      expect(enabled(tester, down), isFalse);
    });
  });
}

Future<void> _insertWithAttachment(
  ChatStore store,
  String messageId,
  String mimeType,
  String filename,
  int seq, {
  int durationMs = 0,
  String contentType = 'text/plain',
}) =>
    store.applyInboundMessage(
      localUserId: localUserId,
      channelId: channelId,
      opId: 'seed-$messageId',
      messageId: messageId,
      senderUserId: peerUserId,
      body: 'see attached',
      contentType: contentType,
      // Exactly the shape InboundReceiver stores: a ChatPayload whose
      // only populated field is the repeated Attachment.
      attachments: pb.ChatPayload(
        attachments: [
          pb.Attachment(
            url: 'https://example.invalid/$filename',
            mimeType: mimeType,
            filename: filename,
            sizeBytes: fixnum.Int64(2048),
            durationMs: durationMs,
          ),
        ],
      ).writeToBuffer(),
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: 1000 + seq,
      serverTimestampMs: 1000 + seq,
      nowMs: 1000 + seq,
    );

pb.ChatPayload _payload(Map<String, Object?> op) =>
    pb.ChatPayload.fromBuffer(op['payload'] as List<int>);

Future<void> _insert(
  ChatStore store,
  String messageId,
  String authorUserId,
  String body,
  int seq, {
  String contentType = 'text/plain',
}) =>
    store.applyInboundMessage(
      localUserId: localUserId,
      channelId: channelId,
      opId: 'seed-$messageId',
      messageId: messageId,
      senderUserId: authorUserId,
      body: body,
      contentType: contentType,
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
