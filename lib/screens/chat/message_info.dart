/// Message info (WhatsApp's, SYNC_PROTOCOL §25.2): for an own message,
/// when it was delivered and read; in a group, by whom.
library vartalap.screens.chat.message_info;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap_store/vartalap_store.dart';

class MessageInfoScreen extends StatelessWidget {
  final ChatService chatService;
  final MessageRow message;
  final bool group;

  /// A member's name, as the chat shows it.
  final String Function(String userId) nameOf;

  const MessageInfoScreen({
    super.key,
    required this.chatService,
    required this.message,
    required this.group,
    required this.nameOf,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = VartalapTheme.chatColorsOf(context);
    final preview = message.contentType == kSecureType
        ? '🔒 Secure message'
        : messagePreview(message.body ?? '', message.contentType,
            attachment: message.attachments != null);
    return Scaffold(
      appBar: AppBar(title: const Text('Message info')),
      body: StreamBuilder<List<MessageReceipt>>(
        stream: chatService.watchMessageReceipts(message.messageId),
        builder: (context, snap) {
          final all = snap.data ?? const <MessageReceipt>[];
          final read = [
            for (final r in all)
              if (r.readAtMs != null) r
          ];
          final delivered = [
            for (final r in all)
              if (r.deliveredAtMs != null && r.readAtMs == null) r,
          ];
          final waiting = all.length - read.length - delivered.length;
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(kSpaceMd),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
                    decoration: BoxDecoration(
                      color: colors.senderBubble,
                      borderRadius: BorderRadius.circular(kRadiusMd),
                    ),
                    child: Text(
                      preview,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.senderText, fontSize: 16),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              if (!group) ...[
                _row(context, 'Read', all.firstOrNull?.readAtMs, true),
                _row(context, 'Delivered', all.firstOrNull?.deliveredAtMs,
                    false),
              ] else ...[
                _heading(context, 'Read by', true),
                for (final r in read) _member(context, r.userId, r.readAtMs!),
                if (read.isEmpty) _none(context),
                const Divider(height: 1),
                _heading(context, 'Delivered to', false),
                for (final r in delivered)
                  _member(context, r.userId, r.deliveredAtMs!),
                if (delivered.isEmpty && waiting == 0) _none(context),
                if (waiting > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        kSpaceMd, kSpaceSm, kSpaceMd, kSpaceMd),
                    child: Text(
                      '$waiting remaining',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  static Icon _ticks(bool read) =>
      Icon(Icons.done_all, color: read ? const Color(0xFF53BDEB) : null);

  Widget _row(BuildContext context, String label, int? atMs, bool read) =>
      ListTile(
        leading: _ticks(read),
        title: Text(label),
        subtitle:
            atMs == 0 ? null : Text(atMs == null ? '—' : _when(context, atMs)),
      );

  Widget _heading(BuildContext context, String label, bool read) => ListTile(
        leading: _ticks(read),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  Widget _member(BuildContext context, String userId, int atMs) => ListTile(
        contentPadding: const EdgeInsets.only(left: 72, right: kSpaceMd),
        title: Text(nameOf(userId)),
        subtitle: atMs == 0 ? null : Text(_when(context, atMs)),
      );

  Widget _none(BuildContext context) => const ListTile(
        contentPadding: EdgeInsets.only(left: 72, right: kSpaceMd),
        title: Text('—'),
      );

  /// "Today, 5:47 PM", "Yesterday, …", else the date.
  static String _when(BuildContext context, int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final days = DateUtils.dateOnly(DateTime.now())
        .difference(DateUtils.dateOnly(d))
        .inDays;
    final day = switch (days) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => DateFormat.yMMMd().format(d),
    };
    return '$day, ${TimeOfDay.fromDateTime(d).format(context)}';
  }
}
