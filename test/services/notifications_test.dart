/// MessageNotifications builds WhatsApp-style notifications from the
/// local store: which chats, which lines, in the chat list's wording,
/// alerting once per new line, and the "New activity" fallback for a
/// wake it cannot account for. Driven against the in-memory store and a
/// plugin that records what would have gone up.
library vartalap.services.notifications_test;

import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/chat_service.dart' show kMuteAlways;
import 'package:vartalap/services/notifications.dart';
import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap_store/vartalap_store.dart';

const _self = 'a00000001';
const _asha = 'b00000001';
const _ravi = 'c00000001';
const _dm = 'd0000000000000000000000000000001';
const _trip = 'g1';

void main() {
  late ChatStore store;
  late _FakePlugin plugin;
  late MessageNotifications notifications;
  var onScreen = false;
  var ts = 1000;

  Future<void> message(String channelId, String from, String body,
      {String? contentType, bool photo = false}) {
    ts++;
    return store.applyInboundMessage(
      localUserId: _self,
      channelId: channelId,
      opId: 'op$ts',
      messageId: 'm$ts',
      senderUserId: from,
      body: body,
      contentType: contentType,
      attachments: photo ? Uint8List.fromList([1]) : null,
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: ts,
      serverTimestampMs: ts,
      nowMs: ts,
    );
  }

  /// The lines of the chat notification for [channelId] posted [nth]
  /// from last, as `sender: text`.
  List<String> lines(String channelId, {int nth = 0}) {
    final shows = plugin.chats.where((s) => s.payload == channelId).toList();
    final style = shows[shows.length - 1 - nth].android!.styleInformation
        as MessagingStyleInformation;
    return [for (final m in style.messages!) '${m.person!.name}: ${m.text}'];
  }

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    onScreen = false;
    store = await ChatStore.open(path: inMemoryDatabasePath);
    plugin = _FakePlugin();
    notifications = MessageNotifications(
      store: () => store,
      selfUserId: () => _self,
      plugin: plugin,
      onScreen: () => onScreen,
    );
    await store.upsertContact(
        userId: _asha, username: 'asha', contactBookName: 'Asha', nowMs: 0);
    await store.upsertContact(userId: _ravi, username: 'ravi', nowMs: 0);
    await store.insertChannel(
        channelId: _dm, kind: 'one_to_one', ownerUserId: _asha, createdAt: 0);
    await store.insertChannelMember(
        channelId: _dm, userId: _asha, role: 'member', joinedAt: 0);
    await store.insertChannel(
        channelId: _trip,
        kind: 'group',
        ownerUserId: _asha,
        createdAt: 0,
        name: 'Trip');
  });

  tearDown(() => store.close());

  test('one notification per unread chat, titled and worded like the chat '
      'list, with only the lines from others', () async {
    await message(_dm, _asha, 'hi');
    await message(_dm, _self, 'my own echo');
    await message(_dm, _asha, '', contentType: 'image/jpeg', photo: true);
    ts++;
    await store.insertGroupEvent(
      channelId: _trip,
      messageId: 'e$ts',
      actorUserId: _asha,
      event: const GroupEvent(GroupEventKind.added, users: [_self]),
      atMs: ts,
    );
    await message(_trip, _ravi, 'yo');
    await message(_trip, _asha, 'geo:1,2', contentType: kLocationType);

    expect(await notifications.showUnread(), 2);

    final dm = plugin.chats.singleWhere((s) => s.payload == _dm);
    expect(dm.title, 'Asha');
    expect(dm.android!.tag, _dm);
    expect(lines(_dm), ['Asha: hi', 'Asha: 📷 Photo']);
    final trip = plugin.chats.singleWhere((s) => s.payload == _trip);
    expect(trip.title, 'Trip');
    expect(lines(_trip),
        ['Asha: Asha added you', '@ravi: yo', 'Asha: 📍 Location']);
    expect(plugin.shown.where((s) => s.android!.setAsGroupSummary).length, 1,
        reason: 'Android bundles more than one chat under a summary');
  });

  test('muted chats and deleted lines stay out', () async {
    await message(_dm, _asha, 'one');
    await message(_dm, _asha, 'two');
    await store.applyInboundMessageDelete(
        channelId: _dm,
        opId: 'del',
        messageId: 'm$ts',
        senderUserId: _asha,
        serverTimestampMs: ts + 1,
        nowMs: ts + 1);
    await message(_trip, _asha, 'muted');
    await store.setChannelMuted(_trip, kMuteAlways);

    expect(await notifications.showUnread(), 1);

    expect(plugin.chats.map((s) => s.payload), [_dm]);
    expect(lines(_dm), ['Asha: one']);
    expect(plugin.shown.where((s) => s.android!.setAsGroupSummary), isEmpty);
  });

  test('a chat alerts once per new line; reading it starts afresh',
      () async {
    await message(_dm, _asha, 'one');
    await notifications.showUnread();
    await notifications.showUnread();
    expect(plugin.chats, hasLength(1), reason: 'nothing new, no re-post');

    await message(_dm, _asha, 'two');
    await notifications.showUnread();
    expect(plugin.chats, hasLength(2));
    expect(lines(_dm), ['Asha: one', 'Asha: two']);

    await store.markChannelRead(_dm, ts);
    await message(_dm, _asha, 'three');
    await notifications.showUnread();
    expect(lines(_dm), ['Asha: three']);
  });

  test('on screen nothing goes up, and those lines never alert later',
      () async {
    onScreen = true;
    await message(_dm, _asha, 'seen in the app');
    await notifications.showUnread();
    onScreen = false;
    await notifications.showUnread();
    expect(plugin.shown, isEmpty);

    await message(_dm, _asha, 'after leaving');
    await notifications.showUnread();
    expect(lines(_dm), ['Asha: seen in the app', 'Asha: after leaving']);
  });

  group('a wake', () {
    bool newActivity() => plugin.shown.any((s) => s.id == 1);

    test('whose pull failed says "New activity", besides any chat', () async {
      await message(_dm, _asha, 'hi');
      await notifications.afterWake(null);
      expect(newActivity(), isTrue);
      expect(plugin.chats, hasLength(1));
    });

    test('that pulled nothing, with nothing unread, says "New activity"',
        () async {
      await notifications.afterWake(0);
      expect(newActivity(), isTrue);
    });

    test('that pulled only muted chats, receipts or echoes posts nothing',
        () async {
      await message(_trip, _asha, 'muted');
      await store.setChannelMuted(_trip, kMuteAlways);
      await message(_dm, _self, 'my own echo');
      await notifications.afterWake(3);
      expect(plugin.shown, isEmpty);
    });

    test('that pulled nothing new while a chat is up posts nothing',
        () async {
      await message(_dm, _asha, 'hi');
      await notifications.showUnread();
      await notifications.afterWake(0);
      expect(newActivity(), isFalse);
      expect(plugin.chats, hasLength(1));
    });

    test('while the app is on screen posts nothing', () async {
      onScreen = true;
      await notifications.afterWake(null);
      expect(plugin.shown, isEmpty);
    });
  });

  test('reading a chat cancels it, and the summary with the last one',
      () async {
    plugin.active = const [ActiveNotification(id: 3, tag: _trip)];
    await notifications.cancelChat(_dm);
    expect(plugin.cancelled, [(3, _dm)]);

    plugin.active = const [ActiveNotification(id: 3, tag: _dm)];
    await notifications.cancelChat(_dm);
    expect(plugin.cancelled, [(3, _dm), (3, _dm), (2, null)]);
  });
}

typedef _Shown = ({
  int id,
  String? title,
  String? payload,
  AndroidNotificationDetails? android,
});

/// Records what would have gone up; the shade is [active].
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final List<_Shown> shown = [];
  final List<(int, String?)> cancelled = [];
  List<ActiveNotification> active = const [];

  Iterable<_Shown> get chats => shown.where((s) => s.id == 3);

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async =>
      shown.add((
        id: id,
        title: title,
        payload: payload,
        android: notificationDetails?.android,
      ));

  @override
  Future<void> cancel({required int id, String? tag}) async =>
      cancelled.add((id, tag));

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => active;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
