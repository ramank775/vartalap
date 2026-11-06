/// The DM header's second line (SYNC_PROTOCOL §21): "typing…", else
/// "online" or "last seen today at 10:42", else nothing, as WhatsApp.
library vartalap.screens.chat.presence_line;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vartalap/services/chat_service.dart';

/// What the header says for [p]; null for nothing. The time follows the
/// phone's 12/24-hour setting.
String? presenceText(BuildContext context, PeerPresence? p, {DateTime? now}) {
  if (p == null) return null;
  if (p.online) return 'online';
  if (p.lastSeenMs <= 0) return null;
  final seen = DateTime.fromMillisecondsSinceEpoch(p.lastSeenMs);
  final today = now ?? DateTime.now();
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(seen.year, seen.month, seen.day))
      .inDays;
  final time = TimeOfDay.fromDateTime(seen).format(context);
  if (days <= 0) return 'last seen today at $time';
  if (days == 1) return 'last seen yesterday at $time';
  if (days < 7) return 'last seen ${DateFormat.EEEE().format(seen)} at $time';
  return 'last seen ${DateFormat.yMMMd().format(seen)}';
}

/// Watches [channelId]'s peer while on screen. Mounted for the chat's
/// whole life, typing or not, so a "typing…" does not cost a new watch.
class PresenceLine extends StatefulWidget {
  final ChatService chatService;
  final String channelId;
  final bool typing;
  final Color color;

  const PresenceLine({
    super.key,
    required this.chatService,
    required this.channelId,
    required this.typing,
    required this.color,
  });

  @override
  State<PresenceLine> createState() => _PresenceLineState();
}

class _PresenceLineState extends State<PresenceLine> {
  @override
  void initState() {
    super.initState();
    widget.chatService.watchPresence(widget.channelId);
  }

  @override
  void dispose() {
    widget.chatService.unwatchPresence(widget.channelId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PeerPresence?>(
        valueListenable: widget.chatService.presence,
        builder: (context, presence, _) {
          final text =
              widget.typing ? 'typing…' : presenceText(context, presence);
          if (text == null) return const SizedBox.shrink();
          return Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: widget.color,
              fontStyle: widget.typing ? FontStyle.italic : null,
            ),
          );
        },
      );
}
