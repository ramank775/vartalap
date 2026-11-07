/// Message notifications, WhatsApp style.
///
/// The push wake stays content-free (SYNC_PROTOCOL §12.1). Everything
/// shown here is rendered on the phone, from the local store, after the
/// pull or a live WS frame has landed: one notification per unmuted chat
/// with unread lines from others (Android MessagingStyle), a group
/// summary so Android bundles them, and the generic "New activity" only
/// for a wake whose reason we cannot see. Nothing goes up while the app
/// is on screen. Each chat's carries the sender's (or group's) photo when
/// this phone already has it, and WhatsApp's Mark as read and Reply,
/// which work with the app closed ([act]).
library vartalap.services.notifications;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max, min;
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart' show parseAttachmentUrl;
import 'package:vartalap_store/vartalap_store.dart';

const int _wakeId = 1;
const int _summaryId = 2;

/// Every chat notification has this id; its tag, the channel id, tells
/// them apart.
const int _chatId = 3;

/// Invites to us (decision 219): one notification, tapped open the
/// Invites list. Its payload, and its key among the watermarks.
const int _invitesId = 4;
const String kInvitesNotification = 'invites';
const String _group = 'vartalap.messages';

/// A chat notification's buttons, as WhatsApp has them
/// ([MessageNotifications.act]).
const String kReadAction = 'read';
const String kReplyAction = 'reply';
const List<AndroidNotificationAction> _chatActions = [
  AndroidNotificationAction(kReadAction, 'Mark as read',
      semanticAction: SemanticAction.markAsRead),
  AndroidNotificationAction(kReplyAction, 'Reply',
      inputs: [AndroidNotificationActionInput(label: 'Reply')],
      // replaced by the chat with the reply in it
      cancelNotification: false,
      semanticAction: SemanticAction.reply),
];

/// How long a chat's notification shows a reply sent from it.
const int _replyShownMs = 3000;

/// Everything goes on one "Messages" channel, high importance so a
/// message heads up, and in one group so Android bundles it.
NotificationDetails _details({
  String? tag,
  StyleInformation? style,
  bool summary = false,
  int? timeoutAfter,
  AndroidBitmap<Object>? largeIcon,
  List<AndroidNotificationAction>? actions,
  bool silent = false,
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
        timeoutAfter: timeoutAfter,
        largeIcon: largeIcon,
        actions: actions,
        silent: silent,
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

  /// A chat notification's button, app running or not: a top-level
  /// function, run by the plugin in an engine of its own (`main.dart`).
  final DidReceiveBackgroundNotificationResponseCallback? _onAction;

  /// Set by `main.dart`: a notification was tapped. [channelId] is the
  /// chat's; null for "New activity" and the summary.
  void Function(String? channelId)? onTap;

  MessageNotifications({
    required ChatStore? Function() store,
    required String? Function() selfUserId,
    FlutterLocalNotificationsPlugin? plugin,
    bool Function()? onScreen,
    DidReceiveBackgroundNotificationResponseCallback? onAction,
  })  : _store = store,
        _selfUserId = selfUserId,
        _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _onScreen = onScreen ?? _resumed,
        _onAction = onAction;

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
        onDidReceiveBackgroundNotificationResponse: _onAction,
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
      final contacts = await _contacts(store);
      final names = {
        for (final c in contacts.values) c.userId: c.displayLabel,
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
        await _showChat(chat, lines, self, contacts);
        posted = true;
      }
      // Decision 219: an invite to us alerts like a message, once.
      final invites = [
        for (final i in await store.fetchInvites())
          if (i.toUser == self) i,
      ];
      if (invites.isNotEmpty) {
        final mark = invites.last.createdAt.toString().padLeft(15, '0');
        next[kInvitesNotification] = mark;
        final seen = notified[kInvitesNotification];
        if (!quiet && (seen == null || seen.compareTo(mark) < 0)) {
          await _showInvites(invites, names);
        }
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

  /// [reply]: just sent from this notification ([act]). It shows as the
  /// last line, quietly, and the notification goes a moment later.
  Future<void> _showChat(
    ChannelListEntry chat,
    List<MessageRow> lines,
    String self,
    Map<String, ContactRow> contacts, {
    String? reply,
  }) async {
    final group = chat.kind == 'group';
    String name(String id) => contacts[id]?.displayLabel ?? 'Unknown';
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
              nameOf: name,
            )
          : messagePreview(
              m.body ?? '',
              m.contentType,
              attachment: m.attachments != null,
            );
    }

    // The round photos: each sender's, and the chat's own (a DM's is
    // its person's). Only what this phone already has.
    final chatPhoto = await _cachedPhoto(chat.avatarUrl);
    final photos = {
      for (final id in {for (final m in lines) m.authorUserId})
        id: group ? await _cachedPhoto(contacts[id]?.avatarUrl) : chatPhoto,
    };
    // Decision 222: a timed line takes the chat's notification with it
    // when its time is up, the app running or not.
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiry = lines
        .map((m) => m.expiresAtMs)
        .whereType<int>()
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    final timeout = expiry == null ? null : max(1, expiry - now);

    NotificationDetails details({required bool withPhotos}) => _details(
          tag: chat.channelId,
          timeoutAfter: reply == null
              ? timeout
              : min(timeout ?? _replyShownMs, _replyShownMs),
          largeIcon: withPhotos && chatPhoto != null
              ? FilePathAndroidBitmap(chatPhoto)
              : null,
          actions: reply == null ? _chatActions : null,
          silent: reply != null,
          style: MessagingStyleInformation(
            const Person(name: 'You'),
            conversationTitle: group ? chat.title : null,
            groupConversation: group,
            messages: [
              for (final (i, m) in lines.indexed)
                Message(
                  text(m),
                  DateTime.fromMillisecondsSinceEpoch(m.displayTimestampMs),
                  Person(
                    key: m.authorUserId,
                    name: group ? name(m.authorUserId) : chat.title,
                    // Android takes a run of lines' avatar from its first;
                    // each copy would be one more bitmap to carry.
                    icon: withPhotos &&
                            (i == 0 ||
                                lines[i - 1].authorUserId != m.authorUserId)
                        ? switch (photos[m.authorUserId]) {
                            final String path =>
                              BitmapFilePathAndroidIcon(path),
                            null => null,
                          }
                        : null,
                  ),
                ),
              // null: from the user
              if (reply != null) Message(reply, DateTime.now(), null),
            ],
          ),
        );

    Future<void> show({required bool withPhotos}) => _plugin.show(
          id: _chatId,
          title: chat.title,
          body: reply ?? text(lines.last),
          payload: chat.channelId,
          notificationDetails: details(withPhotos: withPhotos),
        );
    if (chatPhoto == null && photos.values.every((p) => p == null)) {
      return show(withPhotos: false);
    }
    try {
      await show(withPhotos: true);
    } catch (e) {
      // A photo Android would not take (unreadable, too big): the chat
      // still goes up, with Android's own initials.
      debugPrint('Notification photos failed: $e');
      await show(withPhotos: false);
    }
  }

  /// The photo at [url] if this phone already has it, else null: a
  /// notification never waits on a download (Android draws the initials
  /// instead). One not here yet is fetched for the next notification.
  static Future<String?> _cachedPhoto(String? url) async {
    // ponytail: an http(s) photo is only cached in memory.
    if (url == null || url.isEmpty || url.startsWith('http')) return null;
    try {
      // the opened (decrypted) bytes, by fileId, as AssetCache keeps them
      final path = url.startsWith('/')
          ? url
          : '${(await AssetCache.dirProvider()).path}/'
              '${parseAttachmentUrl(url).object}';
      if (await File(path).exists()) return path;
      unawaited(AssetCache.instance?.bytes(url));
    } catch (_) {/* no documents dir (tests, desktop) */}
    return null;
  }

  static Future<Map<String, ContactRow>> _contacts(ChatStore store) async =>
      {for (final c in await store.fetchContacts()) c.userId: c};

  /// A chat notification's Mark as read or Reply ([kReadAction],
  /// [kReplyAction]), in whichever engine has the account open, app on
  /// screen or swiped away. A reply joins the outbound queue like one
  /// typed in the chat; the notification shows it a moment, then goes;
  /// the chat is read. A reply the chat screen would not allow (a block,
  /// not connected yet, a group left) is not queued: the notification
  /// says why instead.
  Future<void> act(
    ChatService chats, {
    required String? action,
    required String? channelId,
    String? input,
  }) =>
      // after any showUnread under way, which could post the chat over it
      _queue = _queue.then((_) async {
        await _act(chats, action, channelId, input?.trim() ?? '');
        return 0;
      });

  Future<void> _act(
    ChatService chats,
    String? action,
    String? channelId,
    String text,
  ) async {
    final self = _selfUserId();
    final store = _store();
    if (self == null || store == null || channelId == null) return;
    try {
      if (action == kReadAction) return await chats.markRead(channelId);
      if (action != kReplyAction || text.isEmpty) return;
      final chat = await store.fetchChannel(channelId);
      if (chat == null) return;
      final refusal = await _replyRefusal(store, chat, self);
      if (refusal != null) {
        await _plugin.show(
          id: _chatId,
          title: chat.title,
          body: refusal,
          payload: channelId,
          notificationDetails: _details(
            tag: channelId,
            silent: true,
            style: BigTextStyleInformation(refusal),
          ),
        );
        return;
      }
      final lines = await _unreadLines(store, chat, self);
      await chats.sendMessage(
          channelId: channelId, body: text, authorUserId: self);
      await _showChat(chat, lines, self, await _contacts(store), reply: text);
      await chats.markRead(channelId, clearNotification: false);
      await _dropSummary(channelId);
    } catch (e) {
      debugPrint('Notification action failed: $e');
    }
  }

  /// What the chat screen would show instead of its composer, or null
  /// when a message may go (decision 219: invite only, blocks).
  static Future<String?> _replyRefusal(
    ChatStore store,
    ChannelListEntry chat,
    String self,
  ) async {
    final members = await store.fetchChannelMembers(chat.channelId);
    if (chat.kind == 'group') {
      return members.any((m) => m.userId == self)
          ? null
          : "Not sent. You're no longer a member of this group.";
    }
    final peer = members.where((m) => m.userId != self).firstOrNull?.userId;
    if (peer == null) return null; // as the chat screen: the server decides
    final link = await store.peerLink(self, peer);
    final name = chat.title;
    if (link.blocked) return 'Not sent. You blocked $name.';
    if (link.connected) return null;
    if (link.inviteReceived) {
      return 'Not sent. $name wants to chat with you: open the chat to '
          'accept.';
    }
    if (link.inviteSent) return 'Not sent. You can chat once $name accepts.';
    return 'Not sent. Vartalap is invite only: open the chat to send $name '
        'an invite.';
  }

  Future<void> _showInvites(
    List<InviteRow> invites,
    Map<String, String> names,
  ) {
    final newest = invites.last;
    final from = names[newest.fromUser] ?? 'Someone';
    final one = invites.length == 1;
    return _plugin.show(
      id: _invitesId,
      title: !one
          ? 'Invites'
          : newest.isGroup
              ? newest.name ?? 'Group invite'
              : from,
      body: !one
          ? '${invites.length} invites are waiting for your answer'
          : newest.isGroup
              ? '$from invited you to this group'
              : 'Wants to chat with you',
      payload: kInvitesNotification,
      notificationDetails: _details(tag: kInvitesNotification),
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
      await _dropSummary(channelId);
    } catch (e) {
      debugPrint('Cancelling a chat notification failed: $e');
    }
  }

  /// The summary goes with the last chat it bundles; [leaving]'s is on
  /// its way out.
  Future<void> _dropSummary(String leaving) async {
    final active = await _plugin.getActiveNotifications();
    if (!active.any((n) => n.id == _chatId && n.tag != leaving)) {
      await _plugin.cancel(id: _summaryId);
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
