import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  // Mock state for now
  bool _readReceipts = true;
  String _lastSeenVisibility = 'Everyone';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Account & Privacy',
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
            child: Text('Privacy', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            title: const Text('Read Receipts'),
            subtitle: const Text('If turned off, you won\'t send or receive read receipts.'),
            value: _readReceipts,
            onChanged: (bool value) {
              setState(() {
                _readReceipts = value;
              });
              // TODO: Sync to backend/local storage
            },
          ),
          ListTile(
            title: const Text('Last Seen Visibility'),
            subtitle: Text(_lastSeenVisibility),
            onTap: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (context) {
                  return SimpleDialog(
                    title: const Text('Last Seen Visibility'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'Everyone'),
                        child: const Text('Everyone'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'My Contacts'),
                        child: const Text('My Contacts'),
                      ),
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, 'Nobody'),
                        child: const Text('Nobody'),
                      ),
                    ],
                  );
                },
              );
              
              if (result != null) {
                setState(() {
                  _lastSeenVisibility = result;
                });
                // TODO: Sync to backend/local storage
              }
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Blocked Contacts'),
            subtitle: const Text('0 contacts'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Blocked contacts UI coming soon')),
              );
            },
          ),
        ],
      ),
    );
  }
}
