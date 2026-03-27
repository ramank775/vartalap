import 'package:flutter/material.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/chat_preview.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ForwardMessagesScreen extends StatefulWidget {
  final List<ChatMessage> messagesToForward;

  const ForwardMessagesScreen({
    Key? key,
    required this.messagesToForward,
  }) : super(key: key);

  @override
  State<ForwardMessagesScreen> createState() => _ForwardMessagesScreenState();
}

class _ForwardMessagesScreenState extends State<ForwardMessagesScreen> {
  final List<ChatPreview> _selectedChats = [];
  bool _isForwarding = false;

  void _toggleChatSelection(ChatPreview chat) {
    setState(() {
      if (_selectedChats.contains(chat)) {
        _selectedChats.remove(chat);
      } else {
        // Limit to forwarding to a max of 5 chats at once to avoid spamming
        if (_selectedChats.length < 5) {
          _selectedChats.add(chat);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You can only forward to up to 5 chats at a time.')),
          );
        }
      }
    });
  }

  Future<void> _forwardMessages() async {
    if (_selectedChats.isEmpty) return;

    setState(() {
      _isForwarding = true;
    });

    final client = context.read<VartalapChatClientFlutter>();
    final currentUser = CurrentUser.of(context).user!;
    int successCount = 0;

    try {
      for (final chat in _selectedChats) {
        // We need to create a new message specifically for this channel, carrying the content over
        // True "forwarding" typically includes a header like "Forwarded", but for simplicity here we just send the content
        final messages = widget.messagesToForward.map((originalMsg) {
          return ChatMessage.text(
            channelId: chat.channel.id,
            senderId: currentUser.id,
            text: originalMsg.text,
            // If the original message was an attachment, we would need to handle that,
            // but for now we focus on text.
          ).copyWith(sender: currentUser);
        }).toList();

        final chatClient = await client.chat(channel: chat.channel, currentUser: currentUser);
        await chatClient.sendMessage(messages);
        successCount++;
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Messages forwarded to $successCount chat(s).')),
        );
        Navigator.pop(context);
        // Also pop the chat selection if needed, but since we pushed, popping once is enough to return to the chat
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to forward messages: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isForwarding = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = context.read<VartalapChatClientFlutter>();
    final currentUser = CurrentUser.of(context).user!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Forward to...',
          style: VartalapTheme.theme.appTitleStyle.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: StreamBuilder<List<ChatPreview>>(
        stream: client.watchChatPreviews(currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error loading chats: ${snapshot.error}'));
          }

          final chats = snapshot.data ?? [];
          if (chats.isEmpty) {
            return const Center(child: Text('No chats available.'));
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              return ChatPreviewWidget(
                chat,
                (selectedChat) => _toggleChatSelection(selectedChat),
                (selectedChat) => _toggleChatSelection(selectedChat),
                isSelected: _selectedChats.contains(chat),
              );
            },
          );
        },
      ),
      floatingActionButton: _selectedChats.isNotEmpty
          ? FloatingActionButton(
              onPressed: _isForwarding ? null : _forwardMessages,
              child: _isForwarding
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.send),
            )
          : null,
    );
  }
}
