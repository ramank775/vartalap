/// Chat screen — reactive over `chatService.watchMessages(channelId)`.
library vartalap.screens.chat.chat;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vartalap/screens/chat_info/chat_info.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

class ChatScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  final String channelKind; // 'dm' | 'group'
  final ChatService chatService;
  final AuthService authService;

  const ChatScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.channelKind,
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
    if (userId == null) return;
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
    final scheme = Theme.of(context).colorScheme;
    final chatColors = VartalapTheme.chatColorsOf(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatInfoScreen(
                  channelId: widget.channelId,
                  channelName: widget.channelName,
                  channelKind: widget.channelKind,
                  chatService: widget.chatService,
                ),
              ),
            );
          },
          child: Row(
            children: [
              Avator(
                text: widget.channelName,
                width: kAvatarSm,
                height: kAvatarSm,
              ),
              const SizedBox(width: kSpaceSm),
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
                  return Center(
                    child: Text(
                      'No messages yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }
                // Build a flat list of widgets: messages + date chips.
                // The list is reversed, so index 0 = newest.
                final items = <Widget>[];
                for (int i = 0; i < messages.length; i++) {
                  final msg = messages[i];
                  final mine = msg.authorUserId == currentUserId;
                  final showTail = i == messages.length - 1 ||
                      messages[i + 1].authorUserId != msg.authorUserId;

                  items.add(_MessageBubble(
                    message: msg,
                    isMine: mine,
                    showTail: showTail,
                    chatColors: chatColors,
                  ));

                  // Insert a date chip between this message and the
                  // next older one (i+1) if they fall on different days.
                  // Also insert one above the very oldest message.
                  final thisDate = DateTime.fromMillisecondsSinceEpoch(
                      msg.clientTimestampMs);
                  final bool needsDateChip;
                  if (i == messages.length - 1) {
                    needsDateChip = true; // oldest message
                  } else {
                    final olderDate = DateTime.fromMillisecondsSinceEpoch(
                        messages[i + 1].clientTimestampMs);
                    needsDateChip = thisDate.year != olderDate.year ||
                        thisDate.month != olderDate.month ||
                        thisDate.day != olderDate.day;
                  }
                  if (needsDateChip) {
                    items.add(_DateChip(date: thisDate));
                  }
                }

                return ListView(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: kSpaceSm,
                    vertical: kSpaceSm,
                  ),
                  children: items,
                );
              },
            ),
          ),
          _MessageInput(
            controller: _input,
            sending: _sending,
            onSend: _onSend,
          ),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;
  const _DateChip({required this.date});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: kSpaceSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: kSpaceMd,
            vertical: kSpaceXs + 2,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(kRadiusFull),
          ),
          child: Text(
            _formatDate(date),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.EEEE().format(d);
    if (d.year == now.year) return DateFormat.MMMd().format(d);
    return DateFormat.yMMMd().format(d);
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _MessageInput({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpaceSm,
          vertical: kSpaceSm,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(kRadiusXl),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Message',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: kSpaceMd,
                      vertical: kSpaceSm + kSpaceXs,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: kSpaceSm),
            Material(
              color: scheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: Padding(
                  padding: const EdgeInsets.all(kSpaceSm + kSpaceXs),
                  child: sending
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: scheme.onPrimary,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageRow message;
  final bool isMine;
  final bool showTail;
  final ChatColors chatColors;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showTail,
    required this.chatColors,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMine ? chatColors.senderBubble : chatColors.receiverBubble;
    final fg = isMine ? chatColors.senderText : chatColors.receiverText;
    final timestampColor = isMine
        ? chatColors.senderText.withValues(alpha: 0.6)
        : chatColors.messageTimestamp;

    final timeStr = DateFormat.Hm().format(
      DateTime.fromMillisecondsSinceEpoch(message.clientTimestampMs),
    );

    // The meta row (time + optional tick) that tucks into the message.
    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: TextStyle(fontSize: 11, color: timestampColor),
        ),
        if (isMine) ...[
          const SizedBox(width: 3),
          _stateIcon(message.state, timestampColor),
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.only(
        top: showTail ? 8 : 2,
        bottom: 2,
        left: isMine ? 64 : 0,
        right: isMine ? 0 : 64,
      ),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: PhysicalShape(
          clipper: _BubbleClipper(isMine: isMine, showTail: showTail),
          color: bg,
          elevation: 0.5,
          shadowColor: Colors.black26,
          child: Padding(
            padding: EdgeInsets.only(
              left: !isMine && showTail ? 16 : 12,
              right: isMine && showTail ? 16 : 12,
              top: 7,
              bottom: 6,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.68,
              ),
              // Wrap lets the meta (time+tick) sit at the end of the
              // last line of text if there's room, or drop to a new
              // line if the text fills the full width.
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 6,
                runSpacing: 2,
                children: [
                  Text(
                    message.body ?? '',
                    style: TextStyle(color: fg, fontSize: 16, height: 1.35),
                  ),
                  meta,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Single tick = sent, double tick = delivered, blue double tick = read,
  /// clock = pending/sending, error = rejected.
  Widget _stateIcon(MessageState state, Color defaultColor) {
    switch (state) {
      case MessageState.pending:
      case MessageState.sending:
        return Icon(Icons.access_time, size: 15, color: defaultColor);
      case MessageState.sent:
        return Icon(Icons.check, size: 15, color: defaultColor);
      case MessageState.delivered:
        return Icon(Icons.done_all, size: 15, color: defaultColor);
      case MessageState.read:
        return const Icon(Icons.done_all, size: 15, color: Color(0xFF53BDEB));
      case MessageState.rejected:
        return Icon(Icons.error_outline, size: 15, color: Colors.red[300]);
    }
  }
}

/// Clips the bubble shape. Without a tail it's a plain rounded rect.
/// With a tail it draws a small curved nub at the top corner (right
/// for sender, left for receiver) using cubic bezier for a smooth
/// WhatsApp-like shape.
class _BubbleClipper extends CustomClipper<Path> {
  final bool isMine;
  final bool showTail;

  _BubbleClipper({required this.isMine, required this.showTail});

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    const r = 18.0;

    if (!showTail) {
      return Path()
        ..addRRect(RRect.fromLTRBR(0, 0, w, h, const Radius.circular(r)));
    }

    final path = Path();

    if (isMine) {
      // Tail on top-right.
      path.moveTo(r, 0);
      path.lineTo(w, 0);
      // Tail: small curved nub extending right from the top-right.
      path.cubicTo(w, 0, w + 6, 0, w + 6, 8);
      path.cubicTo(w + 6, 10, w, 6, w, r);
      // Right edge down.
      path.lineTo(w, h - r);
      // Bottom-right corner.
      path.quadraticBezierTo(w, h, w - r, h);
      // Bottom edge.
      path.lineTo(r, h);
      // Bottom-left corner.
      path.quadraticBezierTo(0, h, 0, h - r);
      // Left edge up.
      path.lineTo(0, r);
      // Top-left corner.
      path.quadraticBezierTo(0, 0, r, 0);
    } else {
      // Tail on top-left.
      path.moveTo(0, 0);
      // Tail: small curved nub extending left from the top-left.
      path.cubicTo(0, 0, -6, 0, -6, 8);
      path.cubicTo(-6, 10, 0, 6, 0, r);
      // Left edge down.
      path.lineTo(0, h - r);
      // Bottom-left corner.
      path.quadraticBezierTo(0, h, r, h);
      // Bottom edge.
      path.lineTo(w - r, h);
      // Bottom-right corner.
      path.quadraticBezierTo(w, h, w, h - r);
      // Right edge up.
      path.lineTo(w, r);
      // Top-right corner.
      path.quadraticBezierTo(w, 0, w - r, 0);
      // Top edge back to start.
      path.lineTo(0, 0);
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(_BubbleClipper old) =>
      old.isMine != isMine || old.showTail != showTail;
}
