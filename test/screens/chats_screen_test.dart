/// Chat-list row states (frame a1), the long-press sheet (a2) and the
/// mute sheet (f).
///
/// The sheets are checked against a recording [ChatService] rather than
/// a real store: what a sheet is responsible for is calling the right
/// method with the right argument. That the argument then lands in the
/// right column is the store's job and is covered by
/// packages/vartalap_store/test/chat_metadata_test.dart — and a real
/// sqlite store cannot be driven from inside `testWidgets` anyway.
library vartalap.screens.chats_screen_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/chats/chats.dart';
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
  });

  group('long-press sheet', () {
    testWidgets('Pin to top pins, and reads Unpin when already pinned',
        (tester) async {
      final svc = _FakeChatService();
      await _openSheet(tester, svc, _entry(kind: 'group'));

      await tester.tap(find.text('Pin to top'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['setPinned(c-1, true)']);

      await _openSheet(tester, svc, _entry(kind: 'group', pinned: true));
      expect(find.text('Pin to top'), findsNothing);
      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();
      expect(svc.calls.last, 'setPinned(c-1, false)');
    });

    testWidgets('Delete chat deletes locally and never leaves the group',
        (tester) async {
      final svc = _FakeChatService();
      await _openSheet(tester, svc, _entry(kind: 'group'));

      await tester.tap(find.text('Delete chat'));
      await tester.pumpAndSettle();

      expect(svc.calls, ['deleteChat(c-1)']);
      expect(svc.calls.where((c) => c.startsWith('leaveGroup')), isEmpty);
    });

    testWidgets('a group sheet says you stay in the group', (tester) async {
      await _openSheet(
        tester,
        _FakeChatService(),
        _entry(kind: 'group'),
        displayName: 'Kothrud Flat 3B',
      );

      expect(find.textContaining('You stay in the group'), findsOneWidget);
      expect(find.textContaining('Leave group'), findsOneWidget);
    });

    testWidgets('a DM sheet says the contact stays in Contacts',
        (tester) async {
      await _openSheet(
        tester,
        _FakeChatService(),
        _entry(kind: 'one_to_one'),
        displayName: 'Ananya Iyer',
      );

      expect(
        find.textContaining('The contact stays in Contacts'),
        findsOneWidget,
      );
      expect(find.textContaining('You stay in the group'), findsNothing);
    });

    testWidgets('Clear history confirms first — backing out clears nothing',
        (tester) async {
      final svc = _FakeChatService();
      await _openSheet(tester, svc, _entry(kind: 'group'));

      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      expect(find.text('Clear history?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(svc.calls, isEmpty);

      await _openSheet(tester, svc, _entry(kind: 'group'));
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['clearMessages(c-1)']);
    });

    testWidgets('Mute notifications opens the mute sheet', (tester) async {
      final svc = _FakeChatService();
      await _openSheet(tester, svc, _entry(kind: 'group'));

      await tester.tap(find.text('Mute notifications'));
      await tester.pumpAndSettle();

      expect(find.text('8 hours'), findsOneWidget);
      expect(find.text('Always'), findsOneWidget);
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
  String kind = 'one_to_one',
  int unreadCount = 0,
  bool pinned = false,
  int? mutedUntilMs,
  bool hasFailedOp = false,
  String? lastMessagePreview = 'hello',
}) =>
    ChannelListEntry(
      channelId: channelId,
      kind: kind,
      name: null,
      avatarUrl: null,
      lastActivityMs: DateTime.now().millisecondsSinceEpoch,
      unreadCount: unreadCount,
      pinned: pinned,
      mutedUntilMs: mutedUntilMs,
      hasFailedOp: hasFailedOp,
      lastMessagePreview: lastMessagePreview,
      lastMessageAuthor: 'u-peer',
      lastMessageTombstoned: false,
    );

Future<void> _pumpTile(
  WidgetTester tester,
  ChannelListEntry entry, {
  String displayName = 'Ananya Iyer',
  String? senderPrefix,
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
          onTap: () {},
        ),
      ),
    ),
  );
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

Future<void> _openSheet(
  WidgetTester tester,
  ChatService service,
  ChannelListEntry entry, {
  String displayName = 'Kothrud Flat 3B',
}) =>
    _pumpOpener(
      tester,
      (ctx) => showChatActionsSheet(
        context: ctx,
        chatService: service,
        entry: entry,
        displayName: displayName,
      ),
    );

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
        channelId: _channelId,
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

/// Records the calls the sheets make. `noSuchMethod` covers the rest of
/// ChatService's surface, so this stays four methods instead of twenty
/// stubs — and anything the sheets start calling by accident throws
/// rather than silently passing.
class _FakeChatService implements ChatService {
  final List<String> calls = [];
  int? mutedUntilMs;

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
