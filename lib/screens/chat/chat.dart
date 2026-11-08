/// Chat screen — reactive over `chatService.watchMessages(channelId)`.
library vartalap.screens.chat.chat;

import 'dart:async';
import 'dart:math' as math;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'
    show
        BottomActionBarConfig,
        CategoryExtraTab,
        CategoryViewConfig,
        Config,
        EmojiPicker,
        EmojiViewConfig,
        SkinToneConfig;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart' show SecureUnlock;
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap/screens/albums/albums.dart';
import 'package:vartalap/screens/chat/attachment_preview.dart';
import 'package:vartalap/screens/chat/forward.dart';
import 'package:vartalap/screens/chat/message_info.dart';
import 'package:vartalap/screens/chat/link_preview.dart';
import 'package:vartalap/screens/chat/live_location.dart';
import 'package:vartalap/screens/chat/message_options.dart';
import 'package:vartalap/screens/chat/presence_line.dart';
import 'package:vartalap/screens/chat/rich_messages.dart';
import 'package:vartalap/screens/chat/video_view.dart';
import 'package:vartalap/screens/chat/voice_note.dart';
import 'package:vartalap/screens/chat_info/chat_info.dart';
import 'package:vartalap/screens/chat_info/media.dart';
import 'package:vartalap/screens/invites/invites.dart';
import 'package:vartalap/screens/labels/labels.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap/utils/phone_number.dart';
import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/chat_action_sheets.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';

/// In `MaterialApp.navigatorObservers`, so a chat hears when the screen
/// over it closes and the user is looking at it again.
final RouteObserver<ModalRoute<void>> chatRouteObserver = RouteObserver();

class ChatScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  final String channelKind; // 'dm' | 'group'
  final ChatService chatService;
  final AuthService authService;

  /// V3_ARCHITECTURE decision 11 — how long Delete stays undoable
  /// before the op is enqueued. A knob so a widget test doesn't have to
  /// burn five seconds of wall clock proving the timer works.
  final Duration undoWindow;

  /// Opens scrolled to, and flashing, this message: a search hit or a
  /// starred message picked from outside the chat.
  final String? initialMessageId;

  /// Opens with this in the composer: text shared from another app.
  final String? initialText;

  const ChatScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.channelKind,
    required this.chatService,
    required this.authService,
    this.undoWindow = const Duration(seconds: 5),
    this.initialMessageId,
    this.initialText,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with RouteAware {
  late final TextEditingController _input =
      TextEditingController(text: widget.initialText);
  final FocusNode _inputFocus = FocusNode();

  /// The body as it was when Edit started; confirming it unchanged sends
  /// nothing (an edit would mark the message "edited" for no change).
  String? _editingOriginal;
  bool _sending = false;
  StreamSubscription<List<MessageRow>>? _readMarkerSub;
  String? _lastMarkedReadMessageId;

  /// The newest peer message in the chat; read once the user can see it
  /// ([_markSeen]).
  String? _latestPeerMessageId;
  late final AppLifecycleListener _lifecycle;
  ModalRoute<void>? _route;

  /// Page window for the one live query. "Load older" grows it in
  /// place (see [MessageWindow]) rather than opening a second stream.
  static const int _pageSize = 50;
  final MessageWindow _window = MessageWindow(limit: _pageSize);
  final ScrollController _scroll = ScrollController();
  bool _hasMoreOlder = true;
  bool _loadingOlder = false;

  /// Created once (broadcast so both the read-receipt listener below and
  /// the StreamBuilder in [build] share it) so `setState` calls — typing
  /// timers, the `_sending` flag, etc. — don't resubscribe and re-run the
  /// underlying SQL query on every rebuild.
  late final Stream<List<MessageRow>> _messagesStream = widget.chatService
      .watchMessages(widget.channelId, window: _window)
      .asBroadcastStream();

  /// message_id → op_id of the failed outbound op behind it, from
  /// [ChatService.watchFailures] (SPIKE_B_SYNC.md §10). Drives the red
  /// bubble + inline Retry in frame d1.
  Map<String, String> _failedOps = const {};
  StreamSubscription<List<OutboundOpRow>>? _failureSub;

  /// Ops already toasted about, so a re-emit arriving before the
  /// dismissal lands doesn't say the same thing twice.
  final Set<String> _reportedFailures = {};

  /// Message being edited in the composer, if any.
  String? _editingMessageId;

  /// Message being replied to, if any.
  MessageRow? _replyTo;

  /// Decision 222: the next message's timer and secure options. Back to
  /// none once it is sent.
  ComposeOptions _options = kNoComposeOptions;

  /// WhatsApp's emoji panel, in the keyboard's place and as tall as the
  /// keyboard last was.
  bool _emojiOpen = false;
  // ponytail: a typical keyboard's height until this phone's is seen.
  double _keyboardHeight = 280;

  /// Long texts the user opened with "Read more".
  final Set<String> _expanded = {};

  /// The chat's ⋮; [_menuMore] while it shows its "More" page.
  final GlobalKey<PopupMenuButtonState<VoidCallback>> _menuKey = GlobalKey();
  bool _menuMore = false;

  /// SYNC_PROTOCOL §27: the typed link's preview, none for an edit or a
  /// secure or timed message.
  late final ComposerLinkPreview _linkPreview = ComposerLinkPreview(_input,
      enabled: () =>
          widget.chatService.linkPreviews.value &&
          _editingMessageId == null &&
          _options == kNoComposeOptions);

  /// The voice note being recorded; null while the composer is text.
  AudioRecorder? _recorder;
  DateTime _recordingSince = DateTime.now();
  Timer? _recordingTicker;
  // Then it sends itself ([kMaxVoiceNote]).
  static const Duration _maxVoiceNote = kMaxVoiceNote;

  /// The one delete sitting in its undo window. Committing is ours to
  /// do — the timer outlives the snackbar, and [dispose] flushes — so a
  /// tombstone can never strand un-enqueued.
  /// Tombstoned locally, waiting out the undo window together.
  List<String> _deletingMessageIds = const [];
  Timer? _deleteTimer;

  /// Per-message keys so [Scrollable.ensureVisible] can jump to a row by
  /// id. Kept across rebuilds so a key created during the first build
  /// (when the search-jumped row was visible) is still valid when we
  /// scroll back to it later.
  final Map<String, GlobalKey> _messageKeys = {};

  /// Highlighted by a recent search-jump; cleared after a brief pulse so
  /// the user can see which message matched.
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  /// WhatsApp's in-chat search: the app bar turns into a field with
  /// up / down arrows, over the chat. [_searchQuery] is what the last
  /// search ran for (marked in every bubble), [_matches] its hits'
  /// message ids, newest first, and [_matchIndex] the one shown.
  bool _searchOpen = false;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounce;
  String _searchQuery = '';
  List<String> _matches = const [];
  int _matchIndex = 0;

  /// Selected messages (WhatsApp's selection, in the order picked):
  /// long-press starts it, taps add and remove. The app bar shows what
  /// can be done to all of them; with exactly one, the reaction bar
  /// floats over it, following it through [_selectedLink].
  final Set<String> _selectedIds = {};
  final LayerLink _selectedLink = LayerLink();

  /// The page last rendered, for the selection bar's fresh copy of the
  /// selected row (its reactions change under it).
  List<MessageRow> _lastMessages = const [];

  /// The reaction bar goes under the message when it's too close to the
  /// top of the list to fit above.
  bool _barBelow = false;
  final GlobalKey _listKey = GlobalKey();

  /// Outbound typing-indicator state.
  ///
  /// On every keystroke we send `is_typing=true` if either we haven't
  /// notified yet OR it's been ≥[_typingHeartbeat] since the last `true`
  /// we sent. The receiver's TTL ([_peerTypingTtl] below) is wider than
  /// our heartbeat so a single dropped frame doesn't strand the
  /// indicator.
  ///
  /// We send `is_typing=false` when:
  ///   - the input drains to empty
  ///   - on send
  ///   - on screen dispose
  ///   - after [_typingQuietWindow] of inactivity (the timer below)
  bool _typingNotified = false;
  int _lastTypingHeartbeatMs = 0;
  Timer? _typingQuietTimer;
  static const Duration _typingHeartbeat = Duration(seconds: 3);
  static const Duration _typingQuietWindow = Duration(seconds: 4);

  /// Inbound peer-typing state. Map from peer user_id to the timer that
  /// will auto-clear them if no `is_typing=false` arrives. Multi-user
  /// (groups) shows a "Several people are typing" hint when >1 active.
  final Map<String, Timer> _peerTypingTimers = {};
  StreamSubscription<TypingEvent>? _typingSub;
  static const Duration _peerTypingTtl = Duration(seconds: 6);

  /// Sender display labels keyed by user_id. Populated once from the
  /// channel-members + contacts join so group bubbles can render the
  /// author's name without a per-message fetch. DM chats don't render
  /// sender names so the cache is unused there but cheap to load.
  Map<String, String> _memberNames = const {};

  /// Group only: who is in it now (the header's names, and whether we
  /// may still send), and its live row (a rename or a new photo from
  /// someone else lands while the chat is open). Re-read on every
  /// [GroupEvent] line.
  List<ChannelMemberRow>? _members;
  ChannelListEntry? _channel;

  /// A 1:1 chat's other person, and where we stand with them (decision
  /// 219): until they are connected, [InviteBar] takes the composer's
  /// place.
  String? _peerUserId;
  PeerLink? _link;
  StreamSubscription<PeerLink>? _linkSub;
  String? _lastGroupEventId;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    _linkPreview; // listens from here on
    _typingSub = widget.chatService.typingEvents.listen(_onPeerTyping);
    _scroll.addListener(_onScroll);
    _loadMemberNames();
    // Trim 4: a DM has no server-side row, so the server cannot fan a
    // peer's profile edits to us (SYNC_PROTOCOL §10.3). Pull them when
    // the chat opens — the one moment the staleness would show.
    unawaited(widget.chatService.refreshDmPeerProfile(widget.channelId).then(
        (_) => widget.channelKind == 'group' ? null : _loadMemberNames()));
    // Any delete whose undo window elapsed while this screen was closed
    // (or the app was dead) gets enqueued now.
    unawaited(widget.chatService.sweepExpiredDeletes(widget.channelId));
    _failureSub = widget.chatService.watchFailures().listen(_onFailures);
    // While the chat is on screen, every new peer message that lands
    // also counts as read ([_markSeen]). Subscribe once (to the same
    // stream the StreamBuilder below renders, so opening a chat runs one
    // live query, not two) and re-mark whenever the latest message_id
    // from a peer changes. This also covers "mark read on open": the
    // first emission is the initial query result, so there's no separate
    // eager markRead call here (that used to double-enqueue the
    // read-receipt op).
    _lifecycle = AppLifecycleListener(onResume: _markSeen);
    final localUserId = widget.authService.currentUserId;
    var jumpTo = widget.initialMessageId;
    _readMarkerSub = _messagesStream.listen((rows) {
      // Every emission answers the paging question too: a short page
      // means we've reached the start of the conversation.
      _loadingOlder = false;
      _hasMoreOlder = rows.length >= _window.limit;
      if (jumpTo != null) {
        final id = jumpTo!;
        jumpTo = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpToMessage(id);
        });
      }
      if (localUserId == null) return;
      final latestEvent =
          rows.where((r) => r.contentType == kGroupEventType).firstOrNull;
      if (latestEvent != null &&
          latestEvent.messageId != _lastGroupEventId) {
        _lastGroupEventId = latestEvent.messageId;
        _loadMemberNames();
      }
      // Newest peer message first — `watchMessages` returns newest-first.
      MessageRow? latestPeer;
      for (final r in rows) {
        if (r.authorUserId != localUserId && !r.tombstoned) {
          latestPeer = r;
          break;
        }
      }
      if (latestPeer == null) return;
      if (latestPeer.messageId == _latestPeerMessageId) return;
      _latestPeerMessageId = latestPeer.messageId;
      _markSeen();
      // Group chats render the sender's name above peer bubbles. If
      // we just observed an author we haven't seen before (e.g. a
      // ChannelMemberAdded push that materialized after this screen
      // loaded, or a race on first group create), refresh the name
      // cache so the bubble label resolves instead of "Unknown".
      if (widget.channelKind == 'group' &&
          !_memberNames.containsKey(latestPeer.authorUserId)) {
        _loadMemberNames();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      chatRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) chatRouteObserver.subscribe(this, route);
    }
  }

  /// A screen opened over the chat (Chat info, a photo) closed.
  @override
  void didPopNext() => _markSeen();

  /// Messages are read when the user could have seen them: the app in
  /// front (not in the background or behind the shade) and this chat
  /// the top screen. Otherwise they stay unread, and notify, until the
  /// user comes back ([AppLifecycleListener.onResume], [didPopNext]).
  void _markSeen() {
    final latest = _latestPeerMessageId;
    if (!mounted || latest == null || latest == _lastMarkedReadMessageId) {
      return;
    }
    // Null before the platform first reports one (a cold start from a
    // notification), and the chat is on screen then.
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    if (_route?.isCurrent == false) return;
    _lastMarkedReadMessageId = latest;
    widget.chatService.markRead(widget.channelId);
  }

  @override
  void dispose() {
    chatRouteObserver.unsubscribe(this);
    _lifecycle.dispose();
    // Leaving the screen ends the undo window: commit rather than
    // leaving a tombstone that nobody will ever enqueue.
    _deleteTimer?.cancel();
    for (final id in _deletingMessageIds) {
      unawaited(widget.chatService.commitDelete(
        channelId: widget.channelId,
        messageId: id,
      ));
    }
    // A voice note is sent on purpose or not at all.
    _recordingTicker?.cancel();
    final recorder = _recorder;
    if (recorder != null) {
      recorder.cancel().whenComplete(recorder.dispose).ignore();
    }
    unawaited(stopVoiceNote());
    _failureSub?.cancel();
    _linkSub?.cancel();
    _scroll.dispose();
    _readMarkerSub?.cancel();
    _highlightTimer?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _typingQuietTimer?.cancel();
    for (final t in _peerTypingTimers.values) {
      t.cancel();
    }
    _peerTypingTimers.clear();
    _typingSub?.cancel();
    if (_typingNotified) {
      // Don't leave the peer staring at "is typing…" after we leave.
      widget.chatService.notifyTyping(
        channelId: widget.channelId,
        isTyping: false,
      );
    }
    _input.removeListener(_onInputChanged);
    _linkPreview.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final hasText = _input.text.trim().isNotEmpty;
    if (!hasText) {
      if (_typingNotified) {
        _typingNotified = false;
        _lastTypingHeartbeatMs = 0;
        widget.chatService.notifyTyping(
          channelId: widget.channelId,
          isTyping: false,
        );
      }
      _typingQuietTimer?.cancel();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final dueForHeartbeat = !_typingNotified ||
        now - _lastTypingHeartbeatMs >= _typingHeartbeat.inMilliseconds;
    if (dueForHeartbeat) {
      _typingNotified = true;
      _lastTypingHeartbeatMs = now;
      widget.chatService.notifyTyping(
        channelId: widget.channelId,
        isTyping: true,
      );
    }
    _typingQuietTimer?.cancel();
    _typingQuietTimer = Timer(_typingQuietWindow, () {
      if (!mounted || !_typingNotified) return;
      _typingNotified = false;
      _lastTypingHeartbeatMs = 0;
      widget.chatService.notifyTyping(
        channelId: widget.channelId,
        isTyping: false,
      );
    });
  }

  void _onPeerTyping(TypingEvent ev) {
    if (!mounted) return;
    if (ev.channelId != widget.channelId) return;
    if (ev.userId == widget.authService.currentUserId) return;
    setState(() {
      _peerTypingTimers[ev.userId]?.cancel();
      if (ev.isTyping) {
        _peerTypingTimers[ev.userId] = Timer(_peerTypingTtl, () {
          if (!mounted) return;
          setState(() => _peerTypingTimers.remove(ev.userId));
        });
      } else {
        _peerTypingTimers.remove(ev.userId);
      }
    });
  }

  GlobalKey _keyForMessage(String messageId) =>
      _messageKeys.putIfAbsent(messageId, GlobalKey.new);

  Future<void> _loadMemberNames() async {
    final members =
        await widget.chatService.fetchChannelMembers(widget.channelId);
    // Everyone we know, not just current members: someone who left
    // still labels their old messages and the "left" line.
    final contacts = await widget.chatService.discoverContacts();
    final channel = await widget.chatService.fetchChannel(widget.channelId);
    if (!mounted) return;
    setState(() {
      _memberNames = {
        for (final c in contacts) c.userId: c.displayLabel,
        for (final m in members)
          m.userId: m.contact?.displayLabel ?? 'Unknown',
      };
      _members = members;
      _channel = channel;
    });
    final me = widget.authService.currentUserId;
    final peer = members.where((m) => m.userId != me).firstOrNull?.userId;
    if (widget.channelKind != 'group' && peer != null && _linkSub == null) {
      _peerUserId = peer;
      _linkSub = widget.chatService.watchPeerLink(peer).listen((link) {
        if (mounted) setState(() => _link = link);
      });
    }
  }

  /// Chat menu's Block / Unblock (decision 219).
  Future<void> _toggleBlock() async {
    final peer = _peerUserId;
    if (peer == null) return;
    final block = _link?.blocked != true;
    if (block && !await confirmBlock(context, _title)) return;
    try {
      await widget.chatService.setBlocked(peer, block);
    } catch (e) {
      if (mounted) showInviteError(context, e);
    }
  }

  /// The title row, and the menu's View contact / Group info.
  void _openChatInfo() {
    Navigator.of(context).push(
      MaterialPageRoute<String>(
        builder: (_) => ChatInfoScreen(
          channelId: widget.channelId,
          channelName: _title,
          channelKind: widget.channelKind,
          chatService: widget.chatService,
          authService: widget.authService,
        ),
      ),
    ).then((result) {
      // A rename, member change or mute made in there.
      _loadMemberNames();
      if (result == null || !mounted) return;
      // A message picked under Media (a secure one).
      _jumpToMessage(result);
    });
  }

  void _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));

  /// WhatsApp's ⋮ over a chat, holding only what this app can do; its
  /// "More" shows the rarer actions in the same place.
  List<(String, VoidCallback)> _menuItems() {
    final group = widget.channelKind == 'group';
    final peer = _peerUserId;
    if (_menuMore) {
      return [
        if (peer != null) ...[
          (
            'Report',
            () => showReportDialog(
                  context,
                  chatService: widget.chatService,
                  userId: peer,
                  name: _title,
                  channelId: widget.channelId,
                )
          ),
          (_link?.blocked == true ? 'Unblock' : 'Block', _toggleBlock),
        ],
        if (group && _members != null && _canSend) ('Exit group', _exitGroup),
        (
          'Clear chat',
          () => confirmClearHistory(
                context: context,
                chatService: widget.chatService,
                channelId: widget.channelId,
                isGroup: group,
              )
        ),
      ];
    }
    void media() => Navigator.of(context)
            .push(MaterialPageRoute<String>(
              builder: (_) => MediaScreen(
                channelId: widget.channelId,
                chatService: widget.chatService,
                nameOf: (id) => id == widget.authService.currentUserId
                    ? 'You'
                    : _memberNames[id] ?? widget.channelName,
              ),
            ))
            // A secure message picked there: show it here.
            .then((id) {
          if (id != null && mounted) _jumpToMessage(id);
        });
    return [
      (group ? 'Group info' : 'View contact', _openChatInfo),
      if (group) ('Group media', media),
      ('Search', _openSearch),
      if (!group) ('Media, links and docs', media),
      // A 1:1 chat's wait for its other person, as in chat info.
      if (group || peer != null) ('Albums', _openAlbums),
      if (muteLabel(_channel?.mutedUntilMs) == null)
        ('Mute notifications', _mute)
      else
        ('Unmute notifications', () => _mute(off: true)),
      if (peer != null)
        (
          'Add to label',
          () => pickContactLabels(context, widget.chatService, peer)
        ),
      (
        'More',
        () {
          _menuMore = true;
          _menuKey.currentState?.showButtonMenu();
        }
      ),
    ];
  }

  void _openAlbums() => _push(AlbumsScreen(
        chatService: widget.chatService,
        channelId: widget.channelId,
        peer: widget.channelKind == 'group' ? null : _peerUserId,
      ));

  /// Attach › Album (decision 233): make a new album, or open the chat's
  /// albums to add photos to one.
  Future<void> _albumChoice() async {
    final create = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('New album'),
              subtitle: const Text('For a family day or an occasion'),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Add to an album'),
              subtitle: const Text("Pick one of this chat's albums"),
              onTap: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    );
    if (create == null || !mounted) return;
    if (!create) return _openAlbums();
    final album = await newAlbum(context,
        chatService: widget.chatService,
        channelId: widget.channelId,
        peer: widget.channelKind == 'group' ? null : _peerUserId);
    if (album == null || !mounted) return;
    _push(AlbumScreen(
      chatService: widget.chatService,
      channelId: album.channelId,
      albumId: album.albumId,
      album: album,
    ));
  }

  /// Mute picks a length on frame f's sheet; Unmute is one tap.
  Future<void> _mute({bool off = false}) async {
    if (off) {
      await widget.chatService.setMuted(widget.channelId, null);
    } else {
      await showMuteSheet(
        context: context,
        chatService: widget.chatService,
        channelIds: [widget.channelId],
        mutedUntilMs: null,
      );
    }
    await _loadMemberNames(); // re-reads the channel row's mute
  }

  /// Group info's Leave group, from the chat's menu. Decision 9: an
  /// owner's confirm names who takes over.
  Future<void> _exitGroup() async {
    final me = widget.authService.currentUserId ?? '';
    final members = _members ?? const <ChannelMemberRow>[];
    final owner = members.any((m) => m.userId == me && m.role == 'owner');
    final heir = owner ? successorAfterOwnerLeaves(members, me) : null;
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Exit $_title?'),
        content: Text(
          'You will stop receiving messages. The chat and its history '
          'stay on this phone until you delete it. Other members stay in '
          'the group and can add you back.'
          '${heir == null ? '' : ' ${_memberNames[heir.userId] ?? 'Unknown'} '
              'will become the owner.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Exit group',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (exit != true) return;
    try {
      await widget.chatService.leaveGroup(widget.channelId, selfUserId: me);
    } catch (_) {
      _toast("Couldn't exit the group. Try again.");
      return;
    }
    await _loadMemberNames();
  }

  /// The composer's smiley: the keyboard goes and the emoji panel takes
  /// its place; the keyboard icon brings the keyboard back. The field
  /// keeps its focus, so emoji land at the cursor.
  void _toggleEmoji() {
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      if (_inputFocus.hasFocus) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      } else {
        _inputFocus.requestFocus();
      }
      return;
    }
    final keyboard = MediaQuery.viewInsetsOf(context).bottom -
        MediaQuery.viewPaddingOf(context).bottom;
    if (keyboard > 120) _keyboardHeight = keyboard;
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() => _emojiOpen = true);
  }

  /// The emoji panel, under the composer and above the system
  /// navigation bar. Recently used ones come first.
  Widget _emojiPanel(ColorScheme scheme) {
    final bg = scheme.surfaceContainerLow;
    return ColoredBox(
      color: bg,
      child: SafeArea(
        top: false,
        child: EmojiPicker(
          textEditingController: _input,
          config: Config(
            height: _keyboardHeight,
            emojiViewConfig: EmojiViewConfig(
              // Eight a row, not the package's ten: easier to hit.
              columns: 8,
              emojiSizeMax: 30,
              backgroundColor: bg,
              noRecents: Text(
                'Emoji you use will show here',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            categoryViewConfig: CategoryViewConfig(
              backgroundColor: bg,
              indicatorColor: scheme.primary,
              iconColorSelected: scheme.primary,
              iconColor: scheme.onSurfaceVariant,
              backspaceColor: scheme.onSurfaceVariant,
              extraTab: CategoryExtraTab.BACKSPACE,
            ),
            skinToneConfig: SkinToneConfig(
              dialogBackgroundColor: scheme.surfaceContainerHighest,
              indicatorColor: scheme.onSurfaceVariant,
            ),
            bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
          ),
        ),
      ),
    );
  }

  /// "Dev_Two, Asha, You" under a group's name (WhatsApp).
  String? get _memberLine {
    final members = _members;
    if (members == null || widget.channelKind != 'group') return null;
    final me = widget.authService.currentUserId;
    final names = [
      for (final m in members)
        if (m.userId != me) _memberNames[m.userId] ?? 'Unknown',
    ]..sort();
    if (members.any((m) => m.userId == me)) names.add('You');
    return names.join(', ');
  }

  /// A group's name follows renames; a DM's is whatever we were given.
  String get _title => _channel?.title ?? widget.channelName;

  /// False once someone removed us: the chat stays, read only.
  bool get _canSend =>
      widget.channelKind != 'group' ||
      _members == null ||
      _members!.any((m) => m.userId == widget.authService.currentUserId);

  /// Runs [text] through the store's search (case-insensitive, newest
  /// first) and jumps to the newest hit.
  Future<void> _runSearch(String text) async {
    _searchDebounce?.cancel();
    final query = text.trim();
    final rows = query.isEmpty
        ? const <MessageRow>[]
        : await widget.chatService
            .searchInChannel(channelId: widget.channelId, query: query);
    // Closed, or typed past, while the store looked.
    if (!mounted || !_searchOpen || _search.text.trim() != query) return;
    setState(() {
      _searchQuery = query;
      // A card's body is a vCard / geo URI / iCalendar, not its words.
      _matches = [
        for (final m in rows)
          if (!isRichType(m.contentType)) m.messageId,
      ];
      _matchIndex = 0;
    });
    if (_matches.isNotEmpty) {
      _jumpToMessage(_matches.first);
    } else if (query.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('No results found')));
    }
  }

  /// Up is the older hit, down the newer one.
  void _goToMatch(int i) {
    final newer = i < _matchIndex;
    setState(() => _matchIndex = i);
    _jumpToMessage(_matches[i], newer: newer);
  }

  /// Opening search takes the keyboard, even from the composer
  /// (`autofocus` won't take it from a focused field).
  void _openSearch() {
    setState(() {
      _searchOpen = true;
      _emojiOpen = false;
    });
    _searchFocus.requestFocus();
  }

  /// Back leaves search. Focus is let go of first: the field leaving the
  /// tree while focused hands focus back to the composer, and up comes
  /// the keyboard.
  void _closeSearch() {
    _searchFocus.unfocus();
    _searchDebounce?.cancel();
    _highlightTimer?.cancel();
    _search.clear();
    setState(() {
      _searchOpen = false;
      _searchQuery = '';
      _matches = const [];
      _highlightedMessageId = null;
    });
  }

  /// The search bar: back, the field, then older / newer.
  AppBar _searchBar(Color onBar) => AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _closeSearch,
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _search,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search…',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
            hintStyle: TextStyle(color: onBar.withValues(alpha: 0.7)),
          ),
          style: TextStyle(color: onBar, fontSize: 18),
          cursorColor: onBar,
          onChanged: (text) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(
                const Duration(milliseconds: 400), () => _runSearch(text));
          },
          onSubmitted: _runSearch,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: 'Previous match',
            disabledColor: onBar.withValues(alpha: 0.38),
            onPressed: _matchIndex + 1 < _matches.length
                ? () => _goToMatch(_matchIndex + 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: 'Next match',
            disabledColor: onBar.withValues(alpha: 0.38),
            onPressed:
                _matchIndex > 0 ? () => _goToMatch(_matchIndex - 1) : null,
          ),
        ],
      );

  /// After a send, show it: the list is reversed, so the newest
  /// message is at offset 0.
  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _jumpToMessage(String messageId, {bool newer = false}) async {
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer?.cancel();
    // Rows off screen aren't built, so there is nothing to scroll to
    // yet: page toward the target until its row exists, then bring it
    // into view. Older is the reversed list's far end; paging into it
    // grows the window (_onScroll), so wait out each page as it loads.
    // ponytail: one direction and 200 frames at most; a reply is behind
    // you, a search hit is the way its arrow points. A hit thousands of
    // messages back may stop short: grow the window to it first then.
    for (var i = 0; i < 200 && mounted; i++) {
      await WidgetsBinding.instance.endOfFrame;
      // A later jump (the next search hit) took over.
      if (_highlightedMessageId != messageId) return;
      final ctx = _messageKeys[messageId]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.3,
        );
        break;
      }
      if (!_scroll.hasClients) break;
      final pos = _scroll.position;
      final step = pos.viewportDimension * 0.8;
      if (newer) {
        if (pos.pixels <= pos.minScrollExtent) break;
        _scroll.jumpTo(math.max(pos.pixels - step, pos.minScrollExtent));
      } else if (pos.pixels < pos.maxScrollExtent) {
        _scroll.jumpTo(math.min(pos.pixels + step, pos.maxScrollExtent));
      } else if (!_loadingOlder) {
        break; // the start of the chat
      }
    }
    if (!mounted || _highlightedMessageId != messageId) return;
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _highlightedMessageId = null);
    });
  }

  // --- paging ------------------------------------------------------------

  void _onScroll() {
    if (!_hasMoreOlder || _loadingOlder || !_scroll.hasClients) return;
    final pos = _scroll.position;
    // Reversed list: "older" is further down the scroll extent.
    if (pos.pixels < pos.maxScrollExtent - 300) return;
    _loadingOlder = true;
    _window.grow(_pageSize); // re-runs the same live query, one stream
  }

  // --- failures (SPIKE_B_SYNC.md §10) -------------------------------------

  /// Two different surfaces, because the two failures mean different
  /// things to the user: a send that never landed stays on its own
  /// bubble with a Retry (frame d1), while a rejected edit or delete has
  /// already been rolled back by the store — there is nothing to retry,
  /// only something to be told about.
  void _onFailures(List<OutboundOpRow> ops) {
    final failed = <String, String>{};
    for (final op in ops) {
      if (op.targetChannelId != widget.channelId) continue;
      final messageId = op.targetMessageId;
      if (messageId == null) continue;
      if (op.kind == OpKind.chatPayload) {
        failed[messageId] = op.opId;
        continue;
      }
      final what = switch (op.kind) {
        OpKind.messageEdit => 'Edit not applied',
        OpKind.messageDelete => "Couldn't delete that message",
        _ => "Couldn't react to that message",
      };
      if (!_reportedFailures.add(op.opId)) continue;
      unawaited(widget.chatService.dismissFailure(op.opId));
      _toast('$what — the server rejected it');
    }
    if (!mounted) return;
    if (failed.length == _failedOps.length &&
        failed.keys.every(_failedOps.containsKey)) {
      return;
    }
    setState(() => _failedOps = failed);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _retry(String opId) => widget.chatService.retryFailedOp(opId);

  // --- message actions (frame d3) ----------------------------------------

  /// §6a.3: recipients drop an UPDATE/DELETE that isn't from the
  /// author, so offering either on someone else's message would be a
  /// button that does nothing. An attachment is editable (its caption)
  /// once the server has it; before that it still points at a local
  /// file (editMessage).
  /// Decision 188: a placeholder for a message that would not decrypt,
  /// until its re-send arrives. Nothing to reply to, react to or copy.
  static bool _waiting(MessageRow msg) => msg.contentType == kUndecryptedType;

  bool _canEdit(MessageRow msg) =>
      _isMine(msg) &&
      !msg.tombstoned &&
      (msg.body ?? '').isNotEmpty &&
      !isRichType(msg.contentType) &&
      msg.contentType != kSecureType && // its body is its title
      (msg.attachments == null || msg.serverTimestampMs != null);

  bool _isMine(MessageRow msg) =>
      msg.authorUserId == widget.authService.currentUserId;

  /// Message info: our own message, once the server has it.
  bool _canInfo(MessageRow msg) =>
      _isMine(msg) &&
      !msg.tombstoned &&
      msg.serverTimestampMs != null &&
      msg.contentType != kGroupEventType;

  void _openInfo(MessageRow msg) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessageInfoScreen(
            chatService: widget.chatService,
            message: msg,
            group: widget.channelKind == 'group',
            nameOf: (id) => _memberNames[id] ?? 'Unknown',
          ),
        ),
      );

  /// Text worth copying: a body that is words, not a vCard / geo URI.
  bool _canCopy(MessageRow msg) =>
      !msg.tombstoned &&
      (msg.body ?? '').isNotEmpty &&
      !isRichType(msg.contentType) &&
      msg.contentType != kSecureType;

  /// Long-press: starts a selection, or adds/removes while one is open.
  void _select(MessageRow msg) {
    HapticFeedback.mediumImpact();
    // Otherwise the keyboard stays up over the actions; Edit and Reply
    // ask for it again. The search field may hold it too.
    FocusManager.instance.primaryFocus?.unfocus();
    _emojiOpen = false;
    _toggleSelected(msg);
  }

  void _toggleSelected(MessageRow msg) {
    setState(() {
      if (!_selectedIds.remove(msg.messageId)) {
        _selectedIds.add(msg.messageId);
      }
      if (_selectedIds.length == 1) _placeBar(_selectedIds.single);
    });
  }

  /// The reaction bar goes under the message when it's too close to the
  /// top of the list to fit above.
  void _placeBar(String messageId) {
    final box = _messageKeys[messageId]?.currentContext?.findRenderObject()
        as RenderBox?;
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    _barBelow = box != null &&
        list != null &&
        box.localToGlobal(Offset.zero).dy -
                list.localToGlobal(Offset.zero).dy <
            64;
  }

  void _clearSelection() {
    if (_selectedIds.isNotEmpty) setState(_selectedIds.clear);
  }

  void _reply(MessageRow msg) {
    setState(() {
      _selectedIds.clear();
      _replyTo = msg;
      _editingMessageId = null;
    });
    _inputFocus.requestFocus();
  }

  /// One message copies as its text; several as WhatsApp does, one
  /// "[date time] Name: text" line each, oldest first.
  void _copy(List<MessageRow> msgs) {
    _clearSelection();
    final String text;
    if (msgs.length == 1) {
      text = msgs.single.body ?? '';
    } else {
      final sorted = [...msgs]
        ..sort((a, b) => a.displayTimestampMs.compareTo(b.displayTimestampMs));
      final when = DateFormat.yMd().add_jm();
      text = [
        for (final m in sorted)
          '[${when.format(DateTime.fromMillisecondsSinceEpoch(m.displayTimestampMs))}] '
              '${_isMine(m) ? 'You' : (_memberNames[m.authorUserId] ?? widget.channelName)}: '
              '${m.body ?? ''}',
      ].join('\n');
    }
    Clipboard.setData(ClipboardData(text: text));
    _toast(msgs.length == 1 ? 'Copied' : '${msgs.length} messages copied');
  }

  /// The selection app bar: the count, and what can be done to every
  /// selected message (WhatsApp's contextual bar): Reply, Star, Delete
  /// and Forward as icons, Copy and Edit under the menu. Reply and Edit
  /// need exactly one.
  AppBar _selectionBar(List<MessageRow> sel) {
    final one = sel.length == 1 ? sel.single : null;
    // WhatsApp: Unstar only when every selected message is starred.
    final allStarred = sel.every((m) => m.starredAtMs != null);
    final more = <(String, VoidCallback)>[
      if (one != null && _canInfo(one))
        (
          'Info',
          () {
            _clearSelection();
            _openInfo(one);
          }
        ),
      if (sel.every(_canCopy)) ('Copy', () => _copy(sel)),
      if (one != null && _canEdit(one))
        (
          'Edit',
          () {
            _clearSelection();
            _startEdit(one);
          }
        ),
    ];
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel',
        onPressed: _clearSelection,
      ),
      title: Text('${sel.length}'),
      actions: [
        if (one != null && !one.tombstoned && !_waiting(one))
          IconButton(
            icon: const Icon(Icons.reply),
            tooltip: 'Reply',
            onPressed: () => _reply(one),
          ),
        if (sel.every((m) => !m.tombstoned && !_waiting(m)))
          IconButton(
            icon: Icon(allStarred ? Icons.star_border : Icons.star),
            tooltip: allStarred ? 'Unstar' : 'Star',
            onPressed: () {
              _clearSelection();
              widget.chatService.setStarred(
                  [for (final m in sel) m.messageId], !allStarred);
            },
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: () => _confirmDelete(sel),
        ),
        if (sel.every(ChatService.canForward))
          IconButton(
            icon: const Icon(Icons.shortcut),
            tooltip: 'Forward',
            onPressed: () => _forward(sel),
          ),
        if (more.isNotEmpty)
          PopupMenuButton<VoidCallback>(
            tooltip: 'More options',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              for (final (label, action) in more)
                PopupMenuItem(value: action, child: Text(label)),
            ],
          ),
      ],
    );
  }

  /// WhatsApp's forward: pick chats, send, and open the chat when there
  /// was just one (SYNC_PROTOCOL §25).
  Future<void> _forward(List<MessageRow> sel) async {
    final self = widget.authService.currentUserId;
    if (self == null) return;
    final many =
        sel.any((m) => ChatService.forwardCount(m) >= kForwardedManyTimes);
    final targets = await Navigator.of(context).push<List<ForwardTarget>>(
      MaterialPageRoute(
        builder: (_) => ForwardScreen(
          chatService: widget.chatService,
          selfUserId: self,
          limit: many ? 1 : ChatService.maxForwardChats,
        ),
      ),
    );
    if (targets == null || targets.isEmpty || !mounted) return;
    _clearSelection();
    await widget.chatService.forwardMessages(
      messages: sel,
      channelIds: [for (final t in targets) t.channelId],
      authorUserId: self,
    );
    if (!mounted) return;
    final only = targets.length == 1 ? targets.single : null;
    if (only == null || only.channelId == widget.channelId) {
      _toast('Forwarded');
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ChatScreen(
        channelId: only.channelId,
        channelName: only.title,
        channelKind: only.group ? 'group' : 'dm',
        chatService: widget.chatService,
        authService: widget.authService,
      ),
    ));
  }

  /// Decision 222: "Delete for me" for anything, "Delete for everyone"
  /// only when every selected message still qualifies.
  Future<void> _confirmDelete(List<MessageRow> sel) async {
    final self = widget.authService.currentUserId;
    final choice = await confirmDeleteMessages(
      context,
      count: sel.length,
      forEveryone:
          sel.every((m) => widget.chatService.canDeleteForEveryone(m, self)),
    );
    if (choice == null || !mounted) return;
    _clearSelection();
    if (choice == DeleteChoice.forEveryone) {
      await _deleteMessages(sel);
    } else {
      await widget.chatService.deleteForMe([for (final m in sel) m.messageId]);
    }
  }

  Future<void> _toggleReaction(MessageRow msg, String emoji) async {
    final userId = widget.authService.currentUserId;
    if (userId == null) return;
    final already = msg.reactions
        .any((r) => r.userId == userId && r.emoji == emoji);
    await widget.chatService.reactToMessage(
      channelId: widget.channelId,
      messageId: msg.messageId,
      userId: userId,
      emoji: emoji,
      add: !already,
    );
  }

  void _startEdit(MessageRow msg) {
    setState(() {
      _replyTo = null;
      _editingMessageId = msg.messageId;
    });
    _editingOriginal = msg.body ?? '';
    _input.text = _editingOriginal!;
    _input.selection =
        TextSelection.collapsed(offset: _input.text.length);
    _inputFocus.requestFocus();
  }

  void _cancelCompose() {
    setState(() {
      _editingMessageId = null;
      _replyTo = null;
    });
    _input.clear();
  }

  /// Decision 11: tombstone now, enqueue in [ChatScreen.undoWindow].
  /// One delete (of one or several messages) is pending at a time — a
  /// new one commits the last rather than racing it — and one Undo
  /// brings back everything it took.
  Future<void> _deleteMessages(List<MessageRow> msgs) async {
    await _flushPendingDelete();
    for (final m in msgs) {
      await widget.chatService.deleteMessage(
        messageId: m.messageId,
        undoWindow: widget.undoWindow,
      );
    }
    if (!mounted) return;
    final ids = [for (final m in msgs) m.messageId];
    _deletingMessageIds = ids;
    _deleteTimer = Timer(widget.undoWindow, () {
      final pending = _deletingMessageIds;
      _deletingMessageIds = const [];
      for (final id in pending) {
        unawaited(widget.chatService
            .commitDelete(channelId: widget.channelId, messageId: id));
      }
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      duration: widget.undoWindow,
      // A SnackBar with an action persists by default (Flutter 3.35+);
      // this one must leave when its window does.
      persist: false,
      content: Row(
        children: [
          _UndoCountdown(window: widget.undoWindow),
          const SizedBox(width: kSpaceSm),
          Expanded(
            child: Text(ids.length == 1
                ? 'Message deleted'
                : '${ids.length} messages deleted'),
          ),
        ],
      ),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () {
          _deleteTimer?.cancel();
          _deletingMessageIds = const [];
          for (final id in ids) {
            unawaited(widget.chatService.undoDelete(id));
          }
        },
      ),
    ));
  }

  /// Commit whatever delete is mid-window right now (a second delete, or
  /// leaving the screen). Idempotent — the store no-ops if Undo won.
  Future<void> _flushPendingDelete() async {
    _deleteTimer?.cancel();
    final pending = _deletingMessageIds;
    _deletingMessageIds = const [];
    for (final id in pending) {
      await widget.chatService
          .commitDelete(channelId: widget.channelId, messageId: id);
    }
  }

  /// Composer attach button (frame d1). One sheet: the camera, the
  /// gallery for photos and videos (photos we can size for the bubble),
  /// the system file picker for everything else (Audio is the same
  /// picker showing only audio), and the text-format kinds — contact,
  /// location, event (decision 133) — and the chat's albums (decision
  /// 233), once a 1:1 chat knows its other person.
  Future<void> _onAttach({String? preset}) async {
    final options = [
      (Icons.photo_camera_outlined, 'Camera', 'camera'),
      (Icons.image_outlined, 'Gallery', 'gallery'),
      (Icons.insert_drive_file_outlined, 'Document', 'file'),
      (Icons.headphones_outlined, 'Audio', 'audio'),
      (Icons.person_outline, 'Contact', 'contact'),
      (Icons.location_on_outlined, 'Location', 'location'),
      (Icons.event_outlined, 'Event', 'event'),
      if (widget.channelKind == 'group' || _peerUserId != null)
        (Icons.photo_library_outlined, 'Album', 'album'),
    ];
    final choice = preset ?? await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        // WhatsApp's compact sheet: four to a row, rows just taller
        // than their circle and label, the sheet as tall as they are.
        return SafeArea(
          child: GridView(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              // A circle, its label, a little air; more for a bigger font.
              mainAxisExtent: 72 + MediaQuery.textScalerOf(ctx).scale(20),
              mainAxisSpacing: kSpaceXs,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                kSpaceSm, kSpaceMd, kSpaceSm, kSpaceSm),
            children: [
              for (final (icon, label, value) in options)
                InkWell(
                  borderRadius: BorderRadius.circular(kRadiusMd),
                  onTap: () => Navigator.of(ctx).pop(value),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: scheme.primaryContainer,
                        child: Icon(icon, color: scheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: 6),
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    if (choice == 'contact') return _shareContact();
    if (choice == 'location') {
      return showLocationSheet(context,
          channelId: widget.channelId,
          sendCurrent: (p) => _sendRich(p.toUri(), kLocationType));
    }
    if (choice == 'event') return _shareEvent();
    if (choice == 'album') return _albumChoice();

    String? sourcePath;
    // Camera and gallery media: a photo is sized here (HD or not), a video
    // gets a thumbnail. A file picked as a file goes byte for byte.
    final media = choice != 'file' && choice != 'audio';
    try {
      if (media) {
        // The original: the preview's HD choice sizes it (decision 130).
        final picker = ImagePicker();
        final picked = choice == 'camera'
            ? await picker.pickImage(source: ImageSource.camera)
            : await picker.pickMedia();
        if (picked == null) return;
        sourcePath = picked.path;
      } else {
        final picked = await FilePicker.pickFile(
          type: choice == 'audio' ? FileType.audio : FileType.any,
        );
        sourcePath = picked?.path;
        if (sourcePath == null) return;
      }
    } on PlatformException catch (e) {
      _toast('Could not open the picker: ${e.code}');
      return;
    }

    if (!mounted) return;
    final mime = mimeForPath(sourcePath);
    final photo = media && mime.startsWith('image/') && mime != 'image/gif';
    final sent = await Navigator.of(context).push<AttachmentChoice>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            AttachmentPreviewScreen(path: sourcePath!, offerHd: photo),
      ),
    );
    if (sent == null || !mounted) return;

    final userId = widget.authService.currentUserId;
    if (userId == null) return;
    setState(() => _sending = true);
    try {
      final file = await prepareAttachment(
          widget.chatService.assets, sourcePath,
          media: media, hd: sent.hd);
      await widget.chatService.sendAttachment(
        channelId: widget.channelId,
        authorUserId: userId,
        path: file.path,
        caption: sent.caption.isEmpty ? null : sent.caption,
        replyToMessageId: _replyTo?.messageId,
        width: file.width,
        height: file.height,
        durationMs: file.durationMs,
        thumbnail: file.thumbnail,
      );
      _toBottom();
      if (mounted) setState(() => _replyTo = null);
    } on ArgumentError catch (e) {
      _toast('${e.message}');
    } catch (e) {
      _toast('Could not attach that file.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Send a contact, location or event: standard text in the body,
  /// the kind in `content_type` (decision 133).
  Future<void> _sendRich(String body, String contentType) async {
    final userId = widget.authService.currentUserId;
    if (userId == null) return;
    await widget.chatService.sendMessage(
      channelId: widget.channelId,
      body: body,
      authorUserId: userId,
      replyToMessageId: _replyTo?.messageId,
      contentType: contentType,
    );
    _toBottom();
    if (mounted) setState(() => _replyTo = null);
  }

  /// The system contact picker, then the picked card as a vCard (no
  /// photo — it would dwarf the message).
  Future<void> _shareContact() async {
    if (!await Permission.contacts.request().isGranted) {
      _toast('Vartalap needs contacts access to share a contact');
      return;
    }
    try {
      final contact = await FlutterContacts.native.showPicker(properties: {
        ContactProperty.name,
        ContactProperty.phone,
        ContactProperty.email,
      });
      if (contact == null) return;
      await _sendRich(FlutterContacts.vCard.export(contact), kContactType);
    } on PlatformException catch (e) {
      _toast('Could not open contacts: ${e.code}');
    }
  }

  Future<void> _shareEvent() async {
    final event = await Navigator.of(context).push<EventInfo>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const EventComposerScreen(),
      ),
    );
    if (event == null) return;
    final now = DateTime.now();
    await _sendRich(
      event.toIcs(uid: '${now.microsecondsSinceEpoch}@vartalap', stamp: now),
      kEventType,
    );
  }

  /// "Message" on a shared contact card: find which of its numbers is
  /// on Vartalap and open that chat.
  Future<void> _messageContact(String vcard) async {
    final userId = widget.authService.currentUserId;
    final contact = FlutterContacts.vCard.import(vcard).firstOrNull;
    if (userId == null || contact == null) return;
    final countryCode = '+${(await defaultCountry()).dialCode}';
    final phones = [
      for (final p in contact.phones)
        normalizePhoneNumber(p.number, countryCode: countryCode),
    ].whereType<String>().toList();
    final name = contactName(vcard);
    final ContactRow? user;
    try {
      user = await widget.chatService.findUserByPhone(phones, name: name);
    } catch (_) {
      _toast("Couldn't check right now. Try again later.");
      return;
    }
    if (!mounted) return;
    if (user == null) {
      _toast("$name isn't on Vartalap yet");
      return;
    }
    if (user.userId == userId) return;
    final channelId = await widget.chatService.startDirectMessage(
      localUserId: userId,
      peerUserId: user.userId,
      peerName: user.displayLabel,
    );
    if (!mounted || channelId == widget.channelId) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        channelId: channelId,
        channelName: user!.displayLabel,
        channelKind: 'dm',
        chatService: widget.chatService,
        authService: widget.authService,
      ),
    ));
  }

  /// One-line description for a reply quote or the reply bar.
  static String _preview(MessageRow m) => messagePreview(
        m.body ?? '',
        m.contentType,
        attachment: m.attachments != null,
      );

  /// The mic (the send button while there is nothing to send).
  /// ponytail: tap to start, then send or discard; hold-to-record with
  /// slide-to-cancel is a gesture on top of the same two calls.
  Future<void> _startRecording() async {
    setState(() => _sending = true);
    AudioRecorder? recorder;
    try {
      if (!await Permission.microphone.request().isGranted) {
        _toast('Allow the microphone to record voice messages.');
        return;
      }
      final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      // Straight into the durable dir: the upload may not run for hours.
      final path =
          '${(await widget.chatService.assets.dir).path}/voice-$stamp.m4a';
      recorder = AudioRecorder();
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: kVoiceNoteBitRate,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (_) {
      recorder?.dispose().ignore();
      _toast("Couldn't start recording.");
      return;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) {
      recorder.cancel().whenComplete(recorder.dispose).ignore();
      return;
    }
    _inputFocus.unfocus();
    setState(() {
      _recorder = recorder;
      _recordingSince = DateTime.now();
      _emojiOpen = false;
    });
    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (DateTime.now().difference(_recordingSince) >= _maxVoiceNote) {
        _stopRecording(send: true);
      } else {
        setState(() {});
      }
    });
  }

  /// Ends the recording: [send] sends it as a voice note (as a reply,
  /// if one is set up), otherwise the file is deleted.
  Future<void> _stopRecording({required bool send}) async {
    final recorder = _recorder;
    if (recorder == null) return;
    _recordingTicker?.cancel();
    // ponytail: wall-clock length, long by however long a phone call
    // paused the recorder; read it off the file if that ever shows.
    final duration = DateTime.now().difference(_recordingSince);
    setState(() {
      _recorder = null;
      _sending = send;
    });
    try {
      // Under a second is a mis-tap, not a message.
      if (!send || duration < const Duration(seconds: 1)) {
        await recorder.cancel();
        return;
      }
      final path = await recorder.stop();
      final userId = widget.authService.currentUserId;
      if (path == null || userId == null) return;
      await widget.chatService.sendAttachment(
        channelId: widget.channelId,
        authorUserId: userId,
        path: path,
        replyToMessageId: _replyTo?.messageId,
        durationMs: duration.inMilliseconds,
        voiceNote: true,
      );
      _toBottom();
      if (mounted) setState(() => _replyTo = null);
    } catch (_) {
      _toast("Couldn't send the voice message.");
    } finally {
      await recorder.dispose();
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _onSend() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    final options = _editingMessageId == null ? _options : kNoComposeOptions;
    if (_editingMessageId != null && body == _editingOriginal?.trim()) {
      _cancelCompose();
      return;
    }
    final userId = widget.authService.currentUserId;
    if (userId == null) return;
    setState(() => _sending = true);
    try {
      final editing = _editingMessageId;
      if (editing != null) {
        await widget.chatService.editMessage(
          channelId: widget.channelId,
          messageId: editing,
          newBody: body,
        );
      } else if (options.secure) {
        // A secret is sent as typed: no trimming.
        await widget.chatService.sendSecure(
          channelId: widget.channelId,
          secret: _input.text,
          authorUserId: userId,
          password: options.password,
          title: options.title,
          replyToMessageId: _replyTo?.messageId,
          timerSec: options.timerSec,
        );
        _toBottom();
        _options = kNoComposeOptions;
      } else {
        await widget.chatService.sendMessage(
          channelId: widget.channelId,
          body: body,
          authorUserId: userId,
          replyToMessageId: _replyTo?.messageId,
          timerSec: options.timerSec,
          linkPreview: _linkPreview.previewFor(body),
        );
        _toBottom();
        _options = kNoComposeOptions;
      }
      if (mounted) {
        setState(() {
          _editingMessageId = null;
          _replyTo = null;
        });
      }
      _input.clear();
      if (_typingNotified) {
        _typingNotified = false;
        _lastTypingHeartbeatMs = 0;
        _typingQuietTimer?.cancel();
        widget.chatService.notifyTyping(
          channelId: widget.channelId,
          isTyping: false,
        );
      }
    } on ArgumentError catch (e) {
      _toast('${e.message}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.authService.currentUserId ?? '';
    final scheme = Theme.of(context).colorScheme;
    // The bar is primary in light mode, surface in dark.
    final onBar =
        Theme.of(context).appBarTheme.foregroundColor ?? scheme.onSurface;
    final chatColors = VartalapTheme.chatColorsOf(context);

    // Rows that left the page (cleared history) drop out of it.
    final selected = _selectedIds.isEmpty
        ? const <MessageRow>[]
        : [
            for (final id in _selectedIds)
              ..._lastMessages.where((m) => m.messageId == id),
          ];
    // Back closes the selection, the emoji panel, then search, first,
    // like WhatsApp.
    return PopScope(
      canPop: selected.isEmpty && !_searchOpen && !_emojiOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selected.isNotEmpty) {
          _clearSelection();
        } else if (_emojiOpen) {
          setState(() => _emojiOpen = false);
        } else {
          _closeSearch();
        }
      },
      child: Scaffold(
      appBar: selected.isNotEmpty
          ? _selectionBar(selected)
          : _searchOpen ? _searchBar(onBar) : AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _openChatInfo,
          child: Row(
            children: [
              Avator(
                text: _title,
                seed: widget.channelId,
                avatarUrl: _channel?.avatarUrl,
                isGroup: widget.channelKind == 'group',
                width: kAvatarSm,
                height: kAvatarSm,
              ),
              const SizedBox(width: kSpaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.channelKind != 'group')
                      PresenceLine(
                        chatService: widget.chatService,
                        channelId: widget.channelId,
                        typing: _peerTypingTimers.isNotEmpty,
                        color: onBar.withValues(alpha: 0.85),
                      )
                    else if (_peerTypingTimers.isNotEmpty)
                      Text(
                        _peerTypingTimers.length == 1
                            ? 'typing…'
                            : 'several people are typing…',
                        style: TextStyle(
                          fontSize: 12,
                          color: onBar.withValues(alpha: 0.85),
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else if (_memberLine case final line?)
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: onBar.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Search lives in the menu, for a 1:1 chat and a group alike.
        actions: [
          PopupMenuButton<VoidCallback>(
            key: _menuKey,
            tooltip: 'More options',
            onCanceled: () => _menuMore = false,
            onSelected: (action) {
              _menuMore = false;
              action();
            },
            itemBuilder: (_) => [
              for (final (label, action) in _menuItems())
                PopupMenuItem(
                  value: action,
                  child: label == 'More'
                      ? const Row(children: [
                          Expanded(child: Text('More')),
                          Icon(Icons.arrow_right),
                        ])
                      : Text(label),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MessageRow>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? const [];
                _lastMessages = messages;
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }
                // Build a flat list of widgets: messages + date chips.
                // The list is reversed, so index 0 = newest.
                //
                // ponytail: reply quotes resolve against the loaded
                // page only, so a reply to a message older than the
                // window renders without its quote. Join
                // reply_to_message_id in fetchChannelMessages if that
                // ever looks broken rather than merely sparse.
                final bodyById = {
                  for (final m in messages)
                    if (!m.tombstoned) m.messageId: _preview(m),
                };
                final items = <Widget>[];
                for (int i = 0; i < messages.length; i++) {
                  final msg = messages[i];
                  final mine = msg.authorUserId == currentUserId;
                  final showTail = i == messages.length - 1 ||
                      messages[i + 1].authorUserId != msg.authorUserId ||
                      messages[i + 1].contentType == kGroupEventType;
                  final event = msg.contentType == kGroupEventType
                      ? GroupEvent.parse(msg.body)
                      : null;
                  if (event != null) {
                    items.add(_CenterChip(
                      key: _keyForMessage(msg.messageId),
                      text: groupEventText(
                        event,
                        actorUserId: msg.authorUserId,
                        selfUserId: currentUserId,
                        nameOf: (id) => _memberNames[id] ?? 'Unknown',
                      ),
                    ));
                  }

                  // Sender name appears above the first bubble of a
                  // same-author run, only for groups, only for peer
                  // messages. `showTail=true` already identifies "top
                  // of run" because the list is reverse-rendered.
                  final senderLabel =
                      (!mine && widget.channelKind == 'group' && showTail)
                          ? (_memberNames[msg.authorUserId] ?? 'Unknown')
                          : null;

                  final failedOpId = _failedOps[msg.messageId];
                  final isSelected = _selectedIds.contains(msg.messageId);
                  final selecting = _selectedIds.isNotEmpty;
                  final replyTo = msg.replyToMessageId;
                  if (event == null && msg.contentType != kGroupEventType) {
                  items.add(_SwipeToReply(
                    key: ValueKey('swipe-${msg.messageId}'),
                    onReply: msg.tombstoned || _waiting(msg) || selecting
                        ? null
                        : () => _reply(msg),
                    child: _MessageBubble(
                    key: _keyForMessage(msg.messageId),
                    message: msg,
                    isMine: mine,
                    showTail: showTail,
                    chatColors: chatColors,
                    highlighted: isSelected ||
                        _highlightedMessageId == msg.messageId,
                    link: isSelected && _selectedIds.length == 1
                        ? _selectedLink
                        : null,
                    senderLabel: senderLabel,
                    searchQuery: _searchQuery,
                    localUserId: currentUserId,
                    replyPreview:
                        replyTo == null ? null : bodyById[replyTo],
                    onReplyTap: replyTo == null || !bodyById.containsKey(replyTo)
                        ? null
                        : () => _jumpToMessage(replyTo),
                    onEditedTap: selecting
                        ? null
                        : () => showEditHistory(context,
                            widget.chatService.messageVersions(msg.messageId)),
                    onLongPress: () => _select(msg),
                    // While selecting, a tap adds or removes a message.
                    onTap: selecting ? () => _toggleSelected(msg) : null,
                    // Decision 222: a secure one opens from its card.
                    onReveal: msg.contentType == kSecureType && !msg.tombstoned
                        ? () => revealSecret(context, widget.chatService, msg)
                        : null,
                    // A long text opens in place; a search shows it whole.
                    onReadMore: _expanded.contains(msg.messageId) ||
                            _searchQuery.isNotEmpty
                        ? null
                        : () => setState(() => _expanded.add(msg.messageId)),
                    onReactionTap: (emoji) => _toggleReaction(msg, emoji),
                    onRetry:
                        failedOpId == null ? null : () => _retry(failedOpId),
                    onMessageContact: _messageContact,
                    // Only where we may still write (a group we left, a
                    // 1:1 chat not connected: the server would refuse).
                    onRsvp: !_canSend ||
                            _link?.connected == false ||
                            _link?.blocked == true
                        ? null
                        : (going) => widget.chatService.rsvp(
                              channelId: widget.channelId,
                              messageId: msg.messageId,
                              userId: currentUserId,
                              going: going,
                            ),
                    nameOf: (id) => id == currentUserId
                        ? 'You'
                        : _memberNames[id] ?? widget.channelName,
                  ),
                  ));
                  }

                  // Insert a date chip between this message and the
                  // next older one (i+1) if they fall on different days.
                  // Also insert one above the very oldest message.
                  final thisDate = DateTime.fromMillisecondsSinceEpoch(
                      msg.displayTimestampMs);
                  final bool needsDateChip;
                  if (i == messages.length - 1) {
                    needsDateChip = true; // oldest message
                  } else {
                    final olderDate = DateTime.fromMillisecondsSinceEpoch(
                        messages[i + 1].displayTimestampMs);
                    needsDateChip = thisDate.year != olderDate.year ||
                        thisDate.month != olderDate.month ||
                        thisDate.day != olderDate.day;
                  }
                  if (needsDateChip) {
                    items.add(_CenterChip(text: _formatDay(thisDate)));
                  }
                }

                final sel = selected.length == 1 ? selected.single : null;
                return Stack(
                  key: _listKey,
                  children: [
                    ListView(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: kSpaceSm),
                      children: items,
                    ),
                    // WhatsApp's reaction bar, pinned to the selected
                    // bubble's top edge (bottom edge near the list top)
                    // on the side the bubble sits.
                    if (sel != null && !sel.tombstoned && !_waiting(sel))
                      Positioned(
                        left: 0,
                        top: 0,
                        child: CompositedTransformFollower(
                          link: _selectedLink,
                          showWhenUnlinked: false,
                          targetAnchor: _barBelow
                              ? (_isMine(sel)
                                  ? Alignment.bottomRight
                                  : Alignment.bottomLeft)
                              : (_isMine(sel)
                                  ? Alignment.topRight
                                  : Alignment.topLeft),
                          followerAnchor: _barBelow
                              ? (_isMine(sel)
                                  ? Alignment.topRight
                                  : Alignment.topLeft)
                              : (_isMine(sel)
                                  ? Alignment.bottomRight
                                  : Alignment.bottomLeft),
                          offset: Offset(0, _barBelow ? 6 : -6),
                          child: _ReactionBar(
                            selected: sel.reactions
                                .where((r) => r.userId == currentUserId)
                                .map((r) => r.emoji)
                                .toSet(),
                            onPick: (emoji) {
                              _clearSelection();
                              _toggleReaction(sel, emoji);
                            },
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (!_canSend)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(kSpaceLg),
                child: Text(
                  "You can't send messages to this group because you're "
                  'no longer a member.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else if (_link case final link?
              when !link.connected || link.blocked)
            InviteBar(
              link: link,
              peerUserId: _peerUserId!,
              peerName: _title,
              chatService: widget.chatService,
              authService: widget.authService,
            )
          else ...[
          _MessageInput(
            controller: _input,
            focusNode: _inputFocus,
            emojiOpen: _emojiOpen,
            onEmoji: _toggleEmoji,
            // A tap on the field brings the keyboard back over the panel.
            onFieldTap: () {
              if (_emojiOpen) setState(() => _emojiOpen = false);
            },
            sending: _sending,
            onSend: _onSend,
            onAttach: _onAttach,
            onCamera: () => _onAttach(preset: 'camera'),
            onMic: _startRecording,
            recording: _recorder == null
                ? null
                : DateTime.now().difference(_recordingSince),
            onStopRecording: (send) => _stopRecording(send: send),
            editing: _editingMessageId != null,
            options: _options,
            onOptions: () async {
              final picked = await pickComposeOptions(context, _options);
              if (picked != null && mounted) {
                setState(() => _options = picked);
              }
            },
            onClearOptions: () =>
                setState(() => _options = kNoComposeOptions),
            linkPreview: ComposerLinkPreviewCard(controller: _linkPreview),
            replyPreview: _replyTo == null ? null : _preview(_replyTo!),
            onCancelCompose:
                (_editingMessageId != null || _replyTo != null)
                    ? _cancelCompose
                    : null,
          ),
          if (_emojiOpen) _emojiPanel(scheme),
          ],
        ],
      ),
    ),
    );
  }
}

/// The centred pill a day starts with ("Today"), and the one a group
/// event reads in ("Asha added you"), as in WhatsApp.
class _CenterChip extends StatelessWidget {
  final String text;
  const _CenterChip({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpaceXl,
          vertical: 6,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: kSpaceMd,
            vertical: kSpaceXs + 2,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(kRadiusMd),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(d.year, d.month, d.day);
  final diff = today.difference(target).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat.EEEE().format(d);
  if (d.year == now.year) return DateFormat.MMMd().format(d);
  return DateFormat.yMMMd().format(d);
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  /// Opens the attachment sheet (frame d1's paperclip).
  final VoidCallback onAttach;

  /// Straight to the camera, from the composer box.
  final VoidCallback onCamera;

  /// Starts a voice note. The send button is a mic while there is
  /// nothing to send.
  final VoidCallback onMic;

  /// How long the voice note has been recording, null when it isn't;
  /// the text row is then a recording bar.
  final Duration? recording;

  /// Ends the recording: true sends it, false discards it.
  final ValueChanged<bool> onStopRecording;

  /// Composer is in edit mode — the send button applies a
  /// MESSAGE_UPDATE to an existing message instead of sending a new one.
  final bool editing;

  /// Body of the message being replied to, if any.
  final String? replyPreview;

  /// Non-null while editing or replying; clears both.
  final VoidCallback? onCancelCompose;

  /// Decision 222: the next message's timer and secure options, the
  /// button that picks them and the ✕ that drops them.
  final ComposeOptions options;
  final VoidCallback onOptions;
  final VoidCallback onClearOptions;

  /// The smiley at the field's left end (a keyboard while the emoji
  /// panel is open), and a tap on the field itself.
  final bool emojiOpen;
  final VoidCallback onEmoji;
  final VoidCallback onFieldTap;

  /// The typed link's preview card (SYNC_PROTOCOL §27).
  final Widget? linkPreview;

  const _MessageInput({
    required this.controller,
    required this.focusNode,
    required this.emojiOpen,
    required this.onEmoji,
    required this.onFieldTap,
    required this.sending,
    required this.onSend,
    required this.onAttach,
    required this.onCamera,
    required this.onMic,
    required this.onStopRecording,
    this.recording,
    this.editing = false,
    this.replyPreview,
    this.onCancelCompose,
    required this.options,
    required this.onOptions,
    required this.onClearOptions,
    this.linkPreview,
  });

  /// Height of the box and of the round button beside it.
  static const double _height = 48;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    // WhatsApp's composer: one rounded box holding the reply/edit
    // preview, the text, the paperclip and the camera, and the round
    // send/mic button beside it at the same height.
    final box = recording != null
        ? Row(
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Discard',
                color: scheme.error,
                onPressed: () => onStopRecording(false),
              ),
              Icon(Icons.circle, size: 10, color: scheme.error),
              const SizedBox(width: kSpaceSm),
              Text(
                mmss(recording!),
                style: TextStyle(color: scheme.onSurface, fontSize: 16),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: kSpaceMd),
                child: Text('Recording…', style: TextStyle(color: muted)),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (editing || replyPreview != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: ColoredBox(
                      color: scheme.surface.withValues(alpha: 0.7),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Container(width: 4, color: scheme.primary),
                            const SizedBox(width: kSpaceSm + kSpaceXs),
                            Icon(
                              editing ? Icons.edit_outlined : Icons.reply,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: kSpaceSm),
                            Expanded(
                              child: Text(
                                editing
                                    ? 'Editing message'
                                    : (replyPreview!.isEmpty
                                        ? 'Message'
                                        : replyPreview!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: muted),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Cancel',
                              onPressed: onCancelCompose,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (options != kNoComposeOptions && !editing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 0, 0),
                  child: Row(
                    children: [
                      Icon(
                          options.secure
                              ? Icons.lock_outline
                              : Icons.timer_outlined,
                          size: 16,
                          color: scheme.primary),
                      const SizedBox(width: kSpaceSm),
                      Expanded(
                        child: GestureDetector(
                          onTap: onOptions,
                          child: Text(
                            composeOptionsText(options),
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Clear timer and secure',
                        onPressed: onClearOptions,
                      ),
                    ],
                  ),
                ),
              if (linkPreview != null) linkPreview!,
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(emojiOpen
                        ? Icons.keyboard_outlined
                        : Icons.emoji_emotions_outlined),
                    tooltip: emojiOpen ? 'Keyboard' : 'Emoji',
                    color: muted,
                    onPressed: onEmoji,
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onTap: onFieldTap,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        // The rounded box is the background; the
                        // theme's square fill would paint over it.
                        filled: false,
                        border: InputBorder.none,
                        isDense: true,
                        hintText: 'Message',
                        hintStyle: TextStyle(color: muted),
                        contentPadding:
                            const EdgeInsets.fromLTRB(0, 13, 0, 13),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Transform.rotate(
                      angle: -0.6,
                      child: const Icon(Icons.attach_file),
                    ),
                    tooltip: 'Attach',
                    color: muted,
                    onPressed: sending ? null : onAttach,
                  ),
                  // WhatsApp hides the camera once there's text; the
                  // message's timer and secure options take its place
                  // (decision 222).
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => editing
                        ? const SizedBox(width: kSpaceXs)
                        : value.text.isEmpty
                            ? IconButton(
                                icon: const Icon(Icons.photo_camera_outlined),
                                tooltip: 'Camera',
                                color: muted,
                                onPressed: sending ? null : onCamera,
                              )
                            : IconButton(
                                icon: const Icon(Icons.lock_clock_outlined),
                                tooltip: 'Timer and secure',
                                color: options != kNoComposeOptions
                                    ? scheme.primary
                                    : muted,
                                onPressed: sending ? null : onOptions,
                              ),
                  ),
                ],
              ),
            ],
          );

    // With the emoji panel open, the panel keeps clear of the system
    // navigation bar instead.
    return SafeArea(
      top: false,
      bottom: !emojiOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: _height),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(_height / 2),
                ),
                child: box,
              ),
            ),
            const SizedBox(width: 6),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final mic = recording == null &&
                    !editing &&
                    value.text.trim().isEmpty;
                return SizedBox.square(
                  dimension: _height,
                  child: Material(
                    color: scheme.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: sending
                          ? null
                          : recording != null
                              ? () => onStopRecording(true)
                              : mic
                                  ? onMic
                                  : onSend,
                      child: Center(
                        child: sending
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.onPrimary,
                                ),
                              )
                            : Icon(
                                editing
                                    ? Icons.check_rounded
                                    : mic
                                        ? Icons.mic
                                        : Icons.send_rounded,
                                semanticLabel:
                                    mic ? 'Record voice message' : null,
                                size: 22,
                                color: scheme.onPrimary,
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The six-emoji quick bar from frame d3. Tapping an emoji you already
/// used removes it (REACTION_REMOVE) — the sheet shows which those are.
class _ReactionBar extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onPick;

  const _ReactionBar({required this.selected, required this.onPick});

  static const List<String> emojis = [
    '\u{1F44D}',
    '\u{2764}\u{FE0F}',
    '\u{1F602}',
    '\u{1F62E}',
    '\u{1F622}',
    '\u{1F64F}',
  ];

  /// A floating pill over the long-pressed message (WhatsApp). Your
  /// own reactions are ringed; tapping one again removes it.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: scheme.surface,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in emojis)
              InkWell(
                key: ValueKey('react-$emoji'),
                customBorder: const CircleBorder(),
                onTap: () => onPick(emoji),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected.contains(emoji)
                        ? scheme.primaryContainer
                        : Colors.transparent,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// [CompositedTransformTarget] when there is a [link], else just [child].
class _LinkTarget extends StatelessWidget {
  final LayerLink? link;
  final Widget child;

  const _LinkTarget({required this.link, required this.child});

  @override
  Widget build(BuildContext context) {
    final l = link;
    return l == null
        ? child
        : CompositedTransformTarget(link: l, child: child);
  }
}

/// Drag a message right to reply (WhatsApp): the row follows the finger
/// up to [_max], a reply icon fades in behind it, a tick of haptics
/// marks [_trigger], and letting go past it replies.
class _SwipeToReply extends StatefulWidget {
  /// Null = not swipeable (a deleted message).
  final VoidCallback? onReply;
  final Widget child;

  const _SwipeToReply({super.key, required this.onReply, required this.child});

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const double _trigger = 56;
  static const double _max = 80;

  late final AnimationController _offset = AnimationController(
    vsync: this,
    upperBound: _max,
    duration: const Duration(milliseconds: 180),
  );
  bool _armed = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails d) {
    // Heavier the further it goes, like WhatsApp's rubber band.
    final resistance = 1 - _offset.value / (_max * 1.5);
    _offset.value = _offset.value + d.delta.dx * resistance;
    final armed = _offset.value >= _trigger;
    if (armed && !_armed) HapticFeedback.lightImpact();
    _armed = armed;
  }

  void _release([DragEndDetails? _]) {
    if (_armed) widget.onReply?.call();
    _armed = false;
    _offset.animateBack(0, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onHorizontalDragUpdate: _drag,
      onHorizontalDragEnd: _release,
      onHorizontalDragCancel: _release,
      child: AnimatedBuilder(
        animation: _offset,
        child: widget.child,
        builder: (context, child) {
          final progress = (_offset.value / _trigger).clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned(
                left: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: 0.5 + 0.5 * progress,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.reply,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(_offset.value, 0),
                child: child,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The snackbar's countdown ring (frame d3) — the only job of this
/// widget is to make the undo window visibly finite. The commit timer
/// itself lives on the screen state, so dismissing the snackbar early
/// doesn't cancel the delete.
class _UndoCountdown extends StatefulWidget {
  final Duration window;
  const _UndoCountdown({required this.window});

  @override
  State<_UndoCountdown> createState() => _UndoCountdownState();
}

class _UndoCountdownState extends State<_UndoCountdown> {
  late int _left = widget.window.inSeconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = _left > 0 ? _left - 1 : 0);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.window.inSeconds;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: total == 0 ? 0 : _left / total,
            strokeWidth: 2,
          ),
          Text('$_left', style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

/// [text] with every case-insensitive [query] in it marked, as
/// WhatsApp's in-chat search marks its hits.
InlineSpan _marked(String text, String query) {
  if (query.isEmpty) return TextSpan(text: text);
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in RegExp(RegExp.escape(query), caseSensitive: false)
      .allMatches(text)) {
    spans
      ..add(TextSpan(text: text.substring(at, m.start)))
      ..add(TextSpan(text: m[0], style: _matchStyle));
    at = m.end;
  }
  spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(children: spans);
}

/// Dark text on amber reads the same on either theme's bubbles.
const _matchStyle =
    TextStyle(color: Colors.black87, backgroundColor: Color(0xFFFFE082));

/// WhatsApp's words for a message that has not decrypted yet.
const _waitingText = 'Waiting for this message. This may take a while.';

/// A text longer than this (UTF-16 units) shows only its start, with
/// "Read more"; the start ends at a word near [_readMoreShown]
/// characters.
const _readMoreOver = 700;
const _readMoreShown = 500;

String _readMoreCut(String body) {
  final start = body.characters.take(_readMoreShown).toString();
  final space = start.lastIndexOf(RegExp(r'\s'));
  return (space > _readMoreShown * 0.8 ? start.substring(0, space) : start)
      .trimRight()
      // "the end…", not "the end.…"
      .replaceFirst(RegExp(r'[.,;:!?…]+$'), '');
}

class _MessageBubble extends StatelessWidget {
  final MessageRow message;
  final bool isMine;
  final bool showTail;
  final ChatColors chatColors;
  final bool highlighted;
  final String? senderLabel;
  final String localUserId;

  /// The in-chat search's query, marked wherever the body has it.
  final String searchQuery;

  /// Body of the message this one replies to, when it is inside the
  /// loaded page. Null means "no reply, or too far back".
  final String? replyPreview;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;

  /// Non-null when this message's outbound op is in a terminal failure
  /// state — renders the frame d1 red bubble with inline Retry.
  final VoidCallback? onRetry;

  /// "Message" on a shared contact card (its vCard).
  final ValueChanged<String>? onMessageContact;

  /// Set on the selected bubble: the reaction bar follows it.
  final LayerLink? link;

  /// A tap on the bubble itself (letting go of a selection).
  final VoidCallback? onTap;

  /// Opens a secure message (its card's View).
  final VoidCallback? onReveal;

  /// Set while a long text may be cut short; "Read more" calls it.
  final VoidCallback? onReadMore;

  /// Tapping the reply quote jumps to the message it quotes.
  final VoidCallback? onReplyTap;

  /// Tapping "edited" opens the earlier versions (decision 222).
  final VoidCallback? onEditedTap;

  /// An event's Going / Not going (decision 134), and whose names its
  /// answers carry.
  final ValueChanged<bool>? onRsvp;
  final String Function(String userId)? nameOf;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.showTail,
    required this.chatColors,
    required this.localUserId,
    required this.onLongPress,
    required this.onReactionTap,
    this.highlighted = false,
    this.senderLabel,
    this.searchQuery = '',
    this.replyPreview,
    this.onRetry,
    this.onMessageContact,
    this.link,
    this.onTap,
    this.onReveal,
    this.onReadMore,
    this.onReplyTap,
    this.onEditedTap,
    this.onRsvp,
    this.nameOf,
  });

  /// `messages.attachments` is a ChatPayload holding only the repeated
  /// Attachment field, exactly as InboundReceiver wrote it.
  List<pb.Attachment> get _attachments {
    final bytes = message.attachments;
    if (bytes == null || bytes.isEmpty) return const [];
    try {
      return pb.ChatPayload.fromBuffer(bytes).attachments;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = onRetry != null;
    final tombstoned = message.tombstoned;
    final waiting = message.contentType == kUndecryptedType;
    // Decision 222: a card saying how it opens, never the secret.
    final secure = !tombstoned && message.contentType == kSecureType;
    // A contact / location / event renders as a card, never its body.
    final rich = !tombstoned && isRichType(message.contentType);

    final bg = failed
        ? scheme.errorContainer
        : (isMine ? chatColors.senderBubble : chatColors.receiverBubble);
    final fg = failed
        ? scheme.onErrorContainer
        : (isMine ? chatColors.senderText : chatColors.receiverText);
    final timestampColor = failed
        ? scheme.onErrorContainer.withValues(alpha: 0.7)
        : (isMine
            ? chatColors.senderText.withValues(alpha: 0.6)
            : chatColors.messageTimestamp);

    // The phone's 12/24-hour setting, same as the chat list.
    final timeStr = TimeOfDay.fromDateTime(
      DateTime.fromMillisecondsSinceEpoch(message.displayTimestampMs),
    ).format(context);

    final starred = message.starredAtMs != null && !tombstoned;
    final timed = message.timerSec != null && !tombstoned;
    final forwards = ChatService.forwardCount(message);

    // Time + tick (+ "edited", + star); white when it sits on a photo.
    Widget metaIn(Color color) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isEdited && !tombstoned) ...[
              GestureDetector(
                onTap: onEditedTap,
                child: Text(
                  'edited',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (starred) ...[
              Icon(Icons.star,
                  size: 12, color: color, semanticLabel: 'Starred'),
              const SizedBox(width: 3),
            ],
            if (timed) ...[
              Icon(Icons.timer_outlined,
                  size: 12, color: color, semanticLabel: 'Timed message'),
              const SizedBox(width: 3),
            ],
            Text(timeStr, style: TextStyle(fontSize: 11, color: color)),
            if (isMine && !tombstoned) ...[
              const SizedBox(width: 3),
              _stateIcon(message.state, color),
            ],
          ],
        );
    final meta = metaIn(timestampColor);

    final attachments = tombstoned ? const <pb.Attachment>[] : _attachments;
    final body = message.body ?? '';
    // Photos, files, voice notes and cards sit in a tight frame, and
    // without a caption they carry the time themselves (WhatsApp): on
    // the photo, beside the voice note's length, above a card's buttons.
    final media = attachments.isNotEmpty || rich || secure;
    final selfTimed = media && (rich || secure || body.isEmpty);
    // WhatsApp cuts a very long text short, "Read more" at its end.
    final cut = onReadMore != null && body.length > _readMoreOver
        ? _readMoreCut(body)
        : null;
    Widget pad(Widget child) => media
        ? Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
            child: child,
          )
        : child;

    // The time tucks in after the last line of text: a transparent copy
    // of its text (plus the tick's width) holds its place in the
    // paragraph, so it drops to a line of its own only when the last
    // line is full. Screen readers get the body alone.
    final metaSpace = TextSpan(
      style: const TextStyle(fontSize: 11, color: Colors.transparent),
      children: [
        const WidgetSpan(child: SizedBox(width: 8)),
        if (message.isEdited && !tombstoned) ...[
          const TextSpan(
            text: 'edited',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
          const WidgetSpan(child: SizedBox(width: 4)),
        ],
        if (starred) const WidgetSpan(child: SizedBox(width: 15)),
        if (timed) const WidgetSpan(child: SizedBox(width: 15)),
        TextSpan(text: timeStr),
        if (isMine && !tombstoned) const WidgetSpan(child: SizedBox(width: 18)),
      ],
    );
    Widget withMeta(InlineSpan content, String spoken) => Stack(
          children: [
            Text.rich(
              TextSpan(children: [content, metaSpace]),
              semanticsLabel: spoken,
              style: TextStyle(color: fg, fontSize: 16, height: 1.35),
            ),
            Positioned(right: 0, bottom: 1, child: meta),
          ],
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      color: highlighted
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      // WhatsApp's rhythm: 2 px between one sender's bubbles, 8 px
      // when the sender changes.
      padding: EdgeInsets.only(
        top: showTail ? 7 : 1,
        bottom: 1,
        // The list has no side padding, so a highlight runs edge to
        // edge; the 8 px gutter lives here instead.
        left: isMine ? 72 : 8,
        right: isMine ? 8 : 72,
      ),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
        _LinkTarget(
          link: link,
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onLongPress,
          onTap: onTap,
          // While selecting, a tap anywhere toggles the message — the
          // photo, card buttons and play button inside sit it out.
          child: IgnorePointer(
          ignoring: onTap != null,
          child: PhysicalShape(
          clipper: _BubbleClipper(isMine: isMine, showTail: showTail),
          color: bg,
          elevation: 0.5,
          shadowColor: Colors.black26,
          child: Padding(
            // The tail is drawn outside the box, so both sides match.
            padding: media
                ? const EdgeInsets.all(4)
                : const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.68,
              ),
              // A media bubble is the media's width and its caption wraps
              // inside it (WhatsApp); a text bubble is as wide as its
              // text. Either way every piece shares one width, so the
              // time can sit flush right.
              child: _BubbleWidth(
              media: media,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (senderLabel != null)
                    pad(Text(
                      senderLabel!,
                      style: TextStyle(
                        color: _senderColor(senderLabel!),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    )),
                  if (forwards > 0 && !tombstoned)
                    pad(_ForwardedLabel(
                      many: forwards >= kForwardedManyTimes,
                      tint: fg,
                    )),
                  if (replyPreview != null && !tombstoned) ...[
                    _ReplyQuote(
                      text: replyPreview!,
                      tint: fg,
                      onTap: onReplyTap,
                    ),
                    const SizedBox(height: 4),
                  ],
                  for (final (i, a) in attachments.indexed)
                    _AttachmentView(
                      attachment: a,
                      tint: fg,
                      voiceNote: message.contentType == kVoiceNoteType,
                      // Its own, still going up (SYNC_PROTOCOL §25.4).
                      uploading: isMine &&
                          !failed &&
                          message.serverTimestampMs == null &&
                          a.url.startsWith('/'),
                      footer: selfTimed && i == attachments.length - 1
                          ? (onPhoto) =>
                              metaIn(onPhoto ? Colors.white : timestampColor)
                          : null,
                    ),
                  if (rich)
                    RichMessageView(
                      contentType: message.contentType!,
                      body: body,
                      tint: fg,
                      footer: meta,
                      onMessage: onMessageContact,
                      messageId: message.messageId,
                      mine: isMine,
                      rsvps: message.rsvps,
                      selfUserId: localUserId,
                      onRsvp: onRsvp,
                      nameOf: nameOf,
                    ),
                  if (secure)
                    _SecureCard(
                      title: body,
                      unlock: ChatService.secureUnlock(message),
                      tint: fg,
                      footer: meta,
                      onView: onReveal,
                    ),
                  if (bubbleLinkPreview(message) case final preview?
                      when !media)
                    LinkPreviewCard(preview: preview, tint: fg),
                  if (!selfTimed)
                    pad(withMeta(
                      tombstoned
                          ? TextSpan(
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.6),
                                fontSize: 15,
                                fontStyle: FontStyle.italic,
                              ),
                              children: [
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Icon(Icons.block,
                                      size: 14,
                                      color: fg.withValues(alpha: 0.6)),
                                ),
                                const TextSpan(
                                    text: ' This message was deleted'),
                              ],
                            )
                          : waiting
                              ? TextSpan(
                                  style: TextStyle(
                                    color: fg.withValues(alpha: 0.6),
                                    fontSize: 15,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  children: [
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Icon(Icons.schedule,
                                          size: 14,
                                          color: fg.withValues(alpha: 0.6)),
                                    ),
                                    const TextSpan(text: ' $_waitingText'),
                                  ],
                                )
                              : cut != null
                                  ? TextSpan(children: [
                                      _marked(cut, searchQuery),
                                      const TextSpan(text: '… '),
                                      WidgetSpan(
                                        alignment: PlaceholderAlignment.baseline,
                                        baseline: TextBaseline.alphabetic,
                                        child: GestureDetector(
                                          onTap: onReadMore,
                                          child: Text(
                                            'Read more',
                                            style: TextStyle(
                                              color: chatColors.linkText,
                                              fontSize: 16,
                                              height: 1.35,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ])
                                  : _marked(body, searchQuery),
                      // A screen reader gets a long text whole.
                      tombstoned
                          ? 'This message was deleted'
                          : waiting
                              ? _waitingText
                              : body,
                    )),
                  if (failed)
                    pad(Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Not sent',
                            style: TextStyle(fontSize: 11, color: fg),
                          ),
                          const SizedBox(width: kSpaceSm),
                          InkWell(
                            onTap: onRetry,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh, size: 14, color: fg),
                                const SizedBox(width: 2),
                                Text(
                                  'Retry',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: fg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                ],
              ),
              ),
            ),
          ),
        ),
        ),
        ),
        ),
        if (message.reactions.isNotEmpty && !tombstoned)
          _ReactionChips(
            reactions: message.reactions,
            localUserId: localUserId,
            onTap: onReactionTap,
          ),
          ],
        ),
      ),
    );
  }

  /// Stable hashed color for a sender's name label. Picks one of a
  /// small palette so the same author always gets the same tint within
  /// a conversation, while different authors are visually distinct.
  Color _senderColor(String label) {
    const palette = <Color>[
      Color(0xFFE53935), // red
      Color(0xFF8E24AA), // purple
      Color(0xFF1E88E5), // blue
      Color(0xFF00897B), // teal
      Color(0xFFEF6C00), // orange
      Color(0xFF6D4C41), // brown
      Color(0xFF546E7A), // blue-grey
      Color(0xFFD81B60), // pink
    ];
    var hash = 0;
    for (final code in label.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  /// Single tick = sent, double tick = delivered, blue double tick = read,
  /// clock = pending/sending, error = rejected.
  Widget _stateIcon(MessageState state, Color defaultColor) {
    switch (state) {
      case MessageState.pending:
      case MessageState.sending:
        return Icon(Icons.access_time, size: 15, color: defaultColor);
      case MessageState.sent:
        return Icon(Icons.check, size: 15, color: defaultColor);
      case MessageState.delivered:
        return Icon(Icons.done_all, size: 15, color: defaultColor);
      case MessageState.read:
        return const Icon(Icons.done_all, size: 15, color: Color(0xFF53BDEB));
      case MessageState.rejected:
        return Icon(Icons.error_outline, size: 15, color: Colors.red[300]);
    }
  }
}

/// "Forwarded" at the top of a forwarded bubble, "Forwarded many times"
/// from [kForwardedManyTimes] forwards (SYNC_PROTOCOL §25).
class _ForwardedLabel extends StatelessWidget {
  final bool many;
  final Color tint;

  const _ForwardedLabel({required this.many, required this.tint});

  @override
  Widget build(BuildContext context) {
    final color = tint.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(many ? Icons.fast_forward : Icons.shortcut,
              size: 14, color: color),
          const SizedBox(width: 3),
          Text(
            many ? 'Forwarded many times' : 'Forwarded',
            style: TextStyle(
                fontSize: 12.5, fontStyle: FontStyle.italic, color: color),
          ),
        ],
      ),
    );
  }
}

/// A secure message (decision 222): a card that plainly opens on a tap
/// and says how, never the secret. The secret shows in a dialog, so
/// closing it leaves this card as it was.
class _SecureCard extends StatelessWidget {
  /// What the sender called it; '' for none (SYNC_PROTOCOL §20.4).
  final String title;
  final SecureUnlock? unlock;
  final Color tint;

  /// The bubble's time + tick, above the View button.
  final Widget footer;
  final VoidCallback? onView;

  const _SecureCard({
    required this.title,
    required this.unlock,
    required this.tint,
    required this.footer,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    // The shape of rich_messages.dart's cards (location, album).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onView,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.lock_outline, color: tint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title.isEmpty ? 'Secure message' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tint,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        switch (unlock) {
                          SecureUnlock.screenLock =>
                            'Unlock with your phone lock',
                          SecureUnlock.password => 'Enter the password',
                          null => 'Update Vartalap to open it',
                        },
                        style: TextStyle(
                          color: tint.withValues(alpha: 0.75),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 6, 4),
          child: Align(alignment: Alignment.centerRight, child: footer),
        ),
        Divider(height: 1, thickness: 1, color: tint.withValues(alpha: 0.15)),
        TextButton(
          onPressed: onView,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
            minimumSize: const Size.fromHeight(40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const RoundedRectangleBorder(),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          child: const Text('View'),
        ),
      ],
    );
  }
}

/// Media bubbles are [_AttachmentView.width] wide (or the bubble's max,
/// if less); text bubbles take their text's width.
class _BubbleWidth extends StatelessWidget {
  final bool media;
  final Widget child;

  const _BubbleWidth({required this.media, required this.child});

  @override
  Widget build(BuildContext context) => media
      ? SizedBox(width: _AttachmentView.width, child: child)
      : IntrinsicWidth(child: child);
}

/// Clips the bubble shape. Without a tail it's a plain rounded rect.
/// With a tail it draws a small curved nub at the top corner (right
/// for sender, left for receiver) using cubic bezier for a smooth
/// WhatsApp-like shape.
class _BubbleClipper extends CustomClipper<Path> {
  final bool isMine;
  final bool showTail;

  _BubbleClipper({required this.isMine, required this.showTail});

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    const r = 18.0;

    if (!showTail) {
      return Path()
        ..addRRect(RRect.fromLTRBR(0, 0, w, h, const Radius.circular(r)));
    }

    final path = Path();

    if (isMine) {
      // Tail on top-right.
      path.moveTo(r, 0);
      path.lineTo(w, 0);
      // Tail: small curved nub extending right from the top-right.
      path.cubicTo(w, 0, w + 6, 0, w + 6, 8);
      path.cubicTo(w + 6, 10, w, 6, w, r);
      // Right edge down.
      path.lineTo(w, h - r);
      // Bottom-right corner.
      path.quadraticBezierTo(w, h, w - r, h);
      // Bottom edge.
      path.lineTo(r, h);
      // Bottom-left corner.
      path.quadraticBezierTo(0, h, 0, h - r);
      // Left edge up.
      path.lineTo(0, r);
      // Top-left corner.
      path.quadraticBezierTo(0, 0, r, 0);
    } else {
      // Tail on top-left.
      path.moveTo(0, 0);
      // Tail: small curved nub extending left from the top-left.
      path.cubicTo(0, 0, -6, 0, -6, 8);
      path.cubicTo(-6, 10, 0, 6, 0, r);
      // Left edge down.
      path.lineTo(0, h - r);
      // Bottom-left corner.
      path.quadraticBezierTo(0, h, r, h);
      // Bottom edge.
      path.lineTo(w - r, h);
      // Bottom-right corner.
      path.quadraticBezierTo(w, h, w, h - r);
      // Right edge up.
      path.lineTo(w, r);
      // Top-right corner.
      path.quadraticBezierTo(w, 0, w - r, 0);
      // Top edge back to start.
      path.lineTo(0, 0);
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(_BubbleClipper old) =>
      old.isMine != isMine || old.showTail != showTail;
}

/// The quoted strip above a reply's own text. `reply_to_message_id`
/// already exists on the wire (docs/proto/v3-chat-payload.proto) and in
/// the schema, so a reply is an ordinary MESSAGE_CREATE that names its
/// parent — nothing new goes on the wire for it.
class _ReplyQuote extends StatelessWidget {
  final String text;
  final Color tint;
  final VoidCallback? onTap;

  const _ReplyQuote({required this.text, required this.tint, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: kSpaceSm,
        vertical: kSpaceXs,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border(left: BorderSide(color: tint.withValues(alpha: 0.5), width: 3)),
      ),
      child: Text(
        text.isEmpty ? 'Message' : text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: tint.withValues(alpha: 0.8)),
      ),
    ),
    );
  }
}

/// One attachment on a bubble. An image renders inline and opens
/// full-screen on tap; audio plays inline, as a voice note or an audio
/// file; anything else is a document box that opens on tap. `attachment.url` is a local path
/// while our own upload is still in flight and a media-ms fileId
/// afterwards — [AssetCache] resolves both.
class _AttachmentView extends StatelessWidget {
  final pb.Attachment attachment;
  final Color tint;

  /// Recorded in the app ([kVoiceNoteType]) rather than a sent file.
  final bool voiceNote;

  /// The bubble's time + tick when there is no caption to carry it;
  /// `onPhoto` asks for the white version that sits on an image.
  final Widget Function(bool onPhoto)? footer;

  /// Our own file on its way up: how far, over it.
  final bool uploading;

  const _AttachmentView({
    required this.attachment,
    required this.tint,
    this.voiceNote = false,
    this.footer,
    this.uploading = false,
  });

  /// Media width; the bubble is this plus its 4 px frame.
  static const double width = 240;

  bool get _isImage => attachment.mimeType.startsWith('image/');

  String get _name =>
      attachment.filename.isEmpty ? 'Attachment' : attachment.filename;

  Future<void> _openFile(BuildContext context) async {
    if (attachment.mimeType.startsWith('video/')) {
      return showVideoPlayer(context, attachment);
    }
    final messenger = ScaffoldMessenger.of(context);
    final cache = AssetCache.instance;
    if (cache == null) return;
    final ok = await openAttachment(
      cache,
      uri: attachment.url,
      name: _name,
      mime: attachment.mimeType,
    );
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't open $_name")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (attachment.mimeType.startsWith('audio/')) {
      return VoiceNoteView(
        attachment: attachment,
        tint: tint,
        audioFile: !voiceNote,
        footer: footer?.call(false),
      );
    }
    // A video with its thumbnail (SYNC_PROTOCOL §25.4) looks like a photo
    // with a play button, and opens in the app's player.
    final video = attachment.mimeType.startsWith('video/') &&
        attachment.thumbnail.isNotEmpty;
    if (!_isImage && !video) return _document(context);

    // Reserve the sender-declared aspect ratio where we have one so the
    // bubble doesn't jump when the bytes land.
    final w = attachment.width;
    final h = attachment.height;
    final image = video
        ? Image.memory(
            Uint8List.fromList(attachment.thumbnail),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => AssetImagePlaceholder(tint: tint),
          )
        : AssetImageView(
            uri: attachment.url,
            fit: BoxFit.cover,
            placeholder: AssetImagePlaceholder(tint: tint),
            fallback: AssetImagePlaceholder(
              tint: tint,
              icon: Icons.broken_image_outlined,
            ),
          );
    final time = footer;
    final length = Duration(milliseconds: attachment.durationMs);
    return GestureDetector(
      onTap: video
          ? () => _openFile(context)
          : () => showAssetViewer(
                context,
                uri: attachment.url,
                title:
                    attachment.filename.isEmpty ? null : attachment.filename,
              ),
      child: ClipRRect(
        // The bubble's 18 px corner less its 4 px frame.
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: double.infinity,
          child: Stack(
            children: [
              // Tall shots are cropped to a sensible height (WhatsApp).
              SizedBox(
                height: (w > 0 && h > 0) ? math.min(width * h / w, 320) : 160,
                width: double.infinity,
                child: image,
              ),
              if (uploading)
                Positioned.fill(
                    child: Center(child: _UploadRing(attachment.url)))
              else if (video)
                const Positioned.fill(
                  child: Center(
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.black45,
                      child: Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 32,
                          semanticLabel: 'Play video'),
                    ),
                  ),
                ),
              if (video && length > Duration.zero)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(mmss(length),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ),
                  ),
                ),
              if (time != null)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: time(true),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// WhatsApp's document box: type glyph, name, size and extension.
  Widget _document(BuildContext context) {
    final isVideo = attachment.mimeType.startsWith('video/');
    final details = [
      humanFileSize(attachment.sizeBytes.toInt()),
      if (_name.contains('.')) extForPath(_name).toUpperCase(),
    ].where((s) => s.isNotEmpty).join(' · ');
    final time = footer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          child: Material(
            color: tint.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openFile(context),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: uploading
                          ? _UploadRing(attachment.url, small: true)
                          : Icon(
                              isVideo
                                  ? Icons.play_arrow_rounded
                                  : Icons.description_outlined,
                              color: tint,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tint,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              details,
                              style: TextStyle(
                                color: tint.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (time != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
            child: Align(alignment: Alignment.centerRight, child: time(false)),
          ),
      ],
    );
  }
}

/// How far our own file has gone up (SYNC_PROTOCOL §25.4): a ring that
/// fills, spinning while it is queued or being sealed.
class _UploadRing extends StatelessWidget {
  /// The local path the bubble shows until the upload lands.
  final String path;
  final bool small;

  const _UploadRing(this.path, {this.small = false});

  @override
  Widget build(BuildContext context) {
    final uploads = AssetCache.instance?.uploads;
    Widget ring(double? done) => Container(
          width: small ? 40 : 48,
          height: small ? 40 : 48,
          padding: EdgeInsets.all(small ? 8 : 10),
          decoration: const BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: CircularProgressIndicator(
            value: done,
            strokeWidth: 3,
            color: Colors.white,
            semanticsLabel: 'Sending',
          ),
        );
    return uploads == null
        ? ring(null)
        : ValueListenableBuilder<Map<String, double>>(
            valueListenable: uploads,
            builder: (_, value, __) => ring(value[path]),
          );
  }
}

/// Reaction chips under a bubble (frame d2's `👍 4`). Tapping one
/// toggles the local user's own reaction for that emoji.
class _ReactionChips extends StatelessWidget {
  final List<MessageReaction> reactions;
  final String localUserId;
  final ValueChanged<String> onTap;

  const _ReactionChips({
    required this.reactions,
    required this.localUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    final mine = <String>{};
    for (final r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
      if (r.userId == localUserId) mine.add(r.emoji);
    }
    // Tucked onto the bubble's bottom edge with a ring, like WhatsApp.
    return Transform.translate(
      offset: const Offset(0, -6),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Wrap(
        spacing: kSpaceXs,
        children: [
          for (final entry in counts.entries)
            InkWell(
              key: ValueKey('chip-${entry.key}'),
              borderRadius: BorderRadius.circular(kRadiusFull),
              onTap: () => onTap(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: kSpaceSm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: mine.contains(entry.key)
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(kRadiusFull),
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Text(
                  '${entry.key} ${entry.value}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}
