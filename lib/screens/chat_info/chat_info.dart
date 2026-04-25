/// Chat info screen — shows channel details, members, and actions.
///
/// Branches on channel `kind` for the destructive action: groups get
/// "Leave group" (drops channel + membership), DMs get "Clear messages"
/// (wipes messages, keeps channel — DM channels must remain unique per
/// user pair to keep the address stable for incoming peer messages).
library vartalap.screens.chat_info;

import 'package:flutter/material.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';

class ChatInfoScreen extends StatelessWidget {
  final String channelId;
  final String channelName;
  final String channelKind; // 'dm' | 'group'
  final ChatService chatService;

  const ChatInfoScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.channelKind,
    required this.chatService,
  });

  bool get _isGroup => channelKind == 'group';

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
          Center(
            child: Column(
              children: [
                Avator(
                  text: channelName,
                  width: kAvatarXl,
                  height: kAvatarXl,
                ),
                const SizedBox(height: kSpaceMd),
                Text(channelName, style: textTheme.headlineSmall),
                const SizedBox(height: kSpaceXs),
                Text(
                  _isGroup ? 'Group' : 'Direct message',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: kSpaceXl),
          const Divider(),
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
          _InfoTile(
            icon: Icons.cleaning_services_outlined,
            title: 'Clear messages',
            iconColor: scheme.error,
            titleColor: scheme.error,
            onTap: () => _confirmClear(context),
          ),
          if (_isGroup)
            _InfoTile(
              icon: Icons.exit_to_app,
              title: 'Leave group',
              iconColor: scheme.error,
              titleColor: scheme.error,
              onTap: () => _confirmLeave(context),
            ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear messages?'),
        content: Text(
          _isGroup
              ? 'All messages in this group will be removed from this device. '
                  'You’ll stay in the group and can find it under Groups.'
              : 'All messages with this contact will be removed from this device. '
                  'The contact stays in your contacts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await chatService.clearMessages(channelId);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not clear messages: $e')),
                );
                return;
              }
              if (!context.mounted) return;
              Navigator.of(context).pop();
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

  void _confirmLeave(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text(
          'You’ll stop receiving messages from this group. '
          'Someone will need to add you back to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await chatService.leaveGroup(channelId);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not leave group: $e')),
                );
                return;
              }
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            child: Text(
              'Leave',
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
