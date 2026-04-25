/// Chat list — reactive over `chatService.watchChannels()`.
library vartalap.screens.chats.chats;

import 'package:flutter/material.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/group_create/group_create.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/screens/profile/profile.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/Inherited/app_services.dart';
import 'package:vartalap/widgets/rich_message.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

class ChatsScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final wsTransport = AppServicesProvider.of(context).services.wsTransport;
    final scheme = Theme.of(context).colorScheme;
    final chatColors = VartalapTheme.chatColorsOf(context);

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<TransportState>(
          stream: wsTransport.state,
          initialData: wsTransport.currentState,
          builder: (context, snapshot) {
            final state = snapshot.data ?? TransportState.disconnected;
            return Row(
              children: [
                // Connectivity dot
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
                      Text(config.packageInfo.appName),
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
              if (value == 'new_group') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupCreateScreen(
                      chatService: chatService,
                      authService: authService,
                    ),
                  ),
                );
              } else if (value == 'profile') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      authService: authService,
                      config: config,
                    ),
                  ),
                );
              } else if (value == 'about') {
                _showAbout(context);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                  value: 'new_group', child: Text('New group')),
              const PopupMenuItem(value: 'profile', child: Text('Profile')),
              const PopupMenuItem(value: 'about', child: Text('About')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<ChannelListEntry>>(
        stream: chatService.watchChannels(),
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
              return _ChannelTile(
                entry: entry,
                chatColors: chatColors,
                onTap: () => _openChat(context, entry),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _newChat(context),
        child: const Icon(Icons.chat),
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
          chatService: chatService,
          authService: authService,
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
          chatService: chatService,
          authService: authService,
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: config.packageInfo.appName,
      applicationIcon: const AppLogo(size: 25),
      applicationVersion:
          '${config.packageInfo.version}+${config.packageInfo.buildNumber}',
      children: [
        Text(config.subtitle),
        const SizedBox(height: kSpaceSm),
        RichMessage(
          'Vartalap v3 — a greenfield relaunch, Firebase-free.',
          TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      ],
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
  final VoidCallback onTap;
  const _ChannelTile({
    required this.entry,
    required this.chatColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayName = entry.name ?? entry.channelId;
    final preview = entry.lastMessageTombstoned
        ? '(message deleted)'
        : entry.lastMessagePreview ?? '';
    final hasUnread = entry.unreadCount > 0;

    return ListTile(
      leading: Avator(text: displayName, width: kAvatarMd, height: kAvatarMd),
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
    );
  }
}
