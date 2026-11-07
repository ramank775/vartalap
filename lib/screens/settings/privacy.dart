/// Settings › Privacy's presence rows (decision 223, track F): who sees
/// your last seen and online (everyone, contacts, nobody, or by label:
/// "My contacts except…", "Only share with…"), and the read receipts and
/// typing switches, in WhatsApp's words; and its Blocked contacts
/// (decision 219).
library vartalap.screens.settings.privacy;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vartalap/screens/invites/invites.dart';
import 'package:vartalap/screens/labels/labels.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/compact_tiles.dart';
import 'package:vartalap_store/vartalap_store.dart';

/// The server's values and how the page says them, in the picker's
/// order (WhatsApp's, plus its "Only share with…").
const Map<String, String> kPresenceLabels = {
  'everyone': 'Everyone',
  'contacts': 'My contacts',
  'except': 'My contacts except…',
  'only': 'Only share with…',
  'nobody': 'Nobody',
};

/// The two settings that name people, by label.
const Set<String> kPresenceByLabel = {'only', 'except'};

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
  /// Null while loading; the server holds it (SYNC_PROTOCOL §22).
  String? _presence;
  bool _loadFailed = false;

  /// The labels behind `only` / `except`, saved on this phone only.
  Set<int> _picked = const {};
  List<Label> _labels = const [];
  StreamSubscription<List<Label>>? _labelsSub;

  @override
  void initState() {
    super.initState();
    _labelsSub = widget.chatService
        .watchLabels()
        .listen((labels) => setState(() => _labels = labels));
    _load();
  }

  @override
  void dispose() {
    _labelsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final value = await widget.authService.presenceSetting();
      final saved = await widget.chatService.presenceLabels();
      if (mounted) {
        setState(() {
          _presence = value;
          _picked = saved?.labels ?? const {};
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  /// "Only share with Family, Close": the picked labels that still exist.
  String _subtitle() {
    if (_loadFailed) return "Couldn't load, tap to try again";
    final presence = _presence;
    if (presence == null) return 'Loading…';
    final names = [
      for (final l in _labels)
        if (_picked.contains(l.labelId)) l.name
    ];
    final label = kPresenceLabels[presence] ?? presence;
    if (!kPresenceByLabel.contains(presence) || names.isEmpty) return label;
    return '${label.substring(0, label.length - 1)} ${names.join(', ')}';
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
            // null: the picked "only" / "except" again, to change labels
            onChanged: (value) => Navigator.of(ctx).pop(value ?? _presence),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final MapEntry(:key, :value) in kPresenceLabels.entries)
                  RadioListTile<String>(
                    title: Text(value),
                    value: key,
                    toggleable: kPresenceByLabel.contains(key),
                  ),
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
    if (picked == null || !mounted) return;
    Set<int>? labelIds;
    if (kPresenceByLabel.contains(picked)) {
      labelIds = await showDialog<Set<int>>(
        context: context,
        builder: (_) => LabelPicker(
          title: kPresenceLabels[picked]!.replaceAll('…', ''),
          labels: _labels,
          initial: picked == _presence ? _picked : const {},
          onManage: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => LabelsScreen(chatService: widget.chatService))),
        ),
      );
      // ponytail: no labels picked is a cancel, not "share with nobody";
      // Nobody is its own row.
      if (labelIds == null || labelIds.isEmpty) return;
    } else if (picked == _presence) {
      return;
    }
    try {
      await widget.chatService.setPresence(picked, labelIds);
      if (mounted) {
        setState(() {
          _presence = picked;
          _picked = labelIds ?? const {};
        });
      }
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
          subtitle: Text(_subtitle()),
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
        ValueListenableBuilder<bool>(
          valueListenable: chat.linkPreviews,
          builder: (context, on, _) => SwitchListTile(
            title: const Text('Link previews'),
            subtitle: const Text(
              "Your phone fetches the preview; people you send it to don't "
              'contact the website.',
            ),
            value: on,
            onChanged: chat.setLinkPreviews,
          ),
        ),
      ],
    );
  }
}

/// Settings › Privacy's Blocked contacts (decision 219), with the count.
class BlockedContactsRow extends StatelessWidget {
  final ChatService chatService;
  const BlockedContactsRow({super.key, required this.chatService});

  @override
  Widget build(BuildContext context) => StreamBuilder<Set<String>>(
        stream: chatService.watchBlocked(),
        builder: (context, snap) {
          final n = snap.data?.length ?? 0;
          return ListTile(
            leading: Icon(Icons.block,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            title: const Text('Blocked contacts'),
            subtitle: Text(n == 0 ? 'None' : '$n'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => BlockedScreen(chatService: chatService))),
          );
        },
      );
}

/// Everyone we blocked; Unblock lets their messages and invites in again.
class BlockedScreen extends StatefulWidget {
  final ChatService chatService;
  const BlockedScreen({super.key, required this.chatService});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  late final Stream<(Set<String>, Map<String, String>)> _blocked =
      widget.chatService.watchBlocked().asyncMap((blocked) async {
    final contacts = await widget.chatService.discoverContacts();
    return (blocked, {for (final c in contacts) c.userId: c.displayLabel});
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked contacts')),
      body: StreamBuilder<(Set<String>, Map<String, String>)>(
        stream: _blocked,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final (blocked, names) = data;
          if (blocked.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(kSpaceXl),
                child: Text(
                  'Nobody is blocked. Blocked contacts cannot message you '
                  'or send you invites.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return compactTiles(ListView(children: [
            for (final userId in blocked)
              ListTile(
                leading: Avator(
                  text: names[userId] ?? 'Unknown',
                  seed: personSeed(context, userId),
                  width: kAvatarMd,
                  height: kAvatarMd,
                ),
                title: Text(names[userId] ?? 'Unknown'),
                trailing: TextButton(
                  onPressed: () async {
                    try {
                      await widget.chatService.setBlocked(userId, false);
                    } catch (e) {
                      if (context.mounted) showInviteError(context, e);
                    }
                  },
                  child: const Text('Unblock'),
                ),
              ),
          ]));
        },
      ),
    );
  }
}
