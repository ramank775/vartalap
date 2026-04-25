/// New-chat picker — two tabs.
///
/// Contacts tab: pick a contact to start (or resume) a DM.
/// Groups tab: pinned "New group" row at the top, then the list of
/// groups the current user is in. Tap a group to open it (re-enter
/// after clearing messages, or jump into a silent group).
///
/// The chat list shows only channels with messages (active
/// conversations). The Groups tab is the canonical surface for "groups
/// I'm in regardless of message state."
library vartalap.screens.new_chat;

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/group_create/group_create.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

class NewChatScreen extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;
  const NewChatScreen({
    super.key,
    required this.chatService,
    required this.authService,
  });

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  late Future<List<ContactRow>> _contactsFuture;

  @override
  void initState() {
    super.initState();
    _contactsFuture = widget.chatService.discoverContacts();
  }

  void _retryContacts() {
    setState(() {
      _contactsFuture = widget.chatService.discoverContacts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Chat'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Contacts'),
              Tab(text: 'Groups'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ContactsTab(
              contactsFuture: _contactsFuture,
              chatService: widget.chatService,
              authService: widget.authService,
              onRetry: _retryContacts,
            ),
            _GroupsTab(
              chatService: widget.chatService,
              authService: widget.authService,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contacts tab
// ---------------------------------------------------------------------------

class _ContactsTab extends StatefulWidget {
  final Future<List<ContactRow>> contactsFuture;
  final ChatService chatService;
  final AuthService authService;
  final VoidCallback onRetry;

  const _ContactsTab({
    required this.contactsFuture,
    required this.chatService,
    required this.authService,
    required this.onRetry,
  });

  @override
  State<_ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<_ContactsTab> {
  bool _creating = false;

  Future<void> _onContactTap(ContactRow contact) async {
    final localUserId = widget.authService.currentUserId;
    if (localUserId == null) return;
    if (_creating) return;

    setState(() => _creating = true);
    try {
      final channelId = await widget.chatService.startDirectMessage(
        localUserId: localUserId,
        peerUserId: contact.userId,
        peerName: contact.resolvedName,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            channelId: channelId,
            channelName: contact.resolvedName,
            channelKind: 'dm',
            chatService: widget.chatService,
            authService: widget.authService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create chat: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<ContactRow>>(
      future: widget.contactsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(kSpaceLg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.errorContainer,
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 36,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: kSpaceMd),
                  Text(
                    'Could not load contacts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: kSpaceSm),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: kSpaceLg),
                  ElevatedButton.icon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final contacts = snapshot.data ?? [];
        if (contacts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(kSpaceLg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primaryContainer.withValues(alpha: 0.3),
                    ),
                    child: Icon(
                      Icons.people_outline_rounded,
                      size: 48,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: kSpaceMd),
                  Text(
                    'No contacts found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: kSpaceSm),
                  Text(
                    'No other users are registered yet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: contacts.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final contact = contacts[i];
            return _ContactTile(
              contact: contact,
              onTap: _creating ? null : () => _onContactTap(contact),
            );
          },
        );
      },
    );
  }
}

class _ContactTile extends StatelessWidget {
  final ContactRow contact;
  final VoidCallback? onTap;
  const _ContactTile({required this.contact, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = contact.resolvedName;
    final subtitle = contact.username != null ? '@${contact.username}' : null;
    return ListTile(
      leading: Avator(text: name, width: kAvatarMd, height: kAvatarMd),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Groups tab
// ---------------------------------------------------------------------------

class _GroupsTab extends StatelessWidget {
  final ChatService chatService;
  final AuthService authService;

  const _GroupsTab({
    required this.chatService,
    required this.authService,
  });

  void _openGroup(BuildContext context, ChannelListEntry entry) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          channelId: entry.channelId,
          channelName: entry.name ?? entry.channelId,
          channelKind: 'group',
          chatService: chatService,
          authService: authService,
        ),
      ),
    );
  }

  void _newGroup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCreateScreen(
          chatService: chatService,
          authService: authService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final userId = authService.currentUserId;
    if (userId == null) {
      return const Center(child: Text('Not signed in.'));
    }

    return StreamBuilder<List<ChannelListEntry>>(
      stream: chatService.watchMemberChannels(userId: userId, kind: 'group'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final groups = snapshot.data ?? const [];

        return ListView.separated(
          itemCount: groups.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            // Pinned action at the top.
            if (i == 0) {
              return ListTile(
                leading: CircleAvatar(
                  radius: kAvatarMd / 2,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.group_add,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                title: const Text('New group'),
                onTap: () => _newGroup(context),
              );
            }
            final group = groups[i - 1];
            return _GroupTile(
              entry: group,
              onTap: () => _openGroup(context, group),
            );
          },
        );
      },
    );
  }
}

class _GroupTile extends StatelessWidget {
  final ChannelListEntry entry;
  final VoidCallback onTap;
  const _GroupTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = entry.name ?? entry.channelId;
    return ListTile(
      leading: Avator(text: name, width: kAvatarMd, height: kAvatarMd),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
