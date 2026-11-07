/// MessageNotifications builds WhatsApp-style notifications from the
/// local store: which chats, which lines, in the chat list's wording,
/// alerting once per new line, and the "New activity" fallback for a
/// wake it cannot account for. Driven against the in-memory store and a
/// plugin that records what would have gone up.
library vartalap.services.notifications_test;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/notifications.dart';
import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

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
    return [
      for (final m in style.messages!) '${m.person?.name ?? 'You'}: ${m.text}'
    ];
  }

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AssetCache.instance = null;
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

  test('decision 222: a chat showing a timed line goes from the shade when '
      'its time is up, app running or not', () async {
    await message(_dm, _asha, 'plain');
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.applyInboundMessage(
      localUserId: _self,
      channelId: _trip,
      opId: 'op-timed',
      messageId: 'm-timed',
      senderUserId: _asha,
      body: 'OTP 1234',
      contentType: null,
      attachments: null,
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: now,
      serverTimestampMs: now,
      nowMs: now,
      timerSec: 60,
    );

    await notifications.showUnread();

    expect(plugin.chats.singleWhere((s) => s.payload == _dm).android!
        .timeoutAfter, isNull);
    expect(
        plugin.chats.singleWhere((s) => s.payload == _trip).android!
            .timeoutAfter,
        inInclusiveRange(50000, 60000));
  });

  test('decision 222: a secure message reads "Secure message", never its '
      'secret', () async {
    await message(_dm, _asha, '', contentType: kSecureType);
    await notifications.showUnread();
    expect(lines(_dm), ['Asha: 🔒 Secure message']);
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

  group('photos', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('notif-photos');
      AssetCache.dirProvider = () async => dir;
      // AssetCache keeps an opened photo under its fileId, key left off
      File('${dir.path}/asha-photo').writeAsBytesSync([1]);
      File('${dir.path}/trip-photo').writeAsBytesSync([2]);
      Future<void> photo(String table, String key, String id, String url) =>
          store.db.update(table, {'avatar_url': url},
              where: '$key = ?', whereArgs: [id]);
      await photo('contacts', 'user_id', _asha, 'asha-photo#AAAA');
      // ravi's is not on this phone yet
      await photo('contacts', 'user_id', _ravi, 'ravi');
      await photo('channels', 'channel_id', _trip, 'trip-photo');
    });

    tearDown(() => dir.delete(recursive: true));

    String? icon(Message m) => switch (m.person?.icon) {
          final BitmapFilePathAndroidIcon i => i.data,
          _ => null,
        };

    test('a DM carries its person\'s photo, a group its own and each '
        'sender\'s; one not on the phone is left to Android\'s initials',
        () async {
      await message(_dm, _asha, 'one');
      await message(_dm, _asha, 'two');
      await message(_trip, _asha, 'a');
      await message(_trip, _ravi, 'b');
      await message(_trip, _asha, 'c');

      await notifications.showUnread();

      final dm = plugin.chats.singleWhere((s) => s.payload == _dm).android!;
      expect((dm.largeIcon! as FilePathAndroidBitmap).data,
          '${dir.path}/asha-photo');
      final dmLines =
          (dm.styleInformation! as MessagingStyleInformation).messages!;
      expect(dmLines.map(icon), ['${dir.path}/asha-photo', null],
          reason: 'Android takes a run of lines\' avatar from its first');

      final trip =
          plugin.chats.singleWhere((s) => s.payload == _trip).android!;
      expect((trip.largeIcon! as FilePathAndroidBitmap).data,
          '${dir.path}/trip-photo');
      final tripLines =
          (trip.styleInformation! as MessagingStyleInformation).messages!;
      expect(tripLines.map(icon),
          ['${dir.path}/asha-photo', null, '${dir.path}/asha-photo']);
    });

    test('a photo Android refuses still lets the chat go up', () async {
      plugin.refusePhotos = true;
      await message(_dm, _asha, 'hi');
      await notifications.showUnread();
      final dm = plugin.chats.singleWhere((s) => s.payload == _dm).android!;
      expect(dm.largeIcon, isNull);
      expect(lines(_dm), ['Asha: hi']);
    });
  });

  group('buttons', () {
    late SyncScheduler scheduler;
    late ChatService chats;

    setUp(() async {
      scheduler = SyncScheduler(
        store: store,
        wsTransport: _Offline(),
        restTransport: _Offline(),
        backoff: const FixedBackoff(Duration(milliseconds: 10)),
        clock: Clock.system,
      );
      final auth = AuthClient(baseUrl: Uri.parse('http://example.invalid'));
      chats = ChatService(
        store: store,
        scheduler: scheduler,
        authClient: auth,
        wsTransport: WsTransport(
            endpoint: Uri.parse('ws://example.invalid/wss'), auth: auth),
        uuidGen: Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(_self)),
        clock: Clock.system,
      )..onRead = notifications.cancelChat;
      for (final u in [_self, _asha, _ravi]) {
        await store.insertChannelMember(
            channelId: _trip, userId: u, role: 'member', joinedAt: 0);
      }
    });

    tearDown(() => scheduler.stop());

    Future<List<MessageRow>> mine(String channelId) async => [
          for (final m in await store.fetchChannelMessages(channelId))
            if (m.authorUserId == _self) m,
        ];

    Future<int> unread(String channelId) async =>
        (await store.fetchChannel(channelId))!.unreadCount;

    test('every chat notification has Mark as read and Reply', () async {
      await message(_dm, _asha, 'hi');
      await notifications.showUnread();
      final actions =
          plugin.chats.single.android!.actions!.map((a) => a.id).toList();
      expect(actions, [kReadAction, kReplyAction]);
      expect(plugin.chats.single.android!.actions!.last.inputs, hasLength(1));
    });

    test('Reply queues the message like one typed in the chat, shows it '
        'a moment, and reads the chat', () async {
      await message(_dm, _asha, 'lunch?');
      await notifications.showUnread();

      await notifications.act(chats,
          action: kReplyAction, channelId: _dm, input: ' yes, at 1 ');

      final sent = (await mine(_dm)).single;
      expect(sent.body, 'yes, at 1');
      expect(sent.state, MessageState.pending);
      expect(await store.hasUnsentOps(), isTrue,
          reason: 'in the outbound queue the background send drains');
      expect(await unread(_dm), 0);
      expect(lines(_dm), ['Asha: lunch?', 'You: yes, at 1']);
      final shown = plugin.chats.last.android!;
      expect(shown.silent, isTrue);
      expect(shown.timeoutAfter, 3000);
      expect(shown.actions, isNull);
      expect(plugin.cancelled, isNot(contains((3, _dm))),
          reason: 'it goes by itself once it has shown the reply');
    });

    test('Reply in a group goes to the group', () async {
      await message(_trip, _ravi, 'who is in?');
      await notifications.act(chats,
          action: kReplyAction, channelId: _trip, input: 'me');
      expect((await mine(_trip)).single.body, 'me');
      expect(lines(_trip), ['@ravi: who is in?', 'You: me']);
    });

    for (final (what, arrange, says) in [
      (
        'someone we blocked',
        (ChatStore s) => s.setConnection(_asha, blocked: true),
        'Not sent. You blocked Asha.',
      ),
      (
        'someone not connected',
        (ChatStore s) =>
            s.replaceConnections(connected: [], blocked: [], invites: []),
        'Not sent. Vartalap is invite only: open the chat to send Asha an '
            'invite.',
      ),
    ]) {
      test('Reply to $what is not queued; the notification says why',
          () async {
        await message(_dm, _asha, 'hi');
        await arrange(store);
        await notifications.act(chats,
            action: kReplyAction, channelId: _dm, input: 'hello');
        expect(await mine(_dm), isEmpty);
        expect(await store.hasUnsentOps(), isFalse);
        expect(await unread(_dm), 1);
        expect(plugin.shown.last.body, says);
        expect(plugin.shown.last.android!.tag, _dm);
      });
    }

    test('Reply to a group we left is not queued', () async {
      await message(_trip, _asha, 'bye');
      await store.db.delete('channel_members',
          where: 'channel_id = ? AND user_id = ?', whereArgs: [_trip, _self]);
      await notifications.act(chats,
          action: kReplyAction, channelId: _trip, input: 'wait');
      expect(await mine(_trip), isEmpty);
      expect(plugin.shown.last.body,
          "Not sent. You're no longer a member of this group.");
    });

    test('Mark as read reads the chat and clears it', () async {
      await message(_dm, _asha, 'hi');
      await notifications.showUnread();
      await notifications.act(chats, action: kReadAction, channelId: _dm);
      expect(await unread(_dm), 0);
      expect(plugin.cancelled, contains((3, _dm)));
      expect(await mine(_dm), isEmpty);
    });
  });
}

class _Offline implements Transport {
  @override
  Future<void> send(OutboundFrame frame) async {}

  @override
  Stream<AckFrame> get acks => const Stream.empty();

  @override
  Stream<TransportState> get state => const Stream.empty();

  @override
  TransportState get currentState => TransportState.disconnected;
}

typedef _Shown = ({
  int id,
  String? title,
  String? body,
  String? payload,
  AndroidNotificationDetails? android,
});

/// Records what would have gone up; the shade is [active].
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final List<_Shown> shown = [];
  final List<(int, String?)> cancelled = [];
  List<ActiveNotification> active = const [];

  /// As Android does with a photo it cannot decode.
  bool refusePhotos = false;

  Iterable<_Shown> get chats => shown.where((s) => s.id == 3);

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    final android = notificationDetails?.android;
    final style = android?.styleInformation;
    if (refusePhotos &&
        (android?.largeIcon != null ||
            style is MessagingStyleInformation &&
                style.messages!.any((m) => m.person?.icon != null))) {
      throw Exception('Bitmap decode failed');
    }
    shown.add((
      id: id,
      title: title,
      body: body,
      payload: payload,
      android: android,
    ));
  }

  @override
  Future<void> cancel({required int id, String? tag}) async =>
      cancelled.add((id, tag));

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => active;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
