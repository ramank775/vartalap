/// User profile screen — shows current user identity.
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
        ],
      ),
    );
  }
}
