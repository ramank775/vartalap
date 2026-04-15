/// Chat screen — reactive over `chatService.watchMessages(channelId)`.
///
/// Bare-bones: one reversed ListView for the message log, a TextField
/// + send button below. On entry the screen calls
/// `chatService.markRead(channelId)` (§10 local read marker). On send,
/// `chatService.sendMessage(...)` enqueues the outbound op and the
/// store stream surfaces the new pending row automatically.
///
/// v2's rich features (reactions, typing indicator, read receipts,
/// message selection + delete) are intentionally left out — they
/// re-land as the corresponding op kinds are added to `vartalap_sync`.
library vartalap.screens.chat.chat;

import 'package:flutter/material.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

class ChatScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  final ChatService chatService;
  final AuthService authService;

  const ChatScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.chatService,
    required this.authService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: the read-marker write is a cheap single-row
    // transaction. If it fails (rare), unread_count stays stale until
    // the next open — acceptable.
    widget.chatService.markRead(widget.channelId);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _onSend() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    final userId = widget.authService.currentUserId;
    if (userId == null) {
      // Session vanished mid-session (token revoked, logged out in
      // another tab). main.dart's authStateChange listener will swap
      // the route; in the meantime don't attempt the send.
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.chatService.sendMessage(
        channelId: widget.channelId,
        body: body,
        authorUserId: userId,
      );
      _input.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.authService.currentUserId ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Avator(text: widget.channelName, width: 32, height: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.channelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MessageRow>>(
              stream: widget.chatService.watchMessages(widget.channelId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return const Center(child: Text('No messages yet'));
                }
                // fetchChannelMessages returns newest-first; use reverse
                // on the ListView so the first element renders at the
                // bottom of the scroll view.
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) => _MessageBubble(
                    message: messages[i],
                    isMine: messages[i].authorUserId == currentUserId,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Message',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send),
                    onPressed: _sending ? null : _onSend,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageRow message;
  final bool isMine;
  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final bg = isMine
        ? Theme.of(context).iconTheme.color
        : Theme.of(context).dividerColor;
    final fg = isMine ? Colors.white : null;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.body ?? '',
              style: TextStyle(color: fg),
            ),
            const SizedBox(height: 2),
            Text(
              _stateLabel(message.state),
              style: TextStyle(
                fontSize: 10,
                color: fg?.withValues(alpha: 0.7) ??
                    Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stateLabel(MessageState state) {
    switch (state) {
      case MessageState.pending:
        return 'pending';
      case MessageState.sending:
        return 'sending…';
      case MessageState.sent:
        return 'sent';
      case MessageState.delivered:
        return 'delivered';
      case MessageState.read:
        return 'read';
      case MessageState.rejected:
        return 'failed';
    }
  }
}
