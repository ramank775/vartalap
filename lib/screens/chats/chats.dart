/// Chat list — reactive over `chatService.watchChannels()`.
///
/// One merged inbox (frame a1). Long-press starts WhatsApp's selection
/// mode: the app bar becomes a contextual bar whose Pin, Delete and
/// Mute act on every selected chat, with Clear history and Select all
/// in its overflow. All of them are local-only.
///
/// Frame b (3.1) splits this list into Personal and Other with a
/// segmented row between the app bar and the list. That is a filter
/// over the same rows, not a redesign — see `_filterSlot` below.
library vartalap.screens.chats.chats;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/screens/group_create/group_create.dart';
import 'package:vartalap/screens/settings/settings.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/chat_action_sheets.dart';
import 'package:vartalap/widgets/Inherited/app_services.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

class ChatsScreen extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;
  final ConfigStore config;
  const ChatsScreen({
    super.key,
    required this.chatService,
    required this.authService,
    required this.config,
  });

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  /// Created once so rebuilds don't resubscribe and re-run the
  /// underlying SQL query.
  late final Stream<List<ChannelListEntry>> _channelsStream =
      widget.chatService.watchChannels().asyncMap((rows) async {
    // Re-read with every emission: a contact sync renames people
    // without touching the chat list, so a once-only read goes stale.
    final contacts = await widget.chatService.discoverContacts();
    _senderLabels = {for (final c in contacts) c.userId: c.displayLabel};
    return rows;
  });

  /// author userId → [ContactRow.displayLabel], for the "Vikram:"
  /// sender prefix on group rows. A channel row resolves its own title
  /// through [ChannelListEntry.title]; the *author* of its preview is
  /// a third party the row has no contact for, so it is resolved here
  /// against the local contacts cache — same resolver, different key.
  Map<String, String> _senderLabels = const {};

  /// Chats picked by long-press, in WhatsApp's selection mode. Empty
  /// means not selecting.
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    // No provider: a standalone widget test.
    final wsTransport = AppServicesProvider.maybeOf(context)?.wsTransport;
    final chatColors = VartalapTheme.chatColorsOf(context);
    final localUserId = widget.authService.currentUserId;

    // Above the Scaffold, because the selection bar needs the rows too.
    return StreamBuilder<List<ChannelListEntry>>(
      stream: _channelsStream,
      builder: (context, snapshot) {
        final channels = snapshot.data ?? const <ChannelListEntry>[];
        // Chats that left the list drop out of the selection.
        final selected = [
          for (final e in channels)
            if (_selectedIds.contains(e.channelId)) e,
        ];
        // Back closes the selection first, like WhatsApp.
        return PopScope(
          canPop: selected.isEmpty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _clearSelection();
          },
          child: Scaffold(
            appBar: selected.isEmpty
                ? _buildDefaultAppBar(context, wsTransport, chatColors)
                : _selectionBar(selected, channels),
            body: Column(
              children: [
                // 3.1 slot: the Personal | Other segmented row drops in
                // here (frame b). In 3.0 it renders nothing and the list
                // below is merged — same rows, same sorting, same
                // selection.
                ..._filterSlot,
                Expanded(
                  child: Builder(builder: (context) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    if (channels.isEmpty) {
                      return const _EmptyChats();
                    }
                    return ListView.separated(
                      itemCount: channels.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final entry = channels[i];
                        return ChannelTile(
                          entry: entry,
                          chatColors: chatColors,
                          displayName: entry.title,
                          senderPrefix: _senderPrefix(entry, localUserId),
                          eventText: _eventText(entry, localUserId),
                          selected: _selectedIds.contains(entry.channelId),
                          // While selecting, a tap adds or removes a chat.
                          onTap: selected.isEmpty
                              ? () => _openChat(context, entry)
                              : () => _toggleSelected(entry),
                          onLongPress: () => _toggleSelected(entry),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => _newChat(context),
              child: const Icon(Icons.chat),
            ),
          ),
        );
      },
    );
  }

  void _toggleSelected(ChannelListEntry entry) {
    setState(() {
      if (!_selectedIds.remove(entry.channelId)) {
        _selectedIds.add(entry.channelId);
      }
    });
  }

  void _clearSelection() {
    if (mounted && _selectedIds.isNotEmpty) setState(_selectedIds.clear);
  }

  /// WhatsApp's contextual bar: back and the count on the left; Pin,
  /// Delete and Mute in its order on the right, each acting on every
  /// selected chat. Pin and Mute flip to Unpin and Unmute only when
  /// every selected chat already is.
  AppBar _selectionBar(
    List<ChannelListEntry> sel,
    List<ChannelListEntry> all,
  ) {
    final allPinned = sel.every((e) => e.pinned);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final allMuted = sel.every((e) => e.isMutedAt(nowMs));
    final one = sel.length == 1 ? sel.single : null;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
        onPressed: _clearSelection,
      ),
      title: Text('${sel.length}'),
      actions: [
        IconButton(
          // ponytail: Material has no crossed-out pin; the filled one
          // reads as "pinned", and the tooltip says Unpin.
          icon: Icon(allPinned ? Icons.push_pin : Icons.push_pin_outlined),
          tooltip: allPinned ? 'Unpin chat' : 'Pin chat',
          onPressed: () async {
            _clearSelection();
            for (final e in sel) {
              await widget.chatService.setPinned(e.channelId, !allPinned);
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete chat',
          onPressed: () async {
            final deleted = await confirmDeleteChat(
              context: context,
              chatService: widget.chatService,
              channelIds: [for (final e in sel) e.channelId],
              isGroup: one?.kind == 'group',
            );
            if (deleted) _clearSelection();
          },
        ),
        IconButton(
          icon: Icon(
            allMuted
                ? Icons.notifications_outlined
                : Icons.notifications_off_outlined,
          ),
          tooltip: allMuted ? 'Unmute notifications' : 'Mute notifications',
          onPressed: () async {
            if (allMuted) {
              _clearSelection();
              for (final e in sel) {
                await widget.chatService.setMuted(e.channelId, null);
              }
              return;
            }
            final saved = await showMuteSheet(
              context: context,
              chatService: widget.chatService,
              channelIds: [for (final e in sel) e.channelId],
              mutedUntilMs: one?.mutedUntilMs,
            );
            if (saved) _clearSelection();
          },
        ),
        PopupMenuButton<String>(
          iconColor: Theme.of(context).appBarTheme.foregroundColor,
          onSelected: (value) async {
            if (value == 'all') {
              setState(() => _selectedIds.addAll(all.map((e) => e.channelId)));
              return;
            }
            final cleared = await confirmClearHistory(
              context: context,
              chatService: widget.chatService,
              channelId: one!.channelId,
              isGroup: one.kind == 'group',
            );
            if (cleared) _clearSelection();
          },
          itemBuilder: (_) => [
            if (one != null)
              const PopupMenuItem(value: 'clear', child: Text('Clear history')),
            const PopupMenuItem(value: 'all', child: Text('Select all')),
          ],
        ),
      ],
    );
  }

  /// Empty in 3.0. See the class doc.
  List<Widget> get _filterSlot => const [];

  /// "Vikram: " / "You: " in front of a group preview, so a group row
  /// is legible without reading the name (frame a1). DMs get no prefix
  /// — there is only one other person in the room.
  String? _senderPrefix(ChannelListEntry entry, String? localUserId) {
    if (entry.kind != 'group') return null;
    if (entry.lastMessageContentType == kGroupEventType) return null;
    final author = entry.lastMessageAuthor;
    if (author == null) return null;
    if (author == localUserId) return 'You: ';
    final label = _senderLabels[author];
    return label == null ? null : '$label: ';
  }

  /// A group whose latest line is "Asha added you" previews as that.
  String? _eventText(ChannelListEntry entry, String? localUserId) {
    if (entry.lastMessageContentType != kGroupEventType) return null;
    final event = GroupEvent.parse(entry.lastMessagePreview);
    if (event == null) return null;
    return groupEventText(
      event,
      actorUserId: entry.lastMessageAuthor ?? '',
      selfUserId: localUserId,
      nameOf: (id) => _senderLabels[id] ?? 'Unknown',
    );
  }

  AppBar _buildDefaultAppBar(
    BuildContext context,
    WsTransport? wsTransport,
    ChatColors chatColors,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      title: StreamBuilder<TransportState>(
        stream: wsTransport?.state,
        initialData: wsTransport?.currentState ?? TransportState.connected,
        builder: (context, snapshot) {
          final state = snapshot.data ?? TransportState.disconnected;
          return Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor(state, chatColors),
                ),
              ),
              const SizedBox(width: kSpaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.config.packageInfo.appName),
                    if (state != TransportState.connected)
                      Text(
                        _statusLabel(state),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                          // On the app bar, so its foreground, not
                          // onSurface (dark on the green bar).
                          color: (Theme.of(context)
                                      .appBarTheme
                                      .foregroundColor ??
                                  scheme.onSurface)
                              .withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        // WhatsApp's menu: plain text, New group then Settings; your
        // profile lives inside Settings (decision 154).
        PopupMenuButton<String>(
          // M3 colours this icon onSurfaceVariant, not the app bar's
          // foreground, which left it dark on the green bar.
          iconColor: Theme.of(context).appBarTheme.foregroundColor,
          onSelected: (value) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => value == 'group'
                  ? GroupCreateScreen(
                      chatService: widget.chatService,
                      authService: widget.authService,
                    )
                  : SettingsScreen(
                      authService: widget.authService,
                      config: widget.config,
                      chatService: widget.chatService,
                    ),
            ),
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'group', child: Text('New group')),
            PopupMenuItem(value: 'settings', child: Text('Settings')),
          ],
        ),
      ],
    );
  }

  static Color _statusColor(TransportState state, ChatColors colors) {
    switch (state) {
      case TransportState.connected:
        return colors.statusConnected;
      case TransportState.connecting:
        return colors.statusConnecting;
      case TransportState.disconnected:
        return colors.statusDisconnected;
    }
  }

  static String _statusLabel(TransportState state) {
    switch (state) {
      case TransportState.connecting:
        return 'Connecting…';
      case TransportState.disconnected:
        return 'Waiting for network…';
      case TransportState.connected:
        return '';
    }
  }

  void _newChat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewChatScreen(
          chatService: widget.chatService,
          authService: widget.authService,
        ),
      ),
    );
  }

  void _openChat(BuildContext context, ChannelListEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          channelId: entry.channelId,
          channelName: entry.title,
          channelKind: entry.kind,
          chatService: widget.chatService,
          authService: widget.authService,
        ),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kSpaceXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer.withValues(alpha: 0.3),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: kSpaceMd),
            Text(
              'No chats yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: kSpaceSm),
            Text(
              'Tap the button below to start a conversation.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the chat list (frame a1). Public so widget tests can
/// pump a row on its own, and so the 3.1 split can reuse it verbatim.
class ChannelTile extends StatelessWidget {
  final ChannelListEntry entry;
  final ChatColors chatColors;
  final String displayName;
  final String? senderPrefix;

  /// The latest line is a group event, already worded; shown as is.
  final String? eventText;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Picked in the chat list's selection mode: tinted, with a check on
  /// the avatar (WhatsApp).
  final bool selected;

  const ChannelTile({
    super.key,
    required this.entry,
    required this.chatColors,
    required this.displayName,
    this.senderPrefix,
    this.eventText,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = entry.isMutedAt(DateTime.now().millisecondsSinceEpoch);
    final hasUnread = entry.unreadCount > 0;
    final avatar = Avator(
      text: displayName,
      // Seeded on the id, not the name: renaming a group must not
      // repaint its avatar.
      seed: entry.channelId,
      avatarUrl: entry.avatarUrl,
      isGroup: entry.kind == 'group',
      width: kAvatarMd,
      height: kAvatarMd,
    );
    // WhatsApp's second line, right-aligned under the time: muted, then
    // pinned, then the unread count.
    final indicators = [
      if (muted)
        Icon(
          Icons.notifications_off_outlined,
          size: 18,
          color: scheme.onSurfaceVariant,
          semanticLabel: 'Muted',
        ),
      if (entry.pinned)
        Icon(
          Icons.push_pin,
          size: 18,
          color: scheme.onSurfaceVariant,
          semanticLabel: 'Pinned',
        ),
      if (hasUnread)
        _UnreadBadge(
          count: entry.unreadCount,
          chatColors: chatColors,
          muted: muted,
        ),
    ];

    return ListTile(
      // The same tint as a selected message in the chat screen.
      tileColor: selected ? scheme.primary.withValues(alpha: 0.12) : null,
      leading: !selected
          ? avatar
          : Stack(
              clipBehavior: Clip.none,
              children: [
                avatar,
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                      border: Border.all(color: scheme.surface, width: 2),
                    ),
                    child: Icon(
                      Icons.check,
                      size: 14,
                      color: scheme.onPrimary,
                      semanticLabel: 'Selected',
                    ),
                  ),
                ),
              ],
            ),
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: _subtitle(context, scheme, hasUnread),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTime(context, entry.lastActivityMs),
            style: TextStyle(
              fontSize: 12,
              color: hasUnread && !muted
                  ? chatColors.unreadBadge
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: kSpaceXs),
          // Fixed height, even when empty, so the time sits on the same
          // line in every row whatever the second line holds.
          SizedBox(
            height: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, w) in indicators.indexed) ...[
                  if (i > 0) const SizedBox(width: kSpaceXs),
                  w,
                ],
              ],
            ),
          ),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  /// The preview line, or the failed-send indicator when an op
  /// targeting this channel has dead-lettered — a row can only say one
  /// thing, and "Not sent" outranks the last message.
  Widget _subtitle(
    BuildContext context,
    ColorScheme scheme,
    bool hasUnread,
  ) {
    if (entry.hasFailedOp) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 14, color: scheme.error),
          const SizedBox(width: kSpaceXs),
          Expanded(
            child: Text(
              'Not sent · tap to retry',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ],
      );
    }

    final preview = entry.lastMessageTombstoned
        ? '(message deleted)'
        : eventText ?? messagePreview(
            entry.lastMessagePreview ?? '',
            entry.lastMessageContentType,
            attachment: entry.lastMessageHasAttachment,
          );
    return Text.rich(
      TextSpan(
        children: [
          if (senderPrefix != null)
            TextSpan(
              text: senderPrefix,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          TextSpan(text: preview),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontStyle:
            entry.lastMessageTombstoned ? FontStyle.italic : FontStyle.normal,
        color: hasUnread ? scheme.onSurface : scheme.onSurfaceVariant,
      ),
    );
  }

  static String _formatTime(BuildContext context, int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    // TimeOfDay follows the phone's 12/24-hour setting; DateFormat.jm()
    // only follows the locale.
    if (days == 0) return TimeOfDay.fromDateTime(d).format(context);
    if (days == 1) return 'Yesterday';
    if (days < 7) return DateFormat.E().format(d);
    if (d.year == now.year) return DateFormat.MMMd().format(d);
    return DateFormat.yMd().format(d);
  }
}

/// Filled when the chat alerts, outlined when it is muted — a muted
/// chat still counts, it just stops shouting.
class _UnreadBadge extends StatelessWidget {
  final int count;
  final ChatColors chatColors;
  final bool muted;

  const _UnreadBadge({
    required this.count,
    required this.chatColors,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: kSpaceSm,
        vertical: kSpaceXs,
      ),
      constraints: const BoxConstraints(minWidth: 24),
      decoration: BoxDecoration(
        color: muted ? Colors.transparent : chatColors.unreadBadge,
        border: muted ? Border.all(color: scheme.outline) : null,
        borderRadius: BorderRadius.circular(kRadiusFull),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: muted ? scheme.onSurfaceVariant : chatColors.unreadBadgeText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
