/// WhatsApp's Starred messages: every starred message in every chat,
/// newest star first. Starring is local-only ([ChatService.setStarred]).
library vartalap.screens.starred.starred;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap_store/vartalap_store.dart';

class StarredMessagesScreen extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;

  const StarredMessagesScreen({
    super.key,
    required this.chatService,
    required this.authService,
  });

  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  /// author userId → [ContactRow.displayLabel], for a group message's
  /// sender, re-read with every emission as the chat list does. A chat
  /// resolves its own title through [ChannelListEntry.title].
  Map<String, String> _senderLabels = const {};

  /// Created once so rebuilds don't resubscribe.
  late final Stream<List<StarredMessage>> _starred =
      widget.chatService.watchStarredMessages().asyncMap((rows) async {
    final contacts = await widget.chatService.discoverContacts();
    _senderLabels = {for (final c in contacts) c.userId: c.displayLabel};
    return rows;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Starred messages')),
      body: StreamBuilder<List<StarredMessage>>(
        stream: _starred,
        builder: (context, snapshot) {
          final items = snapshot.data;
          if (items == null) return const SizedBox.shrink();
          if (items.isEmpty) return const _EmptyStarred();
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _tile(context, items[i]),
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, StarredMessage item) {
    final (:message, :channel) = item;
    final scheme = Theme.of(context).colorScheme;
    final mine = message.authorUserId == widget.authService.currentUserId;
    final dm = channel.kind == 'one_to_one';
    // WhatsApp: "You ▸ Trip", "Asha ▸ Trip"; in a DM "You ▸ Asha" and
    // "Asha ▸ You".
    final sender = mine
        ? 'You'
        : dm
            ? channel.title
            : _senderLabels[message.authorUserId] ?? 'Unknown';
    final chat = dm && !mine ? 'You' : channel.title;
    final date = DateFormat.yMd().format(
        DateTime.fromMillisecondsSinceEpoch(message.displayTimestampMs));
    return ListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              '$sender ▸ $chat',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: kSpaceSm),
          Text(
            date,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: Text(
        messagePreview(
          message.body ?? '',
          message.contentType,
          attachment: message.attachments != null,
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          channelId: channel.channelId,
          channelName: channel.title,
          channelKind: channel.kind,
          chatService: widget.chatService,
          authService: widget.authService,
          initialMessageId: message.messageId,
        ),
      )),
      onLongPress: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetCtx) => SafeArea(
          child: ListTile(
            leading: const Icon(Icons.star_border),
            title: const Text('Unstar'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              widget.chatService.setStarred([message.messageId], false);
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyStarred extends StatelessWidget {
  const _EmptyStarred();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kSpaceXl),
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
              child: Icon(Icons.star, size: 48, color: scheme.primary),
            ),
            const SizedBox(height: kSpaceMd),
            Text(
              'Tap and hold on any message in any chat to star it, so you '
              'can easily find it later.',
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
}
