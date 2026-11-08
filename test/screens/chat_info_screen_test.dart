/// Group info (frames e, e2) — the screen where "Delete chat" and
/// "Leave group" sit together and must never be mistaken for each
/// other.
///
/// Same approach as chats_screen_test.dart: a recording service, so
/// the assertion is about which action a tap invokes.
library vartalap.screens.chat_info_screen_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/chat_info/chat_info.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/album_client.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

import '../fake_asset_cache.dart';

void main() {
  testWidgets('a group shows both actions, worded and coloured apart',
      (tester) async {
    await _pumpInfo(tester, _FakeChatService(members: _self), kind: 'group');
    await _scrollTo(tester, 'Leave group');

    expect(find.text('Group info'), findsOneWidget);
    expect(find.text('Delete chat'), findsOneWidget);
    expect(find.text('Leave group'), findsOneWidget);
    // Delete chat says what it does not do, right on the tile.
    expect(
      find.textContaining('You stay a member and the group stays under '
          'Groups'),
      findsOneWidget,
    );
    // Only Leave group is red.
    final scheme = lightThemeData.colorScheme;
    expect(_titleColor(tester, 'Leave group'), scheme.error);
    expect(_titleColor(tester, 'Delete chat'), isNull);
  });

  testWidgets('nothing on the screen is disabled or "Coming soon"',
      (tester) async {
    await _pumpInfo(tester, _FakeChatService(members: _self), kind: 'group');

    expect(find.textContaining('Coming soon'), findsNothing);
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
      expect(tile.enabled, isTrue);
    }
  });

  testWidgets('Media tile reports the empty state when nothing is shared',
      (tester) async {
    await _pumpInfo(tester, _FakeChatService(members: _self), kind: 'group');

    expect(find.text('Media, links and docs'), findsOneWidget);
    expect(find.text('Nothing shared yet'), findsOneWidget);
  });

  testWidgets('Media tile counts media, docs and links', (tester) async {
    await _pumpInfo(
      tester,
      _FakeChatService(
        members: _self,
        media: [_imageMessage('m-1'), _imageMessage('m-2')],
        files: [_imageMessage('m-3')],
        links: [_imageMessage('m-4')],
      ),
      kind: 'group',
    );

    expect(find.text('4 items'), findsOneWidget);
  });

  testWidgets('a muted group shows the mute bar and the mute on the tile',
      (tester) async {
    await _pumpInfo(
      tester,
      _FakeChatService(mutedUntilMs: kMuteAlways, members: _self),
      kind: 'group',
    );

    expect(find.text('Notifications'), findsOneWidget);
    // Once on the bar under the header, once as the tile subtitle.
    expect(find.text('Always'), findsNWidgets(2));
    expect(
      find.byIcon(Icons.notifications_off_outlined),
      findsNWidgets(2),
    );
  });

  testWidgets('an unmuted group reads "On" and shows no bar', (tester) async {
    await _pumpInfo(tester, _FakeChatService(members: _self), kind: 'group');

    expect(find.text('On'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('Delete chat confirms, then deletes locally — never leaves',
      (tester) async {
    final svc = _FakeChatService(members: _self);
    await _pumpInfo(tester, svc, kind: 'group');
    await _scrollTo(tester, 'Delete chat');

    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this chat?'), findsOneWidget);
    expect(find.textContaining('You stay in the group'), findsOneWidget);

    // Backing out erases nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(svc.calls, isEmpty);

    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Delete chat'),
    ));
    await tester.pumpAndSettle();
    expect(svc.calls, ['deleteChat(c-1)']);
  });

  testWidgets('Leave group confirms with the frame e2 copy', (tester) async {
    final svc = _FakeChatService(members: _self);
    await _pumpInfo(tester, svc, kind: 'group', name: 'Kothrud Flat 3B');
    await _scrollTo(tester, 'Leave group');

    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();

    expect(find.text('Leave Kothrud Flat 3B?'), findsOneWidget);
    expect(
      find.textContaining('Applies right away and syncs when you are '
          'online'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Other members stay in the group and can add '
          'you back'),
      findsOneWidget,
    );

    // Backing out leaves the membership alone.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(svc.calls, isEmpty);
  });

  testWidgets('confirming Leave group calls leaveGroup, not deleteChat',
      (tester) async {
    final svc = _FakeChatService(members: _self);
    await _pumpInfo(tester, svc, kind: 'group');
    await _scrollTo(tester, 'Leave group');

    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Leave group'));
    await tester.pumpAndSettle();

    expect(svc.calls, ['leaveGroup(c-1,u-self)']);
  });

  testWidgets('after leaving, group info is read only and keeps the chat',
      (tester) async {
    final svc = _FakeChatService(members: _roster(selfRole: 'member'));
    await _pumpInfo(tester, svc, kind: 'group');
    await _scrollTo(tester, 'Leave group');
    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stay on this phone until you delete it'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Leave group'));
    await tester.pumpAndSettle();

    // Still here, like WhatsApp: no members, no Leave, Delete chat only.
    expect(find.text('Group info'), findsOneWidget);
    expect(find.text("You're no longer a member of this group"),
        findsOneWidget);
    expect(find.text('Ravi'), findsNothing);
    expect(find.text('Leave group'), findsNothing);
    expect(find.byType(EditableAvator), findsNothing,
        reason: 'not ours to change any more');
    await _scrollTo(tester, 'Delete chat');
    expect(find.textContaining('erases its messages on this phone'),
        findsOneWidget);
    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You stay in the group'), findsNothing);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Delete chat'),
    ));
    await tester.pumpAndSettle();
    expect(svc.calls, ['leaveGroup(c-1,u-self)', 'deleteChat(c-1)']);
  });

  // ---- decisions 9 / 80 / 81: roles -------------------------------------

  testWidgets('member rows carry Owner and Admin badges, members none',
      (tester) async {
    await _pumpInfo(
      tester,
      _FakeChatService(members: _roster()),
      kind: 'group',
    );
    await _scrollTo(tester, 'Admin');

    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Member'), findsNothing);
  });

  testWidgets('the owner sees Delete group as well as Leave group',
      (tester) async {
    await _pumpInfo(
      tester,
      _FakeChatService(members: _roster(selfRole: 'owner')),
      kind: 'group',
    );
    await _scrollTo(tester, 'Delete group');

    final scheme = lightThemeData.colorScheme;
    expect(find.text('Leave group'), findsOneWidget);
    expect(_titleColor(tester, 'Delete group'), scheme.error);
  });

  testWidgets('an admin sees Leave group but never Delete group',
      (tester) async {
    await _pumpInfo(
      tester,
      _FakeChatService(members: _roster(selfRole: 'admin')),
      kind: 'group',
    );
    await _scrollTo(tester, 'Leave group');

    expect(find.text('Delete group'), findsNothing);
  });

  testWidgets('a plain member sees neither Delete group nor a role menu',
      (tester) async {
    await _pumpInfo(
      tester,
      _FakeChatService(members: _roster(selfRole: 'member')),
      kind: 'group',
    );

    expect(find.text('Delete group'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets("the owner's Leave confirm names the successor", (tester) async {
    await _pumpInfo(
      tester,
      _FakeChatService(members: _roster(selfRole: 'owner')),
      kind: 'group',
    );
    await _scrollTo(tester, 'Leave group');
    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();

    // Decision 9: the longest-standing admin, not the earliest joiner.
    expect(
      find.textContaining('Ravi will become the owner'),
      findsOneWidget,
    );
  });

  testWidgets('Delete group confirms that everyone loses it', (tester) async {
    final svc = _FakeChatService(members: _roster(selfRole: 'owner'));
    await _pumpInfo(tester, svc, kind: 'group');
    await _scrollTo(tester, 'Delete group');
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Everyone loses this group'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete group'));
    await tester.pumpAndSettle();
    expect(svc.calls, ['deleteGroup(c-1)']);
  });

  testWidgets('owner and admins can promote a member off its row',
      (tester) async {
    final svc = _FakeChatService(members: _roster(selfRole: 'admin'));
    await _pumpInfo(tester, svc, kind: 'group');

    // Ravi and Meena are both actionable (the owner is never a target
    // and you are not your own).
    await tester.scrollUntilVisible(_rowMenu('Meena'), 200);
    await tester.ensureVisible(_rowMenu('Meena'));
    await tester.pumpAndSettle();
    await tester.tap(_rowMenu('Meena'));
    await tester.pumpAndSettle();
    expect(find.text('Make admin'), findsOneWidget);

    await tester.tap(find.text('Make admin'));
    await tester.pumpAndSettle();
    expect(svc.calls, ['setMemberRole(c-1,u-meena,admin)']);
  });

  testWidgets('an existing admin is offered Dismiss as admin instead',
      (tester) async {
    final svc = _FakeChatService(
      members: _roster(selfRole: 'owner'),
    );
    await _pumpInfo(tester, svc, kind: 'group');

    // Long-press is the other way in, and lands on the same sheet.
    await tester.scrollUntilVisible(find.widgetWithText(ListTile, 'Ravi'), 200);
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Ravi'));
    await tester.pumpAndSettle();
    await tester.longPress(find.widgetWithText(ListTile, 'Ravi'));
    await tester.pumpAndSettle();
    expect(find.text('Dismiss as admin'), findsOneWidget);

    await tester.tap(find.text('Dismiss as admin'));
    await tester.pumpAndSettle();
    expect(svc.calls, ['setMemberRole(c-1,u-ravi,member)']);
  });

  test('the successor is the longest-standing admin, else the '
      'longest-standing member', () {
    final roster = _roster(selfRole: 'owner');
    expect(
      successorAfterOwnerLeaves(roster, 'u-self')?.userId,
      'u-ravi',
      reason: 'decision 9: an admin wins even though Meena joined first.',
    );
    expect(
      successorAfterOwnerLeaves(
        roster.where((m) => m.role != 'admin').toList(),
        'u-self',
      )?.userId,
      'u-meena',
      reason: 'decision 9: with no admin left it is the earliest joiner.',
    );
    expect(
      successorAfterOwnerLeaves(
        roster.where((m) => m.userId == 'u-self').toList(),
        'u-self',
      ),
      isNull,
      reason: 'the last member out takes the group with them.',
    );
  });

  testWidgets('a DM has no Leave group at all', (tester) async {
    await _pumpInfo(tester, _FakeChatService(), kind: 'one_to_one');
    await _scrollTo(tester, 'Delete chat');

    expect(find.text('Chat info'), findsOneWidget);
    expect(find.text('Leave group'), findsNothing);
    expect(find.text('Delete chat'), findsOneWidget);
    expect(
      find.textContaining('The contact stays in Contacts'),
      findsOneWidget,
    );
  });

  testWidgets('a group and a 1:1 each have Albums (decision 233)',
      (tester) async {
    await _pumpInfo(tester, _FakeChatService(members: _roster()),
        kind: 'group');
    expect(find.text('Albums'), findsOneWidget);

    await _pumpInfo(
        tester,
        _FakeChatService(members: [
          _member('u-self', 'member', 1),
          _member('u-peer', 'member', 1, 'Ravi'),
        ]),
        kind: 'one_to_one');
    expect(find.text('Albums'), findsOneWidget);
  });

  testWidgets('a DM is titled by the resolved name, not the stored one',
      (tester) async {
    final dm = ChannelListEntry(
      channelId: _channelId,
      kind: 'one_to_one',
      name: '@dev_test_2',
      avatarUrl: null,
      lastActivityMs: 1000,
      unreadCount: 0,
      lastMessagePreview: null,
      lastMessageAuthor: null,
      lastMessageTombstoned: false,
      peerContact: const ContactRow(
        userId: 'u-peer',
        username: 'dev_test_2',
        contactBookName: 'Dev_Two',
        lastRefreshedMs: 1,
      ),
    );
    await _pumpInfo(tester, _FakeChatService(channel: dm),
        kind: 'one_to_one', name: '@dev_test_2');

    expect(find.text('Dev_Two'), findsOneWidget);
  });

  testWidgets('an invitee shows as Invited; the owner can take it back',
      (tester) async {
    final service = _FakeChatService(members: _roster(), invites: const [
      InviteRow(
          channelId: _channelId,
          toUser: 'u-asha',
          fromUser: 'u-self',
          createdAt: 1),
    ]);
    await _pumpInfo(tester, service, kind: 'group');
    await _scrollTo(tester, 'Invited');
    expect(find.text('Invited'), findsOneWidget);
    expect(find.text('3 members'), findsOneWidget, reason: 'not a member yet');
    await tester.tap(find.byTooltip('Cancel invite'));
    await tester.pumpAndSettle();
    expect(service.calls, ['cancelInvite($_channelId,u-asha)']);
  });

  testWidgets('a DM ends with Block and Report, in red (decision 219)',
      (tester) async {
    final service = _FakeChatService(members: [
      _member('u-self', 'owner', 1),
      _member('u-peer', 'member', 1, 'Dev'),
    ]);
    await _pumpInfo(tester, service, kind: 'one_to_one');
    await _scrollTo(tester, 'Report Kothrud Flat 3B');
    final scheme = lightThemeData.colorScheme;
    expect(_titleColor(tester, 'Block Kothrud Flat 3B'), scheme.error);
    expect(_titleColor(tester, 'Report Kothrud Flat 3B'), scheme.error);
  });

  // ---- decision 245: WhatsApp's action row, photos open full screen ----

  testWidgets('chat info has no row of shortcut buttons under the name '
      '(owner: Search and Mute looked out of place)', (tester) async {
    await _pumpInfo(tester, _FakeChatService(members: _roster()),
        kind: 'group');
    expect(find.byType(InfoActions), findsNothing);
    expect(find.text('Notifications'), findsOneWidget,
        reason: 'mute and unmute stay under Notifications');
  });

  testWidgets('the group photo opens full screen, with a pencil to change it',
      (tester) async {
    AssetCache.instance = FakeAssetCache({'f-photo': onePixelPng});
    addTearDown(() => AssetCache.instance = null);
    final svc = _FakeChatService(
      members: _self,
      channel: ChannelListEntry(
        channelId: _channelId,
        kind: 'group',
        name: 'Kothrud Flat 3B',
        avatarUrl: 'f-photo',
        lastActivityMs: 1000,
        unreadCount: 0,
        lastMessagePreview: null,
        lastMessageAuthor: null,
        lastMessageTombstoned: false,
      ),
    );
    await _pumpInfo(tester, svc, kind: 'group');

    await tester.tap(find.byType(Avator).first);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('Change photo'), findsOneWidget);
  });

  testWidgets('a peer without a photo: the avatar opens nothing',
      (tester) async {
    await _pumpInfo(tester, _FakeChatService(), kind: 'one_to_one');
    await tester.tap(find.byType(Avator).first);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('chat list avatar: a photo opens the card, Message and Info',
      (tester) async {
    AssetCache.instance = FakeAssetCache({'f-photo': onePixelPng});
    addTearDown(() => AssetCache.instance = null);
    final taps = <String>[];
    Future<void> pump(String? photo) => tester.pumpWidget(MaterialApp(
          theme: lightThemeData,
          home: Scaffold(
            body: ChatAvatarPeek(
              entry: ChannelListEntry(
                channelId: _channelId,
                kind: 'one_to_one',
                name: 'Ravi',
                avatarUrl: photo,
                lastActivityMs: 1000,
                unreadCount: 0,
                lastMessagePreview: null,
                lastMessageAuthor: null,
                lastMessageTombstoned: false,
              ),
              title: 'Ravi',
              onMessage: () => taps.add('message'),
              onInfo: () => taps.add('info'),
              child: const Text('avatar'),
            ),
          ),
        ));

    await pump('f-photo');
    await tester.tap(find.text('avatar'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget, reason: 'the name strip');
    await tester.tap(find.byTooltip('Message'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.text('avatar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Info'));
    await tester.pumpAndSettle();
    expect(taps, ['message', 'info']);

    // The photo itself opens full screen.
    await tester.tap(find.text('avatar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AssetImageView));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('chat list avatar without a photo goes straight to Info',
      (tester) async {
    final taps = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ChatAvatarPeek(
        entry: ChannelListEntry(
          channelId: _channelId,
          kind: 'group',
          name: 'Flat',
          avatarUrl: null,
          lastActivityMs: 1000,
          unreadCount: 0,
          lastMessagePreview: null,
          lastMessageAuthor: null,
          lastMessageTombstoned: false,
        ),
        title: 'Flat',
        onMessage: () => taps.add('message'),
        onInfo: () => taps.add('info'),
        child: const Text('avatar'),
      ),
    ));
    await tester.tap(find.text('avatar'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(taps, ['info']);
  });
}

const String _channelId = 'c-1';

/// A group where we are a plain member and alone.
final List<ChannelMemberRow> _self = [_member('u-self', 'member', 100)];

Future<void> _pumpInfo(
  WidgetTester tester,
  ChatService service, {
  required String kind,
  String name = 'Kothrud Flat 3B',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      home: ChatInfoScreen(
        channelId: _channelId,
        channelName: name,
        channelKind: kind,
        chatService: service,
        authService: _FakeAuthService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The trailing role menu on one member's row.
Finder _rowMenu(String name) => find.descendant(
      of: find.widgetWithText(ListTile, name),
      matching: find.byIcon(Icons.more_vert),
    );

/// The destructive block sits below the fold in the test viewport.
/// scrollUntilVisible stops once the row is built, which can be under the
/// bottom edge; ensureVisible brings all of it on screen.
Future<void> _scrollTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 200);
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
}

Color? _titleColor(WidgetTester tester, String title) {
  final text = tester.widget<Text>(find.text(title));
  return text.style?.color;
}

/// Self (owner by default), one admin who joined late, one member who
/// joined first — so "longest-standing admin" and "earliest joiner"
/// disagree and the successor rule is actually exercised.
List<ChannelMemberRow> _roster({String selfRole = 'owner'}) => [
      _member('u-self', selfRole, 100),
      _member('u-ravi', 'admin', 300, 'Ravi'),
      _member('u-meena', 'member', 200, 'Meena'),
    ];

ChannelMemberRow _member(
  String userId,
  String role,
  int joinedAt, [
  String? name,
]) =>
    ChannelMemberRow(
      channelId: _channelId,
      userId: userId,
      role: role,
      joinedAt: joinedAt,
      contact: name == null
          ? null
          : ContactRow(
              userId: userId,
              contactBookName: name,
              lastRefreshedMs: 1,
            ),
    );

MessageRow _imageMessage(String id) => MessageRow(
      messageId: id,
      channelId: _channelId,
      authorUserId: 'u-peer',
      body: null,
      contentType: 'image/jpeg',
      replyToMessageId: null,
      clientTimestampMs: 1000,
      serverTimestampMs: 1010,
      state: MessageState.sent,
      stateUpdatedAt: 1000,
      isEdited: false,
      lastEditMs: null,
      tombstoned: false,
      tombstonePendingUntil: null,
    );

class _FakeChatService implements ChatService {
  final List<String> calls = [];
  final List<MessageRow> media;
  final List<MessageRow> files;
  final List<MessageRow> links;
  List<ChannelMemberRow> members;
  final List<InviteRow> invites;
  int? mutedUntilMs;
  final ChannelListEntry? channel;

  _FakeChatService({
    this.invites = const [],
    this.channel,
    this.media = const [],
    this.files = const [],
    this.links = const [],
    this.members = const [],
    this.mutedUntilMs,
  });

  @override
  Future<List<ChannelMemberRow>> fetchChannelMembers(String channelId) async =>
      members;

  @override
  Stream<List<OutboundOpRow>> watchFailures() =>
      const Stream<List<OutboundOpRow>>.empty();

  @override
  Stream<List<Label>> watchLabels() => Stream.value(const []);

  @override
  Stream<List<InviteRow>> watchInvites() => Stream.value(invites);

  @override
  Stream<Set<String>> watchBlocked() => Stream.value(const {});

  @override
  Future<List<ContactRow>> discoverContacts({
    List<String> normalizedPhones = const [],
    Map<String, String> contactBookNamesByPhone = const {},
  }) async =>
      const [];

  @override
  Future<void> deleteGroup(String channelId) async {
    calls.add('deleteGroup($channelId)');
  }

  @override
  Future<void> setMemberRole({
    required String channelId,
    required String userId,
    required String role,
  }) async {
    calls.add('setMemberRole($channelId,$userId,$role)');
  }

  @override
  Future<List<Album>> albumsOf(String channelId, {String? peer}) async =>
      const [];

  @override
  Future<List<MessageRow>> fetchMedia(String channelId) async => media;

  @override
  Future<List<MessageRow>> fetchFiles(String channelId) async => files;

  @override
  Future<List<MessageRow>> fetchLinks(String channelId) async => links;

  @override
  Future<ChannelListEntry?> fetchChannel(String channelId) async =>
      channel ??
      ChannelListEntry(
        channelId: channelId,
        kind: 'group',
        name: 'Kothrud Flat 3B',
        avatarUrl: null,
        lastActivityMs: 1000,
        unreadCount: 0,
        mutedUntilMs: mutedUntilMs,
        lastMessagePreview: null,
        lastMessageAuthor: null,
        lastMessageTombstoned: false,
      );

  @override
  Future<void> deleteChat(String channelId) async {
    calls.add('deleteChat($channelId)');
  }

  @override
  Future<void> cancelInvite(String channelId, String userId) async {
    calls.add('cancelInvite($channelId,$userId)');
  }

  @override
  Future<void> leaveGroup(
    String channelId, {
    required String selfUserId,
  }) async {
    calls.add('leaveGroup($channelId,$selfUserId)');
    members = [
      for (final m in members)
        if (m.userId != selfUserId) m,
    ];
  }

  @override
  Future<void> clearMessages(String channelId) async {
    calls.add('clearMessages($channelId)');
  }

  @override
  Future<void> setMuted(String channelId, int? untilMs) async {
    calls.add('setMuted($channelId,$untilMs)');
    mutedUntilMs = untilMs;
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
