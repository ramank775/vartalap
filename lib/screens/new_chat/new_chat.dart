/// Contact picker for starting a new DM conversation.
///
/// Calls [ChatService.discoverContacts] to fetch known users from the
/// server, displays them in a list, and on tap creates (or resumes) a
/// DM channel via [ChatService.startDirectMessage].
library vartalap.screens.new_chat;

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
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
      // Replace this screen with the chat screen.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            channelId: channelId,
            channelName: contact.resolvedName,
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
    return Scaffold(
      appBar: AppBar(title: const Text('New Chat')),
      body: FutureBuilder<List<ContactRow>>(
        future: _contactsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load contacts',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _contactsFuture =
                              widget.chatService.discoverContacts();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final contacts = snapshot.data ?? [];
          if (contacts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline, size: 64),
                    SizedBox(height: 12),
                    Text(
                      'No contacts found',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'No other users are registered yet.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: contacts.length,
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
      leading: Avator(text: name, width: 42, height: 42),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle != null
          ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      onTap: onTap,
    );
  }
}
