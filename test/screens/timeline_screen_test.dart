/// Decision 223's screens: the Timeline tab next to Chats, a post's
/// card, the composer, the Labels screen, a contact's labels and the
/// chat list's label chips. Over a fake service; the fan-out itself is
/// test/services/timeline_service_test.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/home/home.dart';
import 'package:vartalap/screens/labels/labels.dart';
import 'package:vartalap/screens/timeline/post_composer.dart';
import 'package:vartalap/screens/timeline/timeline.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/timeline_client.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_store/vartalap_store.dart';

const _me = '00000000a';
const _asha = '00000000b';
const _ravi = '00000000c';

ContactRow _contact(String id, String name) =>
    ContactRow(userId: id, contactBookName: name, lastRefreshedMs: 0);

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(MaterialApp(theme: lightThemeData, home: home));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Timeline is a tab next to Chats, with pencil and camera buttons',
      (tester) async {
    final svc = _FakeChat()..hasNew = true;
    await _pump(
        tester,
        HomeScreen(
            chatService: svc, authService: _Auth(), config: ConfigStore()));

    expect(find.text('Chats'), findsWidgets);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue,
        reason: 'a post came in since the timeline was last opened');
    expect(svc.calls, isNot(contains('load')),
        reason: 'the timeline loads when it is opened, not before');
    await tester.tap(find.text('Timeline').last);
    await tester.pumpAndSettle();
    expect(find.text('No posts yet'), findsOneWidget);
    expect(svc.calls, contains('load'));
    expect(find.byType(Badge), findsNothing, reason: 'seen');

    await tester.tap(find.byTooltip('Write a post'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PostComposerScreen>(find.byType(PostComposerScreen))
            .photo,
        isFalse);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Photo post'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PostComposerScreen>(find.byType(PostComposerScreen))
            .photo,
        isTrue);
  });

  testWidgets('a post: ours lists who reacted; theirs offers the reactions',
      (tester) async {
    final svc = _FakeChat()
      ..posts = const [
        TimelinePost(
          postId: 'p2',
          author: _me,
          text: 'Diwali at home',
          createdAt: 2,
          audience: [_asha, _ravi],
          reactions: [(userId: _asha, emoji: '❤️')],
        ),
        TimelinePost(
            postId: 'p1', author: _asha, text: 'New puppy', createdAt: 1),
      ];
    await _pump(tester, TimelineScreen(chatService: svc, authService: _Auth()));

    expect(find.text('You'), findsOneWidget);
    expect(find.text('Shared with 2 people'), findsOneWidget);
    expect(find.text('❤️ Asha'), findsOneWidget,
        reason: 'only the poster sees who reacted, by name, no count');
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Only Asha sees your reaction'), findsOneWidget);

    await tester.tap(find.text('🙏'));
    await tester.pumpAndSettle();
    expect(svc.calls.last, 'react(p1, 🙏)');
    expect(find.byTooltip('Remove reaction'), findsOneWidget,
        reason: 'the server said yes: it shows as ours');

    await tester.tap(find.byTooltip('Delete post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(svc.calls.last, 'delete(p2)');
    expect(find.text('Diwali at home'), findsNothing);
  });

  testWidgets('offline: the timeline says so and tries again', (tester) async {
    final svc = _FakeChat()..offline = true;
    await _pump(tester, TimelineScreen(chatService: svc, authService: _Auth()));
    expect(find.text("Couldn't load the timeline"), findsOneWidget);
    svc.offline = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No posts yet'), findsOneWidget);
  });

  IconButton send(WidgetTester tester) => tester.widget<IconButton>(find
      .ancestor(of: find.byTooltip('Send'), matching: find.byType(IconButton)));

  testWidgets('a text post: words on a colour, to the last audience',
      (tester) async {
    final svc = _FakeChat()..lastAudience = {1};
    await _pump(tester, PostComposerScreen(chatService: svc));

    expect(find.widgetWithText(TextButton, 'Family'), findsOneWidget,
        reason: 'the audience pill starts at the last one used');
    expect(send(tester).onPressed, isNull, reason: 'nothing to post yet');

    Color background() =>
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor!;
    expect(background(), kPostColors.first.$2);
    expect(find.byTooltip('Purple'), findsNothing);
    await tester.tap(find.byTooltip('Background colour'));
    await tester.pump();
    expect(background(), kPostColors.first.$2,
        reason: 'the palette opens its colours, it does not change one');
    await tester.tap(find.byTooltip('Purple'));
    await tester.pump();
    expect(background(), kPostColors[1].$2);
    await tester.tap(find.byTooltip('Slate'));
    await tester.pump();
    expect(background(), kPostColors.last.$2);

    TextStyle style() =>
        tester.widget<EditableText>(find.byType(EditableText)).style;
    final font = style().fontFamily;
    await tester.tap(find.byTooltip('Font'));
    await tester.pump();
    expect(find.byTooltip('Purple'), findsNothing,
        reason: 'one row of choices at a time');
    expect(style().fontFamily, font);
    await tester.tap(find.text('Mono'));
    await tester.pump();
    expect(style().fontFamily, 'monospace');
    await tester.tap(find.byTooltip('Font'));
    await tester.pump();
    expect(find.text('Mono'), findsNothing, reason: 'T again closes the row');

    await tester.enterText(find.byType(TextField), 'Reached Pune');
    await tester.pump();
    final big = style().fontSize!;
    expect(send(tester).onPressed, isNotNull);
    await tester.enterText(find.byType(TextField), 'Reached Pune. ' * 10);
    await tester.pump();
    expect(style().fontSize, lessThan(big), reason: 'it shrinks as it grows');
    await tester.enterText(find.byType(TextField), 'Reached Pune');

    await tester.tap(find.byTooltip('Emoji'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🙏'));
    await tester.pumpAndSettle();
    expect(find.text('Reached Pune🙏'), findsOneWidget);

    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(svc.calls.last, 'post(Reached Pune🙏, [], {1})');
  });

  testWidgets('the audience pill picks all contacts or labels, with a count',
      (tester) async {
    final svc = _FakeChat();
    await _pump(tester, PostComposerScreen(chatService: svc));
    await tester.enterText(find.byType(TextField), 'hello');

    await tester.tap(find.widgetWithText(TextButton, 'All contacts'));
    await tester.pumpAndSettle();
    expect(find.text('2 people will see this'), findsOneWidget);
    CheckboxListTile tile(String text) => tester
        .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, text));
    expect(tile('All contacts').value, isTrue);

    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    expect(find.text('1 person will see this'), findsOneWidget);
    expect(tile('All contacts').value, isFalse);
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(find.text('2 people will see this'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Family, Friends'), findsOneWidget);

    // Back to everyone; dismissing the sheet keeps what was there.
    await tester.tap(find.widgetWithText(TextButton, 'Family, Friends'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All contacts').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'All contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'All contacts'), findsOneWidget);

    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(svc.calls.last, 'post(hello, [], null)');
  });

  testWidgets('a photo post: gallery or camera, a caption, then send',
      (tester) async {
    final svc = _FakeChat()..lastAudience = {1};
    final asked = <String>[];
    await _pump(
        tester,
        PostComposerScreen(
          chatService: svc,
          photo: true,
          pickPhotos: (camera, max) async {
            asked.add('${camera ? 'camera' : 'gallery'} $max');
            return camera
                ? ['/photos/c.jpg']
                : ['/photos/a.jpg', '/photos/b.jpg'];
          },
        ));
    expect(send(tester).onPressed, isNull, reason: 'no photo yet');
    expect(find.byType(TextField), findsNothing, reason: 'no caption yet');

    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    expect(send(tester).onPressed, isNotNull, reason: 'a photo is enough');
    await tester.tap(find.byTooltip('Take a photo'));
    await tester.pumpAndSettle();
    expect(asked, ['gallery 10', 'camera 8']);

    // A tap on a thumbnail shows that one; Remove takes it.
    await tester.tap(find
        .descendant(
            of: find.byType(ListView), matching: find.byType(GestureDetector))
        .at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove photo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Diwali');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(svc.calls.last, 'post(Diwali, [/photos/a.jpg, /photos/c.jpg], {1})');
  });

  testWidgets('nobody to share with: the composer says so and will not post',
      (tester) async {
    final svc = _FakeChat()..lastAudience = {3};
    await _pump(tester, PostComposerScreen(chatService: svc));
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();
    expect(find.textContaining('Nobody here yet'), findsOneWidget);
    expect(send(tester).onPressed, isNull);
  });

  testWidgets('labels: add, rename and delete', (tester) async {
    final svc = _FakeChat();
    await _pump(tester, LabelsScreen(chatService: svc));
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('0 people'), findsOneWidget, reason: 'Close');

    await tester.tap(find.text('New label'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cousins');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // a new label opens straight on choosing its people
    expect(find.byType(LabelMembersScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Cousins'), findsOneWidget);

    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Parivar');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Parivar'), findsOneWidget);

    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Parivar'), findsNothing);
    expect(svc.calls, ['create(Cousins)', 'rename(1, Parivar)', 'delete(1)']);
  });

  testWidgets('a label\'s people are ticked on and off', (tester) async {
    final svc = _FakeChat();
    await _pump(
        tester, LabelMembersScreen(chatService: svc, label: svc.labels.first));
    await tester.tap(find.text('Ravi'));
    await tester.pumpAndSettle();
    expect(svc.calls, ['members(1, {$_asha, $_ravi})']);
  });

  testWidgets('a contact\'s labels are picked from their info', (tester) async {
    final svc = _FakeChat();
    await _pump(tester,
        Scaffold(body: ContactLabelsTile(chatService: svc, userId: _asha)));
    expect(find.text('Family'), findsOneWidget);

    await tester.tap(find.text('Labels'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Close'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(svc.calls, ['contact($_asha, {1, 3})']);
  });

  testWidgets('a label chip on the chat list keeps the chats with its people',
      (tester) async {
    final svc = _FakeChat()
      ..channels = [
        _chat('d-asha', _contact(_asha, 'Asha')),
        _chat('d-ravi', _contact(_ravi, 'Ravi')),
      ];
    await _pump(
        tester,
        ChatsScreen(
            chatService: svc, authService: _Auth(), config: ConfigStore()));
    expect(find.text('Ravi'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Family'));
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Ravi'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('No chats with people in Close'), findsOneWidget);
  });
}

ChannelListEntry _chat(String id, ContactRow peer) => ChannelListEntry(
      channelId: id,
      kind: 'one_to_one',
      name: null,
      avatarUrl: null,
      lastActivityMs: 1,
      unreadCount: 0,
      lastMessagePreview: 'hi',
      lastMessageAuthor: peer.userId,
      lastMessageTombstoned: false,
      peerContact: peer,
    );

class _Auth implements AuthService {
  @override
  String? get currentUserId => _me;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeChat implements ChatService {
  final calls = <String>[];
  List<TimelinePost> posts = const [];
  List<ChannelListEntry> channels = const [];
  Set<int>? lastAudience;
  List<Label> labels = [
    const Label(labelId: 1, name: 'Family', userIds: {_asha}),
    const Label(labelId: 2, name: 'Friends', userIds: {_ravi}),
    const Label(labelId: 3, name: 'Close'),
  ];
  final _labelChanges = StreamController<List<Label>>.broadcast();

  void _setLabels(List<Label> next) {
    labels = next;
    _labelChanges.add(next);
  }

  @override
  Stream<List<Label>> watchLabels() async* {
    yield labels;
    yield* _labelChanges.stream;
  }

  @override
  Future<List<Label>> fetchLabels() async => labels;

  @override
  Future<int> createLabel(String name) async {
    calls.add('create($name)');
    _setLabels([...labels, Label(labelId: 9, name: name)]);
    return 9;
  }

  @override
  Future<void> renameLabel(int labelId, String name) async {
    calls.add('rename($labelId, $name)');
    _setLabels([
      for (final l in labels)
        l.labelId == labelId
            ? Label(labelId: labelId, name: name, userIds: l.userIds)
            : l
    ]);
  }

  @override
  Future<void> deleteLabel(int labelId) async {
    calls.add('delete($labelId)');
    _setLabels([
      for (final l in labels)
        if (l.labelId != labelId) l
    ]);
  }

  @override
  Future<void> setLabelMembers(int labelId, Set<String> userIds) async =>
      calls.add('members($labelId, $userIds)');

  @override
  Future<void> setContactLabels(String userId, Set<int> labelIds) async =>
      calls.add('contact($userId, $labelIds)');

  @override
  Future<List<ContactRow>> discoverContacts({
    List<String> normalizedPhones = const [],
    Map<String, String> contactBookNamesByPhone = const {},
  }) async =>
      [_contact(_asha, 'Asha'), _contact(_ravi, 'Ravi')];

  @override
  Stream<List<InviteRow>> watchInvites() => Stream.value(const []);

  @override
  Stream<List<ChannelListEntry>> watchChannels({int limit = 100}) =>
      Stream.value(channels);

  bool offline = false;
  bool hasNew = false;

  @override
  Future<List<TimelinePost>> loadTimeline() async {
    calls.add('load');
    if (offline) throw Exception('offline');
    return posts;
  }

  @override
  Future<bool> timelineHasNew() async => hasNew;

  @override
  Future<Set<int>?> lastTimelineAudience() async => lastAudience;

  @override
  Future<List<String>> timelineAudience(Set<int>? labelIds) async => [
        for (final l in labels)
          if (labelIds == null || labelIds.contains(l.labelId)) ...l.userIds
      ].toSet().toList();

  @override
  Future<TimelinePost> postToTimeline({
    String? body,
    List<String> photoPaths = const [],
    Set<int>? labelIds,
  }) async {
    calls.add('post($body, $photoPaths, $labelIds)');
    return const TimelinePost(postId: 'p', author: _me, createdAt: 3);
  }

  @override
  Future<void> reactToPost(TimelinePost post, String? emoji) async =>
      calls.add('react(${post.postId}, $emoji)');

  @override
  Future<void> deletePost(TimelinePost post) async =>
      calls.add('delete(${post.postId})');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
