/// Chat screen — reactive over `chatService.watchMessages(channelId)`.
library vartalap.screens.chat.chat;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap/screens/chat/chat_search.dart';
import 'package:vartalap/screens/chat_info/chat_info.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
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

  void _jumpToMessage(String messageId) {
    setState(() => _highlightedMessageId = messageId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _messageKeys[messageId]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.3,
        );
      }
    });
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

  Future<void> _openMessageSheet(MessageRow msg) async {
    final mine = msg.authorUserId == widget.authService.currentUserId;
    // §6a.3: recipients drop an UPDATE/DELETE that isn't from the
    // author, so offering either on someone else's message would be a
    // button that does nothing.
    final canEdit = mine && !msg.tombstoned && (msg.body ?? '').isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        // Scrollable so the sheet still fits when the text scale is
        // cranked up or the window is short.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            if (!msg.tombstoned)
              _ReactionBar(
                selected: msg.reactions
                    .where((r) => r.userId == widget.authService.currentUserId)
                    .map((r) => r.emoji)
                    .toSet(),
                onPick: (emoji) {
                  Navigator.of(sheetCtx).pop();
                  _toggleReaction(msg, emoji);
                },
              ),
            if (!msg.tombstoned)
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  setState(() {
                    _replyTo = msg;
                    _editingMessageId = null;
                  });
                },
              ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                subtitle: const Text('Everyone sees it marked as edited'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _startEdit(msg);
                },
              ),
            if (!msg.tombstoned && (msg.body ?? '').isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy text'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  Clipboard.setData(ClipboardData(text: msg.body ?? ''));
                  _toast('Copied');
                },
              ),
            if (mine && !msg.tombstoned)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(sheetCtx).colorScheme.error),
                title: Text(
                  'Delete for everyone',
                  style: TextStyle(color: Theme.of(sheetCtx).colorScheme.error),
                ),
                subtitle: Text(
                  'You have ${widget.undoWindow.inSeconds} seconds to undo',
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _deleteMessage(msg);
                },
              ),
            ],
          ),
        ),
      ),
    );
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
    _input.text = msg.body ?? '';
    _input.selection =
        TextSelection.collapsed(offset: _input.text.length);
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

  Future<void> _onSend() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
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
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.authService.currentUserId ?? '';
    final scheme = Theme.of(context).colorScheme;
    final chatColors = VartalapTheme.chatColorsOf(context);

    return Scaffold(
      appBar: AppBar(
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
                    if (!m.tombstoned) m.messageId: m.body ?? '',
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
                  items.add(_MessageBubble(
                    key: _keyForMessage(msg.messageId),
                    message: msg,
                    isMine: mine,
                    showTail: showTail,
                    chatColors: chatColors,
                    highlighted:
                        _highlightedMessageId == msg.messageId,
                    senderLabel: senderLabel,
                    localUserId: currentUserId,
                    replyPreview: msg.replyToMessageId == null
                        ? null
                        : bodyById[msg.replyToMessageId],
                    onLongPress: () => _openMessageSheet(msg),
                    onReactionTap: (emoji) => _toggleReaction(msg, emoji),
                    onRetry:
                        failedOpId == null ? null : () => _retry(failedOpId),
                  ));

                  // Insert a date chip between this message and the
                  // next older one (i+1) if they fall on different days.
                  // Also insert one above the very oldest message.
                  final thisDate = DateTime.fromMillisecondsSinceEpoch(
                      msg.clientTimestampMs);
                  final bool needsDateChip;
                  if (i == messages.length - 1) {
                    needsDateChip = true; // oldest message
                  } else {
                    final olderDate = DateTime.fromMillisecondsSinceEpoch(
                        messages[i + 1].clientTimestampMs);
                    needsDateChip = thisDate.year != olderDate.year ||
                        thisDate.month != olderDate.month ||
                        thisDate.day != olderDate.day;
                  }
                  if (needsDateChip) {
                    items.add(_DateChip(date: thisDate));
                  }
                }

                return ListView(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: kSpaceSm,
                    vertical: kSpaceSm,
                  ),
                  children: items,
                );
              },
            ),
          ),
          _MessageInput(
            controller: _input,
            sending: _sending,
            onSend: _onSend,
            editing: _editingMessageId != null,
            replyPreview: _replyTo?.body,
            onCancelCompose:
                (_editingMessageId != null || _replyTo != null)
                    ? _cancelCompose
                    : null,
          ),
        ],
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
  final bool sending;
  final VoidCallback onSend;

  /// Composer is in edit mode — the send button applies a
  /// MESSAGE_UPDATE to an existing message instead of sending a new one.
  final bool editing;

  /// Body of the message being replied to, if any.
  final String? replyPreview;

  /// Non-null while editing or replying; clears both.
  final VoidCallback? onCancelCompose;

  const _MessageInput({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.editing = false,
    this.replyPreview,
    this.onCancelCompose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpaceSm,
          vertical: kSpaceSm,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
        if (editing || replyPreview != null)
          Container(
            margin: const EdgeInsets.only(bottom: kSpaceSm),
            padding: const EdgeInsets.symmetric(
              horizontal: kSpaceSm,
              vertical: kSpaceXs,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(kRadiusSm),
              border: Border(
                left: BorderSide(color: scheme.primary, width: 3),
              ),
            ),
            child: Row(
              children: [
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
                        : (replyPreview!.isEmpty ? 'Message' : replyPreview!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(kRadiusXl),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Message',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: kSpaceMd,
                      vertical: kSpaceSm + kSpaceXs,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: kSpaceSm),
            Material(
              color: scheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: Padding(
                  padding: const EdgeInsets.all(kSpaceSm + kSpaceXs),
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
                          editing ? Icons.check_rounded : Icons.send_rounded,
                          size: 20,
                          color: scheme.onPrimary,
                        ),
                ),
              ),
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kSpaceSm,
        vertical: kSpaceXs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final emoji in emojis)
            InkWell(
              key: ValueKey('react-$emoji'),
              customBorder: const CircleBorder(),
              onTap: () => onPick(emoji),
              child: Container(
                padding: const EdgeInsets.all(kSpaceSm),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected.contains(emoji)
                      ? scheme.primaryContainer
                      : Colors.transparent,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
        ],
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

    final timeStr = DateFormat.Hm().format(
      DateTime.fromMillisecondsSinceEpoch(message.clientTimestampMs),
    );

    // The meta row (time + optional tick) that tucks into the message.
    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.isEdited && !tombstoned) ...[
          Text(
            'edited',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: timestampColor,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          timeStr,
          style: TextStyle(fontSize: 11, color: timestampColor),
        ),
        if (isMine && !tombstoned) ...[
          const SizedBox(width: 3),
          _stateIcon(message.state, timestampColor),
        ],
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
        left: isMine ? 64 : 0,
        right: isMine ? 0 : 64,
      ),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
        GestureDetector(
          onLongPress: onLongPress,
          child: PhysicalShape(
          clipper: _BubbleClipper(isMine: isMine, showTail: showTail),
          color: bg,
          elevation: 0.5,
          shadowColor: Colors.black26,
          child: Padding(
            padding: EdgeInsets.only(
              left: !isMine && showTail ? 16 : 12,
              right: isMine && showTail ? 16 : 12,
              top: 7,
              bottom: 6,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.68,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (senderLabel != null) ...[
                    Text(
                      senderLabel!,
                      style: TextStyle(
                        color: _senderColor(senderLabel!),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  if (replyPreview != null && !tombstoned) ...[
                    _ReplyQuote(text: replyPreview!, tint: fg),
                    const SizedBox(height: 4),
                  ],
                  for (final a in _attachments)
                    if (!tombstoned) _AttachmentView(attachment: a, tint: fg),
                  // Wrap lets the meta (time+tick) sit at the end of the
                  // last line of text if there's room, or drop to a new
                  // line if the text fills the full width.
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      if (tombstoned)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.block,
                                size: 14,
                                color: fg.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text(
                              'This message was deleted',
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.6),
                                fontSize: 15,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          message.body ?? '',
                          style:
                              TextStyle(color: fg, fontSize: 16, height: 1.35),
                        ),
                      meta,
                    ],
                  ),
                  if (failed) ...[
                    const SizedBox(height: 2),
                    Row(
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
                  ],
                ],
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

  const _ReplyQuote({required this.text, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

/// Inbound attachment. An image mime type renders inline; anything else
/// gets a file row. Sending attachments is not wired yet, so everything
/// here comes off the wire with a server-side URL.
class _AttachmentView extends StatelessWidget {
  final pb.Attachment attachment;
  final Color tint;

  const _AttachmentView({required this.attachment, required this.tint});

  bool get _isImage => attachment.mimeType.startsWith('image/');

  @override
  Widget build(BuildContext context) {
    if (!_isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: kSpaceXs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 28, color: tint),
            const SizedBox(width: kSpaceSm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.filename.isEmpty
                        ? 'Attachment'
                        : attachment.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tint, fontSize: 14),
                  ),
                  Text(
                    _humanSize(attachment.sizeBytes.toInt()),
                    style: TextStyle(
                      color: tint.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Reserve the sender-declared aspect ratio where we have one so the
    // bubble doesn't jump when the bytes land.
    final w = attachment.width;
    final h = attachment.height;
    final image = Image.network(
      attachment.url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(
              alignment: Alignment.center,
              color: tint.withValues(alpha: 0.08),
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
      errorBuilder: (context, _, __) => Container(
        alignment: Alignment.center,
        color: tint.withValues(alpha: 0.08),
        padding: const EdgeInsets.all(kSpaceMd),
        child: Icon(Icons.broken_image_outlined, color: tint),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: kSpaceXs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: SizedBox(
          width: 220,
          child: (w > 0 && h > 0)
              ? AspectRatio(aspectRatio: w / h, child: image)
              : SizedBox(height: 160, child: image),
        ),
      ),
    );
  }

  static String _humanSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
    return Padding(
      padding: const EdgeInsets.only(top: 2),
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
                ),
                child: Text(
                  '${entry.key} ${entry.value}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
