/// Chat screen — reactive over `chatService.watchMessages(channelId)`.
library vartalap.screens.chat.chat;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap/screens/chat/attachment_preview.dart';
import 'package:vartalap/screens/chat/chat_search.dart';
import 'package:vartalap/screens/chat/rich_messages.dart';
import 'package:vartalap/screens/chat/voice_note.dart';
import 'package:vartalap/screens/chat_info/chat_info.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap/utils/phone_number.dart';
import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';

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

  const ChatScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.channelKind,
    required this.chatService,
    required this.authService,
    this.undoWindow = const Duration(seconds: 5),
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  /// The body as it was when Edit started; confirming it unchanged sends
  /// nothing (an edit would mark the message "edited" for no change).
  String? _editingOriginal;
  bool _sending = false;
  StreamSubscription<List<MessageRow>>? _readMarkerSub;
  String? _lastMarkedReadMessageId;

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

  /// The voice note being recorded; null while the composer is text.
  AudioRecorder? _recorder;
  DateTime _recordingSince = DateTime.now();
  Timer? _recordingTicker;
  // Owner: one minute, then it sends itself.
  static const Duration _maxVoiceNote = Duration(minutes: 1);

  /// The one delete sitting in its undo window. Committing is ours to
  /// do — the timer outlives the snackbar, and [dispose] flushes — so a
  /// tombstone can never strand un-enqueued.
  String? _deletingMessageId;
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

  /// Long-pressed message (WhatsApp's selection): the app bar turns
  /// into its actions and the reaction bar floats over it, following it
  /// through [_selectedLink]. ponytail: one at a time; multi-select
  /// (delete/copy several) when someone asks.
  String? _selectedId;
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

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    _typingSub = widget.chatService.typingEvents.listen(_onPeerTyping);
    _scroll.addListener(_onScroll);
    if (widget.channelKind == 'group') _loadMemberNames();
    // Trim 4: a DM has no server-side row, so the server cannot fan a
    // peer's profile edits to us (SYNC_PROTOCOL §10.3). Pull them when
    // the chat opens — the one moment the staleness would show.
    unawaited(widget.chatService.refreshDmPeerProfile(widget.channelId));
    // Any delete whose undo window elapsed while this screen was closed
    // (or the app was dead) gets enqueued now.
    unawaited(widget.chatService.sweepExpiredDeletes(widget.channelId));
    _failureSub = widget.chatService.watchFailures().listen(_onFailures);
    // While the chat is open, every new peer message that lands also
    // counts as read. Subscribe once (to the same stream the StreamBuilder
    // below renders, so opening a chat runs one live query, not two) and
    // re-mark whenever the latest message_id from a peer changes —
    // `markRead` is idempotent on the local marker, and the read-receipt
    // op is dedup'd by op_id on the server, so re-firing on every stream
    // tick is safe. This also covers "mark read on open": the first
    // emission is the initial query result, so there's no separate eager
    // markRead call here (that used to double-enqueue the read-receipt op).
    final localUserId = widget.authService.currentUserId;
    _readMarkerSub = _messagesStream.listen((rows) {
      // Every emission answers the paging question too: a short page
      // means we've reached the start of the conversation.
      _loadingOlder = false;
      _hasMoreOlder = rows.length >= _window.limit;
      if (localUserId == null) return;
      // Newest peer message first — `watchMessages` returns newest-first.
      MessageRow? latestPeer;
      for (final r in rows) {
        if (r.authorUserId != localUserId && !r.tombstoned) {
          latestPeer = r;
          break;
        }
      }
      if (latestPeer == null) return;
      if (latestPeer.messageId == _lastMarkedReadMessageId) return;
      _lastMarkedReadMessageId = latestPeer.messageId;
      widget.chatService.markRead(widget.channelId);
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
  void dispose() {
    // Leaving the screen ends the undo window: commit rather than
    // leaving a tombstone that nobody will ever enqueue.
    _deleteTimer?.cancel();
    final pendingDelete = _deletingMessageId;
    if (pendingDelete != null) {
      unawaited(widget.chatService.commitDelete(
        channelId: widget.channelId,
        messageId: pendingDelete,
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
    _scroll.dispose();
    _readMarkerSub?.cancel();
    _highlightTimer?.cancel();
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
    if (!mounted) return;
    setState(() {
      _memberNames = {
        for (final m in members)
          m.userId: m.contact?.displayLabel ?? 'Unknown',
      };
    });
  }

  Future<void> _openSearch() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ChatSearchScreen(
          channelId: widget.channelId,
          channelName: widget.channelName,
          chatService: widget.chatService,
          localUserId: widget.authService.currentUserId,
        ),
      ),
    );
    if (picked != null && mounted) {
      _jumpToMessage(picked);
    }
  }

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

  Future<void> _jumpToMessage(String messageId) async {
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer?.cancel();
    // Rows off screen aren't built, so there is nothing to scroll to
    // yet: page toward older messages (the reversed list's far end)
    // until the target row exists, then bring it into view.
    // ponytail: older-only and 30 pages at most; a reply or search hit
    // is behind you, and the window loads more as it goes.
    for (var i = 0; i < 30 && mounted; i++) {
      await WidgetsBinding.instance.endOfFrame;
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
      if (pos.pixels >= pos.maxScrollExtent) break;
      _scroll.jumpTo(math.min(
        pos.pixels + pos.viewportDimension * 0.8,
        pos.maxScrollExtent,
      ));
    }
    if (!mounted) return;
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
  bool _canEdit(MessageRow msg) =>
      _isMine(msg) &&
      !msg.tombstoned &&
      (msg.body ?? '').isNotEmpty &&
      !isRichType(msg.contentType) &&
      (msg.attachments == null || msg.serverTimestampMs != null);

  bool _isMine(MessageRow msg) =>
      msg.authorUserId == widget.authService.currentUserId;

  /// Text worth copying: a body that is words, not a vCard / geo URI.
  bool _canCopy(MessageRow msg) =>
      !msg.tombstoned &&
      (msg.body ?? '').isNotEmpty &&
      !isRichType(msg.contentType);

  void _select(MessageRow msg) {
    HapticFeedback.mediumImpact();
    // Otherwise the keyboard stays up over the actions; Edit and Reply
    // ask for it again.
    _inputFocus.unfocus();
    final box = _messageKeys[msg.messageId]?.currentContext?.findRenderObject()
        as RenderBox?;
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    setState(() {
      _selectedId = msg.messageId;
      _barBelow = box != null &&
          list != null &&
          box.localToGlobal(Offset.zero).dy -
                  list.localToGlobal(Offset.zero).dy <
              64;
    });
  }

  void _clearSelection() {
    if (_selectedId != null) setState(() => _selectedId = null);
  }

  void _reply(MessageRow msg) {
    setState(() {
      _selectedId = null;
      _replyTo = msg;
      _editingMessageId = null;
    });
    _inputFocus.requestFocus();
  }

  void _copy(MessageRow msg) {
    _clearSelection();
    Clipboard.setData(ClipboardData(text: msg.body ?? ''));
    _toast('Copied');
  }

  /// The selection app bar: what you can do with the long-pressed
  /// message (WhatsApp's contextual bar).
  AppBar _selectionBar(MessageRow msg) => AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: _clearSelection,
        ),
        actions: [
          if (!msg.tombstoned)
            IconButton(
              icon: const Icon(Icons.reply),
              tooltip: 'Reply',
              onPressed: () => _reply(msg),
            ),
          if (_canCopy(msg))
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copy',
              onPressed: () => _copy(msg),
            ),
          if (_canEdit(msg))
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () {
                _clearSelection();
                _startEdit(msg);
              },
            ),
          if (_isMine(msg) && !msg.tombstoned)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete for everyone',
              onPressed: () {
                _clearSelection();
                _deleteMessage(msg);
              },
            ),
        ],
      );

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
  /// Only one delete is ever pending — a second one commits the first
  /// rather than racing it.
  Future<void> _deleteMessage(MessageRow msg) async {
    await _flushPendingDelete();
    await widget.chatService.deleteMessage(
      messageId: msg.messageId,
      undoWindow: widget.undoWindow,
    );
    if (!mounted) return;
    _deletingMessageId = msg.messageId;
    _deleteTimer = Timer(widget.undoWindow, () {
      final id = _deletingMessageId;
      _deletingMessageId = null;
      if (id == null) return;
      unawaited(widget.chatService
          .commitDelete(channelId: widget.channelId, messageId: id));
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      duration: widget.undoWindow,
      content: Row(
        children: [
          _UndoCountdown(window: widget.undoWindow),
          const SizedBox(width: kSpaceSm),
          const Expanded(child: Text('Message deleted')),
        ],
      ),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () {
          _deleteTimer?.cancel();
          _deletingMessageId = null;
          unawaited(widget.chatService.undoDelete(msg.messageId));
        },
      ),
    ));
  }

  /// Commit whatever delete is mid-window right now (a second delete, or
  /// leaving the screen). Idempotent — the store no-ops if Undo won.
  Future<void> _flushPendingDelete() async {
    _deleteTimer?.cancel();
    final id = _deletingMessageId;
    _deletingMessageId = null;
    if (id == null) return;
    await widget.chatService
        .commitDelete(channelId: widget.channelId, messageId: id);
  }

  /// Composer attach button (frame d1). One sheet: the camera, the
  /// gallery for photos and videos (photos we can size for the bubble),
  /// the system file picker for everything else, and the text-format
  /// kinds — contact, location, event (decision 133).
  Future<void> _onAttach({String? preset}) async {
    const options = [
      (Icons.photo_camera_outlined, 'Camera', 'camera'),
      (Icons.image_outlined, 'Gallery', 'gallery'),
      (Icons.insert_drive_file_outlined, 'Document', 'file'),
      (Icons.person_outline, 'Contact', 'contact'),
      (Icons.location_on_outlined, 'Location', 'location'),
      (Icons.event_outlined, 'Event', 'event'),
    ];
    final choice = preset ?? await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            padding: const EdgeInsets.all(kSpaceLg),
            mainAxisSpacing: kSpaceMd,
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
                      const SizedBox(height: kSpaceSm),
                      Text(label),
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
    if (choice == 'location') return _shareLocation();
    if (choice == 'event') return _shareEvent();

    String? sourcePath;
    var width = 0;
    var height = 0;
    try {
      if (choice != 'file') {
        // ponytail: one fixed "standard quality" (WhatsApp sends ~1600px);
        // an HD toggle is a preview-screen option when that screen exists.
        // Videos go as picked.
        final picker = ImagePicker();
        final picked = choice == 'camera'
            ? await picker.pickImage(
                source: ImageSource.camera,
                maxWidth: 2048,
                maxHeight: 2048,
                imageQuality: 85,
              )
            : await picker.pickMedia(
                maxWidth: 2048,
                maxHeight: 2048,
                imageQuality: 85,
              );
        if (picked == null) return;
        sourcePath = picked.path;
        // Sender-declared dimensions let the bubble reserve the right
        // aspect ratio before the bytes land.
        if (mimeForPath(picked.path).startsWith('image/')) {
          final size = await _decodeSize(picked.path);
          width = size?.$1 ?? 0;
          height = size?.$2 ?? 0;
        }
      } else {
        final result = await FilePicker.platform.pickFiles();
        sourcePath = result?.files.single.path;
        if (sourcePath == null) return;
      }
    } on PlatformException catch (e) {
      _toast('Could not open the picker: ${e.code}');
      return;
    }

    if (!mounted) return;
    final caption = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AttachmentPreviewScreen(path: sourcePath!),
      ),
    );
    if (caption == null || !mounted) return;

    final userId = widget.authService.currentUserId;
    if (userId == null) return;
    setState(() => _sending = true);
    try {
      // Out of the picker's temp dir before the OS sweeps it — the
      // upload op may not run for hours.
      final path = await widget.chatService.assets.importPicked(sourcePath);
      await widget.chatService.sendAttachment(
        channelId: widget.channelId,
        authorUserId: userId,
        path: path,
        caption: caption.isEmpty ? null : caption,
        replyToMessageId: _replyTo?.messageId,
        width: width,
        height: height,
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
      final id = await FlutterContacts.native.showPicker();
      if (id == null) return;
      final contact = await FlutterContacts.get(id, properties: {
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

  /// Current location only, after a confirm that says how precise it is
  /// (decision 135: no map to pick a place on).
  Future<void> _shareLocation() async {
    if (!await Permission.locationWhenInUse.request().isGranted) {
      _toast('Vartalap needs location access to share where you are');
      return;
    }
    _toast('Finding your location…');
    final point = await currentLocation();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (point == null) {
      _toast("Couldn't get your location. Is location turned on?");
      return;
    }
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send your current location?'),
        content: Text([
          if (point.accuracyM != null)
            'Accurate to ${point.accuracyM!.round()} m',
          '${point.lat.toStringAsFixed(5)}, ${point.lng.toStringAsFixed(5)}',
        ].join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (send == true) await _sendRich(point.toUri(), kLocationType);
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

  /// Intrinsic pixel size of a picked image, or null if it will not
  /// decode (the bubble then falls back to a fixed height).
  Future<(int, int)?> _decodeSize(String path) async {
    try {
      final codec = await ui.instantiateImageCodec(
        await File(path).readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      final size = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

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
          bitRate: 32000,
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
      } else {
        await widget.chatService.sendMessage(
          channelId: widget.channelId,
          body: body,
          authorUserId: userId,
          replyToMessageId: _replyTo?.messageId,
        );
        _toBottom();
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
    final chatColors = VartalapTheme.chatColorsOf(context);

    final selected = _selectedId == null
        ? null
        : _lastMessages.where((m) => m.messageId == _selectedId).firstOrNull;
    // Back closes the selection first, like WhatsApp.
    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
      appBar: selected != null
          ? _selectionBar(selected)
          : AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatInfoScreen(
                  channelId: widget.channelId,
                  channelName: widget.channelName,
                  channelKind: widget.channelKind,
                  chatService: widget.chatService,
                  authService: widget.authService,
                ),
              ),
            );
          },
          child: Row(
            children: [
              Avator(
                text: widget.channelName,
                seed: widget.channelId,
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
                      widget.channelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_peerTypingTimers.isNotEmpty)
                      Text(
                        _peerTypingTimers.length == 1
                            ? 'typing…'
                            : 'several people are typing…',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onPrimary.withValues(alpha: 0.85),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search in conversation',
            onPressed: _openSearch,
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
                      messages[i + 1].authorUserId != msg.authorUserId;

                  // Sender name appears above the first bubble of a
                  // same-author run, only for groups, only for peer
                  // messages. `showTail=true` already identifies "top
                  // of run" because the list is reverse-rendered.
                  final senderLabel =
                      (!mine && widget.channelKind == 'group' && showTail)
                          ? (_memberNames[msg.authorUserId] ?? 'Unknown')
                          : null;

                  final failedOpId = _failedOps[msg.messageId];
                  final isSelected = _selectedId == msg.messageId;
                  final replyTo = msg.replyToMessageId;
                  items.add(_SwipeToReply(
                    key: ValueKey('swipe-${msg.messageId}'),
                    onReply: msg.tombstoned ? null : () => _reply(msg),
                    child: _MessageBubble(
                    key: _keyForMessage(msg.messageId),
                    message: msg,
                    isMine: mine,
                    showTail: showTail,
                    chatColors: chatColors,
                    highlighted: isSelected ||
                        _highlightedMessageId == msg.messageId,
                    link: isSelected ? _selectedLink : null,
                    senderLabel: senderLabel,
                    localUserId: currentUserId,
                    replyPreview:
                        replyTo == null ? null : bodyById[replyTo],
                    onReplyTap: replyTo == null || !bodyById.containsKey(replyTo)
                        ? null
                        : () => _jumpToMessage(replyTo),
                    onLongPress: () => _select(msg),
                    // While one is selected, a tap anywhere on a bubble
                    // just lets go of it.
                    onTap: _selectedId == null ? null : _clearSelection,
                    onReactionTap: (emoji) => _toggleReaction(msg, emoji),
                    onRetry:
                        failedOpId == null ? null : () => _retry(failedOpId),
                    onMessageContact: _messageContact,
                  ),
                  ));

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
                    items.add(_DateChip(date: thisDate));
                  }
                }

                final sel = selected;
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
                    if (sel != null && !sel.tombstoned)
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
          _MessageInput(
            controller: _input,
            focusNode: _inputFocus,
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
            replyPreview: _replyTo == null ? null : _preview(_replyTo!),
            onCancelCompose:
                (_editingMessageId != null || _replyTo != null)
                    ? _cancelCompose
                    : null,
          ),
        ],
      ),
    ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;
  const _DateChip({required this.date});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: kSpaceSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: kSpaceMd,
            vertical: kSpaceXs + 2,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(kRadiusFull),
          ),
          child: Text(
            _formatDate(date),
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

  String _formatDate(DateTime d) {
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

  const _MessageInput({
    required this.controller,
    required this.focusNode,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
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
                            const EdgeInsets.fromLTRB(18, 13, 0, 13),
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
                  // WhatsApp hides the camera once there's text.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) =>
                        value.text.isEmpty && !editing
                            ? IconButton(
                                icon: const Icon(Icons.photo_camera_outlined),
                                tooltip: 'Camera',
                                color: muted,
                                onPressed: sending ? null : onCamera,
                              )
                            : const SizedBox(width: kSpaceXs),
                  ),
                ],
              ),
            ],
          );

    return SafeArea(
      top: false,
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

class _MessageBubble extends StatelessWidget {
  final MessageRow message;
  final bool isMine;
  final bool showTail;
  final ChatColors chatColors;
  final bool highlighted;
  final String? senderLabel;
  final String localUserId;

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

  /// Tapping the reply quote jumps to the message it quotes.
  final VoidCallback? onReplyTap;

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
    this.replyPreview,
    this.onRetry,
    this.onMessageContact,
    this.link,
    this.onTap,
    this.onReplyTap,
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

    // Time + tick (+ "edited"); white when it sits on a photo.
    Widget metaIn(Color color) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isEdited && !tombstoned) ...[
              Text(
                'edited',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
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
    final media = attachments.isNotEmpty || rich;
    final selfTimed = media && (rich || body.isEmpty);
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
      padding: EdgeInsets.only(
        top: showTail ? 8 : 2,
        bottom: 2,
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
          onLongPress: onLongPress,
          onTap: onTap,
          child: PhysicalShape(
          clipper: _BubbleClipper(isMine: isMine, showTail: showTail),
          color: bg,
          elevation: 0.5,
          shadowColor: Colors.black26,
          child: Padding(
            // The tail is drawn outside the box, so both sides match.
            padding: media
                ? const EdgeInsets.all(4)
                : const EdgeInsets.fromLTRB(12, 7, 12, 6),
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
                    ),
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
                          : TextSpan(text: body),
                      tombstoned ? 'This message was deleted' : body,
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
/// full-screen on tap; audio is a voice note; anything else is a
/// document box that opens on tap. `attachment.url` is a local path
/// while our own upload is still in flight and a media-ms fileId
/// afterwards — [AssetCache] resolves both.
class _AttachmentView extends StatelessWidget {
  final pb.Attachment attachment;
  final Color tint;

  /// The bubble's time + tick when there is no caption to carry it;
  /// `onPhoto` asks for the white version that sits on an image.
  final Widget Function(bool onPhoto)? footer;

  const _AttachmentView({
    required this.attachment,
    required this.tint,
    this.footer,
  });

  /// Media width; the bubble is this plus its 4 px frame.
  static const double width = 240;

  bool get _isImage => attachment.mimeType.startsWith('image/');

  String get _name =>
      attachment.filename.isEmpty ? 'Attachment' : attachment.filename;

  Future<void> _openFile(BuildContext context) async {
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
        footer: footer?.call(false),
      );
    }
    if (!_isImage) return _document(context);

    // Reserve the sender-declared aspect ratio where we have one so the
    // bubble doesn't jump when the bytes land.
    final w = attachment.width;
    final h = attachment.height;
    final image = AssetImageView(
      uri: attachment.url,
      fit: BoxFit.cover,
      placeholder: AssetImagePlaceholder(tint: tint),
      fallback: AssetImagePlaceholder(
        tint: tint,
        icon: Icons.broken_image_outlined,
      ),
    );
    final time = footer;
    return GestureDetector(
      onTap: () => showAssetViewer(
        context,
        uri: attachment.url,
        title: attachment.filename.isEmpty ? null : attachment.filename,
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
                      child: Icon(
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
