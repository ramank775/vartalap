/// Chat info screen — shows channel details, members, and actions.
///
/// Works for both DM and group channels. DM shows the peer's info;
/// group shows member list with admin controls.
library vartalap.screens.chat_info;

import 'package:flutter/material.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';

class ChatInfoScreen extends StatelessWidget {
  final String channelId;
  final String channelName;
  final ChatService chatService;

  const ChatInfoScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.chatService,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Info'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: kSpaceXl),
          // Avatar + name header
          Center(
            child: Column(
              children: [
                Avator(
                  text: channelName,
                  width: kAvatarXl,
                  height: kAvatarXl,
                ),
                const SizedBox(height: kSpaceMd),
                Text(
                  channelName,
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: kSpaceXs),
                Text(
                  'Direct message',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: kSpaceXl),
          const Divider(),
          // Actions
          _InfoTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'On',
            onTap: () {},
          ),
          _InfoTile(
            icon: Icons.image_outlined,
            title: 'Media, links, and docs',
            subtitle: 'None',
            onTap: () {},
          ),
          _InfoTile(
            icon: Icons.search,
            title: 'Search in conversation',
            onTap: () {},
          ),
          const Divider(),
          // Danger zone
          _InfoTile(
            icon: Icons.block,
            title: 'Block',
            iconColor: scheme.error,
            titleColor: scheme.error,
            onTap: () {},
          ),
          _InfoTile(
            icon: Icons.delete_outline,
            title: 'Delete chat',
            iconColor: scheme.error,
            titleColor: scheme.error,
            onTap: () {
              _confirmDelete(context);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text(
          'This will delete all messages in this chat from your device. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: implement chatService.deleteChannel(channelId)
              Navigator.of(context).pop();
            },
            child: Text(
              'Delete',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Color? titleColor;
  final VoidCallback onTap;

  const _InfoTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? scheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: TextStyle(color: titleColor),
      ),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
