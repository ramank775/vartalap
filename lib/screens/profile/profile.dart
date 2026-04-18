/// User profile screen — shows current user info and app settings.
library vartalap.screens.profile;

import 'package:flutter/material.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';

class ProfileScreen extends StatelessWidget {
  final AuthService authService;
  final ConfigStore config;

  const ProfileScreen({
    super.key,
    required this.authService,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final phone = authService.phoneNumber ?? 'Unknown';
    final userId = authService.currentUserId ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: kSpaceXl),
          // Profile header
          Center(
            child: Column(
              children: [
                Avator(
                  text: phone,
                  width: kAvatarXl,
                  height: kAvatarXl,
                ),
                const SizedBox(height: kSpaceMd),
                Text(
                  phone,
                  style: textTheme.headlineSmall,
                ),
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
          // Settings section
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kSpaceMd,
              vertical: kSpaceSm,
            ),
            child: Text(
              'Settings',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.primary,
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Message and call notifications',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.lock_outline,
            title: 'Privacy',
            subtitle: 'Last seen, profile photo',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Theme, font size',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.storage_outlined,
            title: 'Storage and data',
            subtitle: 'Manage storage',
            onTap: () {},
          ),
          const Divider(),
          // App info section
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kSpaceMd,
              vertical: kSpaceSm,
            ),
            child: Text(
              'About',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.primary,
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.info_outline,
            title: config.packageInfo.appName,
            subtitle:
                'v${config.packageInfo.version}+${config.packageInfo.buildNumber}',
            onTap: () {},
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms and Privacy Policy',
            onTap: () {},
          ),
          const Divider(),
          // Sign out
          ListTile(
            leading: Icon(
              Icons.logout,
              color: scheme.error,
            ),
            title: Text(
              'Sign out',
              style: TextStyle(color: scheme.error),
            ),
            onTap: () => _confirmSignOut(context),
          ),
          const SizedBox(height: kSpaceXl),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to verify your phone number again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await authService.logout();
            },
            child: Text(
              'Sign out',
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(title),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
