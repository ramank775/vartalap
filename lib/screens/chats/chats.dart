/// Chat list — reactive over `chatService.watchChannels()`.
library vartalap.screens.chats.chats;

import 'package:flutter/material.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/rich_message.dart';
import 'package:vartalap_store/vartalap_store.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          config.packageInfo.appName,
          style: VartalapTheme.theme.appTitleStyle.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'about') {
                _showAbout(context);
              } else if (value == 'logout') {
                await authService.logout();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'about', child: Text('About')),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
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
          return ListView.builder(
            itemCount: channels.length,
            itemBuilder: (ctx, i) {
              final entry = channels[i];
              return _ChannelTile(
                entry: entry,
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
        const SizedBox(height: 8),
        RichMessage(
          // v3 description reflects the relaunch posture.
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 64),
            const SizedBox(height: 12),
            const Text(
              'No chats yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Text(
              'New-chat flow lands once contact discovery is wired.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
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
  final VoidCallback onTap;
  const _ChannelTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final displayName = entry.name ?? entry.channelId;
    final preview = entry.lastMessageTombstoned
        ? '(message deleted)'
        : entry.lastMessagePreview ?? '';
    return ListTile(
      leading: Avator(text: displayName, width: 42, height: 42),
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontStyle: entry.lastMessageTombstoned
              ? FontStyle.italic
              : FontStyle.normal,
        ),
      ),
      trailing: entry.unreadCount > 0
          ? CircleAvatar(
              radius: 12,
              backgroundColor: Theme.of(context).iconTheme.color,
              child: Text(
                '${entry.unreadCount}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
