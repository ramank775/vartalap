/// Message notifications, WhatsApp style.
///
/// The push wake stays content-free (SYNC_PROTOCOL §12.1). Everything
/// shown here is rendered on the phone, from the local store, after the
/// pull or a live WS frame has landed: one notification per unmuted chat
/// with unread lines from others (Android MessagingStyle), a group
/// summary so Android bundles them, and the generic "New activity" only
/// for a wake whose reason we cannot see. Nothing goes up while the app
/// is on screen.
library vartalap.services.notifications;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap_store/vartalap_store.dart';

const int _wakeId = 1;
const int _summaryId = 2;

/// Every chat notification has this id; its tag, the channel id, tells
/// them apart.
const int _chatId = 3;
const String _group = 'vartalap.messages';

/// Everything goes on one "Messages" channel, high importance so a
/// message heads up, and in one group so Android bundles it.
NotificationDetails _details({
  String? tag,
  StyleInformation? style,
  bool summary = false,
}) =>
    NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'Messages',
        channelDescription: 'New messages in chats you have not muted.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        groupKey: _group,
        tag: tag,
        styleInformation: style,
        setAsGroupSummary: summary,
        // The chats alert; the summary never does.
        groupAlertBehavior:
            summary ? GroupAlertBehavior.children : GroupAlertBehavior.all,
      ),
    );

class MessageNotifications {
  /// SharedPreferences: per channel, the newest line already notified
  /// ([_mark]), so posting a chat again only alerts for lines past it.
  static const String keyNotified = 'v3.notifications.notified';

  /// The signed-in account's store; null while no one is signed in.
  final ChatStore? Function() _store;
  final String? Function() _selfUserId;
  final FlutterLocalNotificationsPlugin _plugin;
  final bool Function() _onScreen;

  /// Set by `main.dart`: a notification was tapped. [channelId] is the
  /// chat's; null for "New activity" and the summary.
  void Function(String? channelId)? onTap;

  MessageNotifications({
    required ChatStore? Function() store,
    required String? Function() selfUserId,
    FlutterLocalNotificationsPlugin? plugin,
    bool Function()? onScreen,
  })  : _store = store,
        _selfUserId = selfUserId,
        _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _onScreen = onScreen ?? _resumed;

  /// `lifecycleState` is null in the background isolate a distributor
  /// starts, which counts as off screen.
  static bool _resumed() =>
      SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Once per isolate, before anything is shown. Registers the tap
  /// handler.
  Future<void> init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // A white silhouette: Android draws the small icon as a mask, so
          // the full-colour launcher icon came out as a white square.
          android: AndroidInitializationSettings('@drawable/ic_stat_vartalap'),
        ),
        onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
      );
    } catch (e) {
      debugPrint('Local notifications init failed: $e');
    }
  }

  /// The chat whose notification launched the app, if one did.
  Future<String?> launchChannel() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return details!.notificationResponse?.payload;
    } catch (_) {
      return null; // no plugin (tests, desktop)
    }
  }

  StreamSubscription<String>? _storedSub;
  Timer? _soon;

  /// Replace the source of "a message from someone else was stored"
  /// (`InboundReceiver.peerMessagesStored`): the live WS and every pull,
  /// a wake's included, land there. A burst becomes one [showUnread] a
  /// second later. Pass null to detach.
  void bindSource(Stream<String>? stored) {
    _storedSub?.cancel();
    _soon?.cancel();
    _storedSub = stored?.listen((_) {
      _soon?.cancel();
      _soon = Timer(const Duration(seconds: 1), showUnread);
    });
  }

  Future<int> _queue = Future<int>.value(0);

  /// Post every unmuted chat that has unread lines past its watermark.
  /// Returns how many unmuted chats have unread lines, posted now or
  /// earlier. One run at a time, so two triggers never alert twice for
  /// one line.
  Future<int> showUnread() => _queue = _queue.then((_) => _showUnread());

  Future<int> _showUnread() async {
    final self = _selfUserId();
    final store = _store();
    if (self == null || store == null) return 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      // A wake's background isolate writes this too.
      await prefs.reload();
      final notified = (jsonDecode(prefs.getString(keyNotified) ?? '{}')
              as Map<String, dynamic>)
          .cast<String, String>();
      final next = <String, String>{};
      final quiet = _onScreen();
      final now = DateTime.now().millisecondsSinceEpoch;
      final names = {
        for (final c in await store.fetchContacts()) c.userId: c.displayLabel,
      };
      var chats = 0, messages = 0, posted = false;
      for (final chat in await store.fetchChannelList()) {
        if (chat.unreadCount == 0) continue;
        final lines = await _unreadLines(store, chat, self);
        final newest =
            lines.where((m) => m.contentType != kGroupEventType).lastOrNull;
        if (newest == null) continue;
        final mark = _mark(newest);
        next[chat.channelId] = mark;
        // On screen or muted: nothing goes up, but the lines count as
        // notified, so leaving the app or unmuting never alerts for them.
        if (quiet || chat.isMutedAt(now)) continue;
        chats++;
        messages += chat.unreadCount;
        final seen = notified[chat.channelId];
        if (seen != null && seen.compareTo(mark) >= 0) continue;
        await _showChat(chat, lines, self, names);
        posted = true;
      }
      // Only chats with unread lines keep a watermark: reading a chat
      // drops its entry, and the next message there alerts afresh.
      await prefs.setString(keyNotified, jsonEncode(next));
      if (posted && chats > 1) await _showSummary(chats, messages);
      return chats;
    } catch (e) {
      debugPrint('Message notifications failed: $e');
      return 0;
    }
  }

  /// ponytail: (server time, message id) as one string that sorts like
  /// the channel does, zero-padded to 15 digits (good until year 33658).
  static String _mark(MessageRow m) =>
      '${(m.serverTimestampMs ?? 0).toString().padLeft(15, '0')} '
      '${m.messageId}';

  /// The chat's unread lines from others, oldest first: its newest
  /// [ChannelListEntry.unreadCount] messages from others (a deleted one
  /// still counts, as it did when it arrived, but is not shown), with
  /// the group event lines among or right before them.
  ///
  /// ponytail: scans the newest 50 rows; older unread lines are left
  /// out, the summary's count still has them.
  Future<List<MessageRow>> _unreadLines(
    ChatStore store,
    ChannelListEntry chat,
    String self,
  ) async {
    final lines = <MessageRow>[];
    var unread = chat.unreadCount;
    for (final m in await store.fetchChannelMessages(chat.channelId,
        limit: 50)) {
      final event = m.contentType == kGroupEventType;
      if (unread == 0 && !event) break;
      if (m.authorUserId == self) continue;
      if (!event) unread--;
      if (!m.tombstoned) lines.add(m);
    }
    return lines.reversed.toList();
  }

  Future<void> _showChat(
    ChannelListEntry chat,
    List<MessageRow> lines,
    String self,
    Map<String, String> names,
  ) {
    final group = chat.kind == 'group';
    String text(MessageRow m) {
      final event = m.contentType == kGroupEventType
          ? GroupEvent.parse(m.body)
          : null;
      // The chat list's wording, for every kind of line.
      return event != null
          ? groupEventText(
              event,
              actorUserId: m.authorUserId,
              selfUserId: self,
              nameOf: (id) => names[id] ?? 'Unknown',
            )
          : messagePreview(
              m.body ?? '',
              m.contentType,
              attachment: m.attachments != null,
            );
    }

    return _plugin.show(
      id: _chatId,
      title: chat.title,
      body: text(lines.last),
      payload: chat.channelId,
      notificationDetails: _details(
        tag: chat.channelId,
        style: MessagingStyleInformation(
          const Person(name: 'You'),
          conversationTitle: group ? chat.title : null,
          groupConversation: group,
          messages: [
            for (final m in lines)
              Message(
                text(m),
                DateTime.fromMillisecondsSinceEpoch(m.displayTimestampMs),
                Person(
                  key: m.authorUserId,
                  name: group ? names[m.authorUserId] ?? 'Unknown' : chat.title,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSummary(int chats, int messages) => _plugin.show(
        id: _summaryId,
        title: 'Vartalap',
        body: '$messages messages from $chats chats',
        notificationDetails: _details(summary: true),
      );

  /// After a push wake. [pulled] is how many frames its pull handed
  /// over, null when the pull failed or ran out of time.
  ///
  /// The chats it brought go up as usual. "New activity" is kept for a
  /// wake we cannot account for: a failed pull, or one that came back
  /// empty with nothing unread to show. A pull of only receipts, our
  /// own echoes or muted chats posts nothing.
  Future<void> afterWake(int? pulled) async {
    final chats = await showUnread();
    if (_onScreen() || pulled != null && (pulled > 0 || chats > 0)) return;
    try {
      await _plugin.show(
        id: _wakeId,
        title: 'Vartalap',
        body: 'New activity',
        notificationDetails: _details(),
      );
    } catch (e) {
      debugPrint('Wake notification failed: $e');
    }
  }

  /// The chat was read: its notification goes, and with the last one
  /// the summary.
  Future<void> cancelChat(String channelId) async {
    try {
      await _plugin.cancel(id: _chatId, tag: channelId);
      final active = await _plugin.getActiveNotifications();
      if (!active.any((n) => n.id == _chatId && n.tag != channelId)) {
        await _plugin.cancel(id: _summaryId);
      }
    } catch (e) {
      debugPrint('Cancelling a chat notification failed: $e');
    }
  }

  /// The app came on screen: "New activity" has said its piece.
  Future<void> cancelWake() async {
    try {
      await _plugin.cancel(id: _wakeId);
    } catch (_) {/* no plugin (tests, desktop) */}
  }

  /// Logout: nothing of the old account stays in the shade.
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {/* no plugin (tests, desktop) */}
    await (await SharedPreferences.getInstance()).remove(keyNotified);
  }
}
