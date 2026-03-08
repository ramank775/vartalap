import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: VartalapTheme.theme.appTitleStyle.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Account & Privacy'),
            subtitle: const Text('Read receipts, last seen, blocked contacts'),
            onTap: () {
              Navigator.pushNamed(context, '/settings/privacy');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            subtitle: const Text('Message tones, vibration'),
            onTap: () {
              Navigator.pushNamed(context, '/settings/notifications');
            },
          ),
        ],
      ),
    );
  }
}
