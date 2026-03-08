import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  // Mock state
  bool _conversationTones = true;
  String _vibrate = 'Default';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: VartalapTheme.theme.appTitleStyle.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Messages', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            title: const Text('Conversation Tones'),
            subtitle: const Text('Play sounds for incoming and outgoing messages.'),
            value: _conversationTones,
            onChanged: (bool value) {
              setState(() {
                _conversationTones = value;
              });
            },
          ),
          ListTile(
            title: const Text('Notification Tone'),
            subtitle: const Text('Default (ringtone)'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ringtone picker not implemented yet')),
              );
            },
          ),
          ListTile(
            title: const Text('Vibrate'),
            subtitle: Text(_vibrate),
            onTap: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (context) {
                  return SimpleDialog(
                    title: const Text('Vibrate'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'Off'),
                        child: const Text('Off'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'Default'),
                        child: const Text('Default'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'Short'),
                        child: const Text('Short'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'Long'),
                        child: const Text('Long'),
                      ),
                    ],
                  );
                },
              );
              
              if (result != null) {
                setState(() {
                  _vibrate = result;
                });
              }
            },
          ),
        ],
      ),
    );
  }
}
