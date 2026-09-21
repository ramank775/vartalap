/// Contact info for another user — mockup frame g.
///
/// Name, handle, status, Message, shared groups. **No phone row**: the
/// client never holds another user's number (AUTH_CONTRACT §2.5) and
/// the design is explicit that a number you do not hold must not appear
/// here.
library vartalap.screens.contact_info;

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

class ContactInfoScreen extends StatefulWidget {
  final ContactRow contact;
  final ChatService chatService;
  final AuthService authService;

  const ContactInfoScreen({
    super.key,
    required this.contact,
    required this.chatService,
    required this.authService,
  });

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  late Future<List<ChannelListEntry>> _sharedGroups;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _sharedGroups = _loadSharedGroups();
  }

  /// Groups this contact and I are both in.
  ///
  /// ponytail: one membership query per group of mine. A person is in
  /// tens of groups, not thousands; make it a single JOIN in the store
  /// if that ever stops being true.
  Future<List<ChannelListEntry>> _loadSharedGroups() async {
    final me = widget.authService.currentUserId;
    if (me == null) return const [];
    final mine = await widget.chatService
        .fetchMemberChannels(userId: me, kind: 'group');
    final shared = <ChannelListEntry>[];
    for (final g in mine) {
      final members =
          await widget.chatService.fetchChannelMembers(g.channelId);
      if (members.any((m) => m.userId == widget.contact.userId)) {
        shared.add(g);
      }
    }
    return shared;
  }

  Future<void> _onMessage() async {
    final me = widget.authService.currentUserId;
    if (me == null || _opening) return;
    setState(() => _opening = true);
    try {
      final channelId = await widget.chatService.startDirectMessage(
        localUserId: me,
        peerUserId: widget.contact.userId,
        peerName: widget.contact.displayLabel,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            channelId: channelId,
            channelName: widget.contact.displayLabel,
            channelKind: 'one_to_one',
            chatService: widget.chatService,
            authService: widget.authService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the chat: $e')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _openGroup(ChannelListEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          channelId: entry.channelId,
          channelName: entry.title,
          channelKind: 'group',
          chatService: widget.chatService,
          authService: widget.authService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final contact = widget.contact;
    final label = contact.displayLabel;

    return Scaffold(
      appBar: AppBar(title: const Text('Contact info')),
      body: ListView(
        children: [
          const SizedBox(height: kSpaceLg),
          Center(
            child: Column(
              children: [
                Avator(text: label, width: kAvatarXl, height: kAvatarXl),
                const SizedBox(height: kSpaceMd),
                Text(label, style: text.headlineSmall),
                if (contact.username != null)
                  Text(
                    '@${contact.username}',
                    style:
                        text.titleMedium?.copyWith(color: scheme.primary),
                  ),
                if (contact.statusText != null &&
                    contact.statusText!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: kSpaceXs),
                    child: Text(
                      contact.statusText!,
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: kSpaceLg),
          Center(
            child: FilledButton.icon(
              onPressed: _opening ? null : _onMessage,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Message'),
            ),
          ),
          const SizedBox(height: kSpaceSm),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: kSpaceXs),
                Text(
                  'Their number is not shown here',
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: kSpaceMd),
          const Divider(height: 1),
          FutureBuilder<List<ChannelListEntry>>(
            future: _sharedGroups,
            builder: (context, snapshot) {
              final groups = snapshot.data ?? const <ChannelListEntry>[];
              if (groups.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        kSpaceMd, kSpaceMd, kSpaceMd, kSpaceSm),
                    child: Text(
                      groups.length == 1
                          ? '1 group in common'
                          : '${groups.length} groups in common',
                      style: text.titleSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  for (final g in groups)
                    ListTile(
                      leading: Avator(
                        text: g.title,
                        width: kAvatarSm,
                        height: kAvatarSm,
                      ),
                      title: Text(g.title),
                      onTap: () => _openGroup(g),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
