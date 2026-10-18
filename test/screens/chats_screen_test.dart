/// Chat-list row states (frame a1), WhatsApp's long-press selection
/// mode and the mute sheet (f).
///
/// Actions are checked against a recording [ChatService] rather than
/// a real store: what the screen is responsible for is calling the
/// right method with the right argument. That the argument then lands
/// in the right column is the store's job and is covered by
/// packages/vartalap_store/test/chat_metadata_test.dart — and a real
/// sqlite store cannot be driven from inside `testWidgets` anyway.
library vartalap.screens.chats_screen_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/chat_action_sheets.dart';
import 'package:vartalap_store/vartalap_store.dart';

void main() {
  group('ChannelTile', () {
    testWidgets('unread count renders in a filled badge', (tester) async {
      await _pumpTile(tester, _entry(unreadCount: 3));

      expect(find.text('3'), findsOneWidget);
      expect(_badgeDecoration(tester).color, lightChatColors.unreadBadge);
      expect(_badgeDecoration(tester).border, isNull);
    });

    testWidgets('muted chat shows the bell glyph and an outline badge',
        (tester) async {
      await _pumpTile(
        tester,
        _entry(unreadCount: 12, mutedUntilMs: kMuteAlways),
      );

      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
      // A muted chat still counts, it just stops shouting.
      expect(find.text('12'), findsOneWidget);
      expect(_badgeDecoration(tester).color, Colors.transparent);
      expect(_badgeDecoration(tester).border, isNotNull);
    });

    testWidgets('an elapsed mute reads as unmuted', (tester) async {
      await _pumpTile(
        tester,
        _entry(
          unreadCount: 1,
          mutedUntilMs: DateTime.now().millisecondsSinceEpoch - 60 * 1000,
        ),
      );

      expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
      expect(_badgeDecoration(tester).color, lightChatColors.unreadBadge);
    });

    testWidgets('pinned chat shows the pin glyph', (tester) async {
      await _pumpTile(tester, _entry(pinned: true));
      expect(find.byIcon(Icons.push_pin), findsOneWidget);

      await _pumpTile(tester, _entry());
      expect(find.byIcon(Icons.push_pin), findsNothing);
    });

    testWidgets('a dead-lettered op replaces the preview with "Not sent"',
        (tester) async {
      await _pumpTile(
        tester,
        _entry(lastMessagePreview: 'see you at 6', hasFailedOp: true),
      );

      expect(find.textContaining('Not sent'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // A row can only say one thing, and "Not sent" outranks it.
      expect(find.textContaining('see you at 6'), findsNothing);
    });

    testWidgets('an attachment says what it is, with its caption if any',
        (tester) async {
      await _pumpTile(
        tester,
        _entry(lastMessagePreview: '', lastMessageContentType: 'image/jpeg',
            lastMessageHasAttachment: true),
      );
      expect(find.textContaining('📷 Photo', findRichText: true), findsOneWidget);

      // A .txt attachment is text/plain too; it is still a file.
      await _pumpTile(
        tester,
        _entry(lastMessagePreview: '', lastMessageContentType: 'text/plain',
            lastMessageHasAttachment: true),
      );
      expect(find.textContaining('📄 File', findRichText: true), findsOneWidget);

      await _pumpTile(
        tester,
        _entry(
          lastMessagePreview: 'Sunset',
          lastMessageContentType: 'image/jpeg',
          lastMessageHasAttachment: true,
        ),
      );
      expect(find.textContaining('📷 Sunset', findRichText: true), findsOneWidget);
    });

    testWidgets('group rows carry the glyph avatar and a sender prefix',
        (tester) async {
      await _pumpTile(
        tester,
        _entry(kind: 'group', lastMessagePreview: 'Ground booked'),
        senderPrefix: 'Meera: ',
      );

      expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
      expect(
        find.textContaining('Meera: ', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a DM with no photo falls back to initials', (tester) async {
      await _pumpTile(tester, _entry(), displayName: 'Farhan Qureshi');

      expect(find.text('FQ'), findsOneWidget);
      expect(find.byIcon(Icons.groups_rounded), findsNothing);
    });

    testWidgets('rows render in the order given, pinned first',
        (tester) async {
      // Ordering is the store's job (see its pinned-first test); what
      // the list must not do is re-sort behind its back.
      final entries = [
        _entry(channelId: 'c-pinned', pinned: true),
        _entry(channelId: 'c-recent'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          home: Scaffold(
            body: ListView(
              children: [
                for (final e in entries)
                  ChannelTile(
                    key: ValueKey(e.channelId),
                    entry: e,
                    chatColors: lightChatColors,
                    displayName: e.channelId,
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester
            .widgetList<ChannelTile>(find.byType(ChannelTile))
            .map((t) => t.entry.channelId),
        ['c-pinned', 'c-recent'],
      );
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });

    testWidgets('muted, pinned and unread sit right, on the second line',
        (tester) async {
      await _pumpTile(
        tester,
        _entry(unreadCount: 2, pinned: true, mutedUntilMs: kMuteAlways),
      );

      final name = tester.getRect(find.text('Ananya Iyer'));
      final bell = tester.getRect(find.byIcon(Icons.notifications_off_outlined));
      final pin = tester.getRect(find.byIcon(Icons.push_pin));
      final badge = tester.getRect(find.text('2'));
      // WhatsApp: below the name's line, past the preview, in the order
      // muted, pinned, count.
      for (final r in [bell, pin, badge]) {
        expect(r.center.dy, greaterThan(name.bottom - 4));
        expect(r.left, greaterThan(name.right));
      }
      expect(bell.right, lessThanOrEqualTo(pin.left));
      expect(pin.right, lessThanOrEqualTo(badge.left));
    });

    testWidgets('the time sits on the same line whatever the row holds',
        (tester) async {
      // Avatar initials, name, preview, then the time.
      await _pumpTile(tester, _entry());
      final plain = tester.getRect(find.byType(Text).at(3));
      await _pumpTile(
        tester,
        _entry(unreadCount: 5, pinned: true, mutedUntilMs: kMuteAlways),
      );
      final busy = tester.getRect(find.byType(Text).at(3));
      expect(busy.top, plain.top);
      expect(busy.right, plain.right);
    });

    testWidgets('a cleared chat renders an empty preview', (tester) async {
      await _pumpTile(tester, _entry(lastMessagePreview: null, author: null));

      expect(find.text('Ananya Iyer'), findsOneWidget);
      expect(find.textContaining('null', findRichText: true), findsNothing);
    });

    testWidgets('a selected row carries the check badge', (tester) async {
      await _pumpTile(tester, _entry());
      expect(find.byIcon(Icons.check), findsNothing);

      await _pumpTile(tester, _entry(), selected: true);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });

  group('selection mode', () {
    final chats = [
      _entry(channelId: 'c-a', name: 'Ananya'),
      _entry(channelId: 'c-f', name: 'Farhan'),
      _entry(channelId: 'c-k', name: 'Kothrud Flat 3B', kind: 'group'),
    ];

    testWidgets('long-press selects, taps toggle, the last one off exits',
        (tester) async {
      await _pumpChats(tester, _FakeChatService(channels: chats));
      expect(find.text('Vartalap'), findsOneWidget);

      await tester.longPress(find.text('Ananya'));
      await tester.pumpAndSettle();
      expect(find.text('Vartalap'), findsNothing);
      expect(find.text('1'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      for (final action in ['Pin chat', 'Delete chat', 'Mute notifications']) {
        expect(find.byTooltip(action), findsOneWidget, reason: action);
      }

      // While selecting, a tap adds or removes rather than opening.
      await tester.tap(find.text('Farhan'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.text('Farhan'));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.text('Ananya'));
      await tester.pumpAndSettle();
      expect(find.text('Vartalap'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('the back arrow and system back both clear the selection',
        (tester) async {
      await _pumpChats(tester, _FakeChatService(channels: chats));

      await tester.longPress(find.text('Ananya'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Vartalap'), findsOneWidget);

      await tester.longPress(find.text('Ananya'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // Still on the chat list, just not selecting.
      expect(find.text('Vartalap'), findsOneWidget);
      expect(find.text('Ananya'), findsOneWidget);
    });

    testWidgets('Select all picks every chat; Clear history is single-only',
        (tester) async {
      await _pumpChats(tester, _FakeChatService(channels: chats));

      await tester.longPress(find.text('Ananya'));
      await tester.pumpAndSettle();
      await _openOverflow(tester);
      expect(find.text('Clear history'), findsOneWidget);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNWidgets(3));
      await _openOverflow(tester);
      expect(find.text('Clear history'), findsNothing);
    });

    testWidgets('Clear history confirms first — backing out clears nothing',
        (tester) async {
      final svc = _FakeChatService(channels: chats);
      await _pumpChats(tester, svc);

      await tester.longPress(find.text('Kothrud Flat 3B'));
      await tester.pumpAndSettle();
      await _openOverflow(tester);
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      expect(find.text('Clear history?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(svc.calls, isEmpty);
      expect(find.text('1'), findsOneWidget);

      await _openOverflow(tester);
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['clearMessages(c-k)']);
      expect(find.text('Vartalap'), findsOneWidget);
    });

    testWidgets('Pin pins every selected chat; Unpin once all are pinned',
        (tester) async {
      final svc = _FakeChatService(channels: [
        _entry(channelId: 'c-a', name: 'Ananya'),
        _entry(channelId: 'c-f', name: 'Farhan', pinned: true),
        _entry(channelId: 'c-k', name: 'Kothrud', pinned: true),
      ]);
      await _pumpChats(tester, svc);

      // One unpinned in the mix: the action is Pin, for both.
      await tester.longPress(find.text('Ananya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Farhan'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unpin chat'), findsNothing);
      await tester.tap(find.byTooltip('Pin chat'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['setPinned(c-a, true)', 'setPinned(c-f, true)']);
      expect(find.text('Vartalap'), findsOneWidget);

      svc.calls.clear();
      await tester.longPress(find.text('Farhan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kothrud'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Unpin chat'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['setPinned(c-f, false)', 'setPinned(c-k, false)']);
    });

    testWidgets('a mute choice applies to every selected chat',
        (tester) async {
      final svc = _FakeChatService(channels: chats);
      await _pumpChats(tester, svc);

      await tester.longPress(find.text('Ananya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kothrud Flat 3B'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mute notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(svc.calls, ['setMuted(c-a)', 'setMuted(c-k)']);
      expect(svc.mutedUntilMs, kMuteAlways);
      expect(find.text('Vartalap'), findsOneWidget);
    });

    testWidgets('Unmute clears every selected chat once all are muted',
        (tester) async {
      final svc = _FakeChatService(channels: [
        _entry(channelId: 'c-a', name: 'Ananya', mutedUntilMs: kMuteAlways),
        _entry(channelId: 'c-f', name: 'Farhan', mutedUntilMs: kMuteAlways),
      ])
        ..mutedUntilMs = kMuteAlways;
      await _pumpChats(tester, svc);

      await tester.longPress(find.text('Ananya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Farhan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Unmute notifications'));
      await tester.pumpAndSettle();

      // Straight off, like WhatsApp: no sheet to pick "Off" from.
      expect(find.text('Save'), findsNothing);
      expect(svc.calls, ['setMuted(c-a)', 'setMuted(c-f)']);
      expect(svc.mutedUntilMs, isNull);
    });

    testWidgets('Delete confirms: Cancel keeps everything, confirm deletes all',
        (tester) async {
      final svc = _FakeChatService(channels: chats);
      await _pumpChats(tester, svc);

      await tester.longPress(find.text('Ananya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kothrud Flat 3B'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete chat'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 chats?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(svc.calls, isEmpty);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete chats'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['deleteChat(c-a)', 'deleteChat(c-k)']);
      // Local-only: it never leaves the group.
      expect(svc.calls.where((c) => c.startsWith('leaveGroup')), isEmpty);
      expect(find.text('Vartalap'), findsOneWidget);
    });

    testWidgets('deleting one DM says the contact stays', (tester) async {
      await _pumpChats(tester, _FakeChatService(channels: chats));

      await tester.longPress(find.text('Farhan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete chat'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this chat?'), findsOneWidget);
      expect(
        find.textContaining('The contact stays in Contacts'),
        findsOneWidget,
      );
      expect(find.text('Delete chat'), findsOneWidget);
    });
  });

  group('home: chips, Read all, search', () {
    final chats = [
      _entry(channelId: 'c-a', name: 'Ananya', unreadCount: 2),
      _entry(channelId: 'c-f', name: 'Farhan'),
      _entry(channelId: 'c-k', name: 'Kothrud Flat 3B', kind: 'group'),
    ];

    testWidgets('Unread and Groups keep only their rows; an empty chip '
        'offers the way back', (tester) async {
      await _pumpChats(tester, _FakeChatService(channels: chats));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Unread'));
      await tester.pumpAndSettle();
      expect(find.text('Ananya'), findsOneWidget);
      expect(find.text('Farhan'), findsNothing);
      expect(find.text('Kothrud Flat 3B'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Groups'));
      await tester.pumpAndSettle();
      expect(find.text('Kothrud Flat 3B'), findsOneWidget);
      expect(find.text('Ananya'), findsNothing);

      // A fresh screen: the chip is the screen's own state.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpChats(tester, _FakeChatService(channels: [chats[1]]));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Unread'));
      await tester.pumpAndSettle();
      expect(find.text('No unread chats'), findsOneWidget);
      await tester.tap(find.text('View all chats'));
      await tester.pumpAndSettle();
      expect(find.text('Farhan'), findsOneWidget);
    });

    testWidgets('Read all marks only the unread chats read', (tester) async {
      final svc = _FakeChatService(channels: chats);
      await _pumpChats(tester, svc);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(
        [
          for (final t in tester.widgetList<PopupMenuItem<String>>(
              find.byType(PopupMenuItem<String>)))
            (t.child! as Text).data,
        ],
        ['New group', 'Starred messages', 'Read all', 'Settings'],
      );
      await tester.tap(find.text('Read all'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['markRead(c-a)']);
    });

    testWidgets('search finds chats by name, then messages with the words '
        'picked out; back leaves search', (tester) async {
      final svc = _FakeChatService(channels: chats, hits: [
        _message('m-1', 'c-k', 'u-peer', 'see you at the flat tonight'),
        _message('m-2', 'c-a', 'u-self', 'Flat white?'),
        // A chat that is not on the list, and a card: neither shows.
        _message('m-3', 'c-gone', 'u-peer', 'flat'),
        _message('m-4', 'c-f', 'u-peer', 'BEGIN:VCARD\nFN:Flat\nEND:VCARD',
            contentType: 'text/vcard'),
      ]);
      await _pumpChats(tester, svc);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.enterText(find.byType(TextField), 'flat');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      // The group by name, then its message, then Ananya's.
      expect(find.text('Kothrud Flat 3B'), findsNWidgets(2));
      expect(find.text('Ananya'), findsOneWidget);
      expect(find.text('Farhan'), findsNothing);
      final mine = tester.widget<Text>(find.textContaining('Flat white?'));
      expect(mine.textSpan!.toPlainText(), 'You: Flat white?');
      final marked = <String>[];
      mine.textSpan!.visitChildren((s) {
        if (s is TextSpan && s.style?.fontWeight == FontWeight.w600) {
          marked.add(s.text!);
        }
        return true;
      });
      expect(marked, ['Flat']);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text("No results found for 'zzz'"), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Farhan'), findsOneWidget);
    });
  });

  group('mute sheet', () {
    testWidgets('8 hours writes a muted_until_ms eight hours out',
        (tester) async {
      final svc = _FakeChatService();
      final before = DateTime.now().millisecondsSinceEpoch;
      await _openMuteSheet(tester, svc);

      await tester.tap(find.text('8 hours'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      const eightHours = 8 * 60 * 60 * 1000;
      expect(svc.calls, ['setMuted(c-1)']);
      expect(svc.mutedUntilMs, greaterThanOrEqualTo(before + eightHours));
      expect(svc.mutedUntilMs, lessThan(before + eightHours + 60 * 1000));
    });

    testWidgets('1 week writes a muted_until_ms a week out', (tester) async {
      final svc = _FakeChatService();
      final before = DateTime.now().millisecondsSinceEpoch;
      await _openMuteSheet(tester, svc);

      await tester.tap(find.text('1 week'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      const oneWeek = 7 * 24 * 60 * 60 * 1000;
      expect(svc.mutedUntilMs, greaterThanOrEqualTo(before + oneWeek));
      expect(svc.mutedUntilMs, lessThan(before + oneWeek + 60 * 1000));
    });

    testWidgets('Always writes the far-future sentinel', (tester) async {
      final svc = _FakeChatService();
      await _openMuteSheet(tester, svc);

      await tester.tap(find.text('Always'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(svc.mutedUntilMs, kMuteAlways);
    });

    testWidgets('Off clears muted_until_ms', (tester) async {
      final svc = _FakeChatService();
      await _openMuteSheet(tester, svc, mutedUntilMs: kMuteAlways);

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(svc.calls, ['setMuted(c-1)']);
      expect(svc.mutedUntilMs, isNull);
    });

    testWidgets('Cancel writes nothing at all', (tester) async {
      final svc = _FakeChatService();
      await _openMuteSheet(tester, svc);

      await tester.tap(find.text('Always'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(svc.calls, isEmpty);
    });

    testWidgets('reopening on a long mute preselects 1 week', (tester) async {
      final svc = _FakeChatService();
      final inThreeDays = DateTime.now()
          .add(const Duration(days: 3))
          .millisecondsSinceEpoch;
      await _openMuteSheet(tester, svc, mutedUntilMs: inThreeDays);

      // Only the expiry is stored, so the option is recovered from how
      // much mute is left — three days left is not an 8-hour mute.
      expect(
        _selectedMuteOption(tester),
        '1 week',
      );
    });
  });

  group('muteLabel', () {
    test('reads "Always" for the sentinel', () {
      expect(muteLabel(kMuteAlways), 'Always');
    });

    test('is null when unmuted or already elapsed', () {
      final now = DateTime(2026, 9, 21, 10);
      expect(muteLabel(null, now: now), isNull);
      expect(
        muteLabel(
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          now: now,
        ),
        isNull,
      );
    });

    test('says "today" only when the expiry is today', () {
      final now = DateTime(2026, 9, 21, 10);
      expect(
        muteLabel(
          now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
          now: now,
        ),
        contains('today'),
      );
      expect(
        muteLabel(
          now.add(const Duration(days: 7)).millisecondsSinceEpoch,
          now: now,
        ),
        isNot(contains('today')),
      );
    });
  });
}

const String _channelId = 'c-1';


ChannelListEntry _entry({
  String channelId = _channelId,
  String? name,
  String kind = 'one_to_one',
  int unreadCount = 0,
  bool pinned = false,
  int? mutedUntilMs,
  bool hasFailedOp = false,
  String? lastMessagePreview = 'hello',
  String? lastMessageContentType,
  bool lastMessageHasAttachment = false,
  String? author = 'u-peer',
}) =>
    ChannelListEntry(
      channelId: channelId,
      kind: kind,
      name: name,
      avatarUrl: null,
      lastActivityMs: DateTime.now().millisecondsSinceEpoch,
      unreadCount: unreadCount,
      pinned: pinned,
      mutedUntilMs: mutedUntilMs,
      hasFailedOp: hasFailedOp,
      lastMessagePreview: lastMessagePreview,
      lastMessageContentType: lastMessageContentType,
      lastMessageHasAttachment: lastMessageHasAttachment,
      lastMessageAuthor: author,
      lastMessageTombstoned: false,
    );

MessageRow _message(
  String id,
  String channelId,
  String author,
  String body, {
  String contentType = 'text/plain',
}) =>
    MessageRow(
      messageId: id,
      channelId: channelId,
      authorUserId: author,
      body: body,
      contentType: contentType,
      replyToMessageId: null,
      clientTimestampMs: 1000,
      serverTimestampMs: 1000,
      state: MessageState.sent,
      stateUpdatedAt: 1000,
      isEdited: false,
      lastEditMs: null,
      tombstoned: false,
      tombstonePendingUntil: null,
    );

Future<void> _pumpTile(
  WidgetTester tester,
  ChannelListEntry entry, {
  String displayName = 'Ananya Iyer',
  String? senderPrefix,
  bool selected = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      home: Scaffold(
        body: ChannelTile(
          entry: entry,
          chatColors: lightChatColors,
          displayName: displayName,
          senderPrefix: senderPrefix,
          selected: selected,
          onTap: () {},
        ),
      ),
    ),
  );
}

/// The whole screen, over the fake's rows.
Future<void> _pumpChats(WidgetTester tester, _FakeChatService svc) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      home: ChatsScreen(
        chatService: svc,
        authService: _FakeAuthService(),
        config: ConfigStore(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The selection bar's overflow; the only menu on screen while selecting.
Future<void> _openOverflow(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
}

/// The unread badge is the innermost decorated box around the count.
BoxDecoration _badgeDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .ancestor(
          of: find.byType(Text).last,
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

/// Label of the mute option whose radio glyph is filled.
String _selectedMuteOption(WidgetTester tester) {
  final tile = tester.widget<ListTile>(
    find
        .ancestor(
          of: find.byIcon(Icons.radio_button_checked),
          matching: find.byType(ListTile),
        )
        .first,
  );
  return (tile.title! as Text).data!;
}

Future<void> _openMuteSheet(
  WidgetTester tester,
  ChatService service, {
  int? mutedUntilMs,
}) =>
    _pumpOpener(
      tester,
      (ctx) => showMuteSheet(
        context: ctx,
        chatService: service,
        channelIds: [_channelId],
        mutedUntilMs: mutedUntilMs,
      ),
    );

Future<void> _pumpOpener(
  WidgetTester tester,
  Future<void> Function(BuildContext) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => open(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Records the calls the screen makes. `noSuchMethod` covers the rest
/// of ChatService's surface, so this stays a handful of methods instead
/// of twenty stubs — and anything the screen starts calling by accident
/// throws rather than silently passing.
class _FakeChatService implements ChatService {
  final List<String> calls = [];
  final List<ChannelListEntry> channels;
  final List<MessageRow> hits;
  int? mutedUntilMs;

  _FakeChatService({this.channels = const [], this.hits = const []});

  @override
  Future<List<MessageRow>> searchMessages(String query) async => hits;

  @override
  Future<void> markRead(String channelId) async {
    calls.add('markRead($channelId)');
  }

  @override
  Stream<List<ChannelListEntry>> watchChannels({int limit = 100}) =>
      Stream.value(channels);

  @override
  Future<List<ContactRow>> discoverContacts({
    List<String> normalizedPhones = const [],
    Map<String, String> contactBookNamesByPhone = const {},
  }) async =>
      const [];

  @override
  Future<void> setPinned(String channelId, bool pinned) async {
    calls.add('setPinned($channelId, $pinned)');
  }

  @override
  Future<void> setMuted(String channelId, int? untilMs) async {
    calls.add('setMuted($channelId)');
    mutedUntilMs = untilMs;
  }

  @override
  Future<void> deleteChat(String channelId) async {
    calls.add('deleteChat($channelId)');
  }

  @override
  Future<void> clearMessages(String channelId) async {
    calls.add('clearMessages($channelId)');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeAuthService implements AuthService {
  @override
  String? get currentUserId => 'u-self';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
