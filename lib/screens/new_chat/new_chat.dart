/// Contact picker for starting a new DM conversation.
library vartalap.screens.new_chat;

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat/chat.dart';
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
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _contactsFuture = widget.chatService.discoverContacts();
  }

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Chat'),
      ),
      body: FutureBuilder<List<ContactRow>>(
        future: _contactsFuture,
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
                      onPressed: () {
                        setState(() {
                          _contactsFuture =
                              widget.chatService.discoverContacts();
                        });
                      },
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
      ),
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
