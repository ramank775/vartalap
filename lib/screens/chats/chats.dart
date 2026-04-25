/// Chat list — reactive over `chatService.watchChannels()`.
library vartalap.screens.chats.chats;

import 'package:flutter/material.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/screens/profile/profile.dart';
import 'package:vartalap/screens/settings/settings.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
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
  /// Channel ids currently selected. Non-empty = selection mode.
  final Set<String> _selected = {};

  bool get _selectionMode => _selected.isNotEmpty;

  void _exitSelection() => setState(_selected.clear);

  void _toggleSelection(String channelId) {
    setState(() {
      if (!_selected.remove(channelId)) _selected.add(channelId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wsTransport = AppServicesProvider.of(context).services.wsTransport;
    final chatColors = VartalapTheme.chatColorsOf(context);

    // Intercept system back while in selection mode so it cancels the
    // selection rather than leaving the chat list.
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectionMode) _exitSelection();
      },
      child: Scaffold(
        appBar: _selectionMode
            ? _buildSelectionAppBar(context)
            : _buildDefaultAppBar(context, wsTransport, chatColors),
        body: StreamBuilder<List<ChannelListEntry>>(
          stream: widget.chatService.watchChannels(),
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
            // Cull selection ids that are no longer in the list (e.g.,
            // a parallel clear from another screen). Keeps the count
            // accurate without an explicit refresh.
            final visibleIds = channels.map((c) => c.channelId).toSet();
            _selected.removeWhere((id) => !visibleIds.contains(id));
            return ListView.separated(
              itemCount: channels.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final entry = channels[i];
                final selected = _selected.contains(entry.channelId);
                return _ChannelTile(
                  entry: entry,
                  chatColors: chatColors,
                  selected: selected,
                  onTap: () {
                    if (_selectionMode) {
                      _toggleSelection(entry.channelId);
                    } else {
                      _openChat(context, entry);
                    }
                  },
                  onLongPress: () => _toggleSelection(entry.channelId),
                );
              },
            );
          },
        ),
        floatingActionButton: _selectionMode
            ? null
            : FloatingActionButton(
                onPressed: () => _newChat(context),
                child: const Icon(Icons.chat),
              ),
      ),
    );
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
          itemBuilder: (ctx) => const [
            PopupMenuItem(value: 'profile', child: Text('Profile')),
            PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 20),
                  SizedBox(width: kSpaceSm),
                  Text('Settings'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelection,
        tooltip: 'Cancel',
      ),
      title: Text('${_selected.length}'),
      actions: [
        IconButton(
          icon: const Icon(Icons.cleaning_services_outlined),
          tooltip: 'Clear messages',
          onPressed: _confirmClearSelected,
        ),
      ],
    );
  }

  void _confirmClearSelected() {
    final count = _selected.length;
    if (count == 0) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(count == 1 ? 'Clear messages?' : 'Clear $count chats?'),
        content: Text(
          count == 1
              ? 'All messages in this chat will be removed from this device. '
                  'The contact or group stays in your list.'
              : 'All messages in the selected chats will be removed from '
                  'this device. The contacts and groups stay in your list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final ids = _selected.toList();
              _exitSelection();
              try {
                for (final id in ids) {
                  await widget.chatService.clearMessages(id);
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not clear messages: $e')),
                );
              }
            },
            child: Text(
              'Clear',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
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
        return 'Connecting\u2026';
      case TransportState.disconnected:
        return 'Waiting for network\u2026';
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
          channelName: entry.name ?? entry.channelId,
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

class _ChannelTile extends StatelessWidget {
  final ChannelListEntry entry;
  final ChatColors chatColors;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _ChannelTile({
    required this.entry,
    required this.chatColors,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayName = entry.name ?? entry.channelId;
    final preview = entry.lastMessageTombstoned
        ? '(message deleted)'
        : entry.lastMessagePreview ?? '';
    final hasUnread = entry.unreadCount > 0;

    // Selected: avatar overlaid with a primary check, tile tinted.
    final Widget leading = selected
        ? Stack(
            children: [
              Avator(
                text: displayName,
                width: kAvatarMd,
                height: kAvatarMd,
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.85),
                  ),
                  child: Icon(
                    Icons.check,
                    color: scheme.onPrimary,
                    size: kAvatarMd * 0.55,
                  ),
                ),
              ),
            ],
          )
        : Avator(text: displayName, width: kAvatarMd, height: kAvatarMd);

    return ListTile(
      tileColor:
          selected ? scheme.primaryContainer.withValues(alpha: 0.25) : null,
      leading: leading,
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontStyle: entry.lastMessageTombstoned
              ? FontStyle.italic
              : FontStyle.normal,
          color: hasUnread
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      trailing: hasUnread
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: kSpaceSm,
                vertical: kSpaceXs,
              ),
              constraints: const BoxConstraints(minWidth: 24),
              decoration: BoxDecoration(
                color: chatColors.unreadBadge,
                borderRadius: BorderRadius.circular(kRadiusFull),
              ),
              child: Text(
                '${entry.unreadCount}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: chatColors.unreadBadgeText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
