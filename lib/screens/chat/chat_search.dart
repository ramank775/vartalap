/// In-chat message search. Pushed from the chat AppBar; pops with the
/// tapped message_id (or null if dismissed) so the caller can scroll
/// the chat to that row.
library vartalap.screens.chat.chat_search;

import 'package:flutter/material.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_store/vartalap_store.dart';

class ChatSearchScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  final ChatService chatService;
  final String? localUserId;

  const ChatSearchScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.chatService,
    required this.localUserId,
  });

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final TextEditingController _query = TextEditingController();
  List<MessageRow> _results = const [];
  bool _searching = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String q) async {
    final trimmed = q.trim();
    _lastQuery = trimmed;
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final results = await widget.chatService.searchInChannel(
      channelId: widget.channelId,
      query: trimmed,
    );
    if (!mounted || _lastQuery != trimmed) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search in ${widget.channelName}',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
            hintStyle: TextStyle(
              color: scheme.onPrimary.withValues(alpha: 0.7),
            ),
          ),
          style: TextStyle(color: scheme.onPrimary, fontSize: 18),
          cursorColor: scheme.onPrimary,
          onChanged: _runSearch,
        ),
        actions: [
          if (_query.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _query.clear();
                _runSearch('');
              },
            ),
        ],
      ),
      body: Builder(
        builder: (_) {
          if (_query.text.trim().isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(kSpaceLg),
                child: Text(
                  'Type to search messages in this conversation.',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (_searching) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_results.isEmpty) {
            return Center(
              child: Text(
                'No messages match.',
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            );
          }
          return ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final m = _results[i];
              final mine = widget.localUserId != null &&
                  m.authorUserId == widget.localUserId;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    mine ? Icons.person : Icons.person_outline,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                title: Text(
                  m.body ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _formatTimestamp(m.serverTimestampMs ?? m.clientTimestampMs),
                ),
                onTap: () => Navigator.of(context).pop(m.messageId),
              );
            },
          );
        },
      ),
    );
  }

  static String _formatTimestamp(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}
