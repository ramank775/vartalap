/// Chat list — reactive over `chatService.watchChannels()`.
///
/// One merged inbox (frame a1). Per-chat actions live in the long-press
/// sheet (frame a2), not in a selection app bar: every one of them is
/// local-only, so there is nothing to batch and nothing to confirm at
/// the top of the screen.
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
import 'package:vartalap/screens/profile/profile.dart';
import 'package:vartalap/screens/settings/settings.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/chat_action_sheets.dart';
import 'package:vartalap/widgets/Inherited/app_services.dart';
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
      widget.chatService.watchChannels();

  /// author userId → [ContactRow.displayLabel], for the "Vikram:"
  /// sender prefix on group rows. A channel row resolves its own title
  /// through [ChannelListEntry.title]; the *author* of its preview is
  /// a third party the row has no contact for, so it is resolved here
  /// against the local contacts cache — same resolver, different key.
  Map<String, String> _senderLabels = const {};

  @override
  void initState() {
    super.initState();
    _loadSenderLabels();
  }

  Future<void> _loadSenderLabels() async {
    // No phones passed → local cache read, no network.
    final contacts = await widget.chatService.discoverContacts();
    if (!mounted) return;
    setState(() {
      _senderLabels = {
        for (final c in contacts) c.userId: c.displayLabel,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final wsTransport = AppServicesProvider.of(context).services.wsTransport;
    final chatColors = VartalapTheme.chatColorsOf(context);
    final localUserId = widget.authService.currentUserId;

    return Scaffold(
      appBar: _buildDefaultAppBar(context, wsTransport, chatColors),
      body: Column(
        children: [
          // 3.1 slot: the Personal | Other segmented row drops in here
          // (frame b). In 3.0 it renders nothing and the list below is
          // merged — same rows, same sorting, same sheet.
          ..._filterSlot,
          Expanded(
            child: StreamBuilder<List<ChannelListEntry>>(
              stream: _channelsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final channels = snapshot.data ?? const [];
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
                      onTap: () => _openChat(context, entry),
                      onLongPress: () => showChatActionsSheet(
                        context: context,
                        chatService: widget.chatService,
                        entry: entry,
                        displayName: entry.title,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _newChat(context),
        child: const Icon(Icons.chat),
      ),
    );
  }

  /// Empty in 3.0. See the class doc.
  List<Widget> get _filterSlot => const [];

  /// "Vikram: " / "You: " in front of a group preview, so a group row
  /// is legible without reading the name (frame a1). DMs get no prefix
  /// — there is only one other person in the room.
  String? _senderPrefix(ChannelListEntry entry, String? localUserId) {
    if (entry.kind != 'group') return null;
    final author = entry.lastMessageAuthor;
    if (author == null) return null;
    if (author == localUserId) return 'You: ';
    final label = _senderLabels[author];
    return label == null ? null : '$label: ';
  }

  AppBar _buildDefaultAppBar(
    BuildContext context,
    WsTransport wsTransport,
    ChatColors chatColors,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      title: StreamBuilder<TransportState>(
        stream: wsTransport.state,
        initialData: wsTransport.currentState,
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
                          color: scheme.onSurface.withValues(alpha: 0.7),
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
        PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'profile') {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    authService: widget.authService,
                    config: widget.config,
                    chatService: widget.chatService,
                  ),
                ),
              );
            } else if (value == 'settings') {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    authService: widget.authService,
                    config: widget.config,
                  ),
                ),
              );
            }
          },
          itemBuilder: (ctx) => [
            _menuItem(
              context,
              value: 'profile',
              icon: Icons.person_outline_rounded,
              label: 'Profile',
            ),
            _menuItem(
              context,
              value: 'settings',
              icon: Icons.settings_outlined,
              label: 'Settings',
            ),
          ],
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: scheme.onSurface,
        );
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurface),
          const SizedBox(width: kSpaceMd),
          Text(label, style: textStyle),
        ],
      ),
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
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ChannelTile({
    super.key,
    required this.entry,
    required this.chatColors,
    required this.displayName,
    this.senderPrefix,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = entry.isMutedAt(DateTime.now().millisecondsSinceEpoch);
    final hasUnread = entry.unreadCount > 0;

    return ListTile(
      leading: Avator(
        text: displayName,
        // Seeded on the id, not the name: renaming a group must not
        // repaint its avatar.
        seed: entry.channelId,
        avatarUrl: entry.avatarUrl,
        isGroup: entry.kind == 'group',
        width: kAvatarMd,
        height: kAvatarMd,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (muted) ...[
            const SizedBox(width: kSpaceXs),
            Icon(
              Icons.notifications_off_outlined,
              size: 14,
              color: scheme.onSurfaceVariant,
              semanticLabel: 'Muted',
            ),
          ],
          if (entry.pinned) ...[
            const SizedBox(width: kSpaceXs),
            Icon(
              Icons.push_pin,
              size: 14,
              color: scheme.onSurfaceVariant,
              semanticLabel: 'Pinned',
            ),
          ],
        ],
      ),
      subtitle: _subtitle(context, scheme, hasUnread),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTime(entry.lastActivityMs),
            style: TextStyle(
              fontSize: 12,
              color: hasUnread && !muted
                  ? chatColors.unreadBadge
                  : scheme.onSurfaceVariant,
            ),
          ),
          if (hasUnread) ...[
            const SizedBox(height: kSpaceXs),
            _UnreadBadge(
              count: entry.unreadCount,
              chatColors: chatColors,
              muted: muted,
            ),
          ],
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
        : entry.lastMessagePreview ?? '';
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

  static String _formatTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days == 0) return DateFormat.jm().format(d);
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
        border: muted
            ? Border.all(color: scheme.outline)
            : null,
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
