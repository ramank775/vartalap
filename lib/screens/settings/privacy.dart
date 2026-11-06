/// Settings › Privacy's presence rows (decision 223, track F): who sees
/// your last seen and online, and the read receipts and typing switches,
/// in WhatsApp's words.
library vartalap.screens.settings.privacy;

import 'package:flutter/material.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';

/// The server's values and how the page says them.
const Map<String, String> kPresenceLabels = {
  'everyone': 'Everyone',
  'contacts': 'My contacts',
  'nobody': 'Nobody',
};

class PresencePrivacyRows extends StatefulWidget {
  final AuthService authService;
  final ChatService chatService;

  const PresencePrivacyRows({
    super.key,
    required this.authService,
    required this.chatService,
  });

  @override
  State<PresencePrivacyRows> createState() => _PresencePrivacyRowsState();
}

class _PresencePrivacyRowsState extends State<PresencePrivacyRows> {
  /// Null while loading; the server holds it (SYNC_PROTOCOL §21).
  String? _presence;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final value = await widget.authService.presenceSetting();
      if (mounted) setState(() => _presence = value);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _pickPresence() async {
    if (_presence == null) {
      if (_loadFailed) await _load();
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Last seen and online'),
        children: [
          RadioGroup<String>(
            groupValue: _presence,
            onChanged: (value) => Navigator.of(ctx).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final MapEntry(:key, :value) in kPresenceLabels.entries)
                  RadioListTile<String>(title: Text(value), value: key),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              "If you don't share your last seen and online, you won't be "
              "able to see other people's last seen and online.",
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == _presence) return;
    try {
      await widget.authService.setPresenceSetting(picked);
      if (mounted) setState(() => _presence = picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text("Couldn't change it. Check your connection and try again."),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chatService;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: const Text('Last seen and online'),
          subtitle: Text(_loadFailed
              ? "Couldn't load, tap to try again"
              : kPresenceLabels[_presence] ?? 'Loading…'),
          onTap: _pickPresence,
        ),
        const Divider(height: 1),
        ValueListenableBuilder<bool>(
          valueListenable: chat.readReceipts,
          builder: (context, on, _) => SwitchListTile(
            title: const Text('Read receipts'),
            subtitle: const Text(
              "If you turn off read receipts, you won't be able to see "
              'read receipts from other people. Read receipts are always '
              'sent for group chats.',
            ),
            value: on,
            onChanged: chat.setReadReceipts,
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: chat.typingIndicator,
          builder: (context, on, _) => SwitchListTile(
            title: const Text('Typing indicator'),
            subtitle: const Text(
              "If you turn this off, others won't see when you are typing, "
              "and you won't see when they are.",
            ),
            value: on,
            onChanged: chat.setTypingIndicator,
          ),
        ),
      ],
    );
  }
}
