/// Contact info screen — shows details about a contact.
library vartalap.screens.contact_info;

import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';

class ContactInfoScreen extends StatelessWidget {
  final String name;
  final String userId;
  final String? username;

  const ContactInfoScreen({
    super.key,
    required this.name,
    required this.userId,
    this.username,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Info'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: kSpaceXl),
          // Contact header
          Center(
            child: Column(
              children: [
                Avator(
                  text: name,
                  width: kAvatarXl,
                  height: kAvatarXl,
                ),
                const SizedBox(height: kSpaceMd),
                Text(name, style: textTheme.headlineSmall),
                if (username != null) ...[
                  const SizedBox(height: kSpaceXs),
                  Text(
                    '@$username',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: kSpaceXs),
                Text(
                  'User ID: $userId',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: kSpaceXl),
          const Divider(),
          // Actions
          _ActionTile(
            icon: Icons.chat_outlined,
            title: 'Message',
            onTap: () {
              // Pop back to trigger the DM creation flow.
              Navigator.of(context).pop();
            },
          ),
          _ActionTile(
            icon: Icons.phone_outlined,
            title: 'Voice call',
            subtitle: 'Coming soon',
            enabled: false,
            onTap: () {},
          ),
          _ActionTile(
            icon: Icons.videocam_outlined,
            title: 'Video call',
            subtitle: 'Coming soon',
            enabled: false,
            onTap: () {},
          ),
          const Divider(),
          _ActionTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Default',
            onTap: () {},
          ),
          _ActionTile(
            icon: Icons.image_outlined,
            title: 'Shared media',
            subtitle: 'None',
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.block, color: scheme.error),
            title: Text('Block', style: TextStyle(color: scheme.error)),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = enabled ? scheme.onSurfaceVariant : scheme.outlineVariant;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? null : scheme.outlineVariant,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: color))
          : null,
      trailing: const Icon(Icons.chevron_right),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}
