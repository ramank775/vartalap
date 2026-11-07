/// "Forward to…" (WhatsApp's): the chats a forward may go to, with a
/// search. Only groups we are in and people we are connected with
/// (decision 219), recent chats first.
library vartalap.screens.chat.forward;

import 'package:flutter/material.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_transport/vartalap_transport.dart' show dmChannelId;

/// A chat picked to forward to.
typedef ForwardTarget = ({String channelId, String title, bool group});

/// Pops the picked chats, at most [limit], in the order picked; a 1:1
/// chat not started yet is created on the way. Null on back. Share-to
/// uses it as "Send to…" ([title]).
class ForwardScreen extends StatefulWidget {
  final ChatService chatService;
  final String selfUserId;
  final int limit;
  final String title;

  const ForwardScreen({
    super.key,
    required this.chatService,
    required this.selfUserId,
    this.limit = ChatService.maxForwardChats,
    this.title = 'Forward to…',
  });

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

typedef _Row = ({
  ForwardTarget target,
  String? avatarUrl,
  String? peerUserId,
  int lastActivityMs,
});

class _ForwardScreenState extends State<ForwardScreen> {
  late final Future<List<_Row>> _rows = _load();
  final List<_Row> _picked = [];
  final _search = TextEditingController();

  Future<List<_Row>> _load() async {
    final self = widget.selfUserId;
    final chats = {
      for (final c
          in await widget.chatService.fetchMemberChannels(userId: self))
        c.channelId: c,
    };
    final connected = await widget.chatService.connectedUsers();
    final blocked = await widget.chatService.watchBlocked().first;
    final rows = <_Row>[
      for (final c in chats.values)
        if (c.kind == 'group')
          (
            target: (channelId: c.channelId, title: c.title, group: true),
            avatarUrl: c.avatarUrl,
            peerUserId: null,
            lastActivityMs: c.lastActivityMs,
          ),
      for (final p in await widget.chatService.discoverContacts())
        if ((connected?.contains(p.userId) ?? true) &&
            !blocked.contains(p.userId) &&
            p.userId != self)
          (
            target: (
              channelId: dmChannelId(self, p.userId),
              title: p.displayLabel,
              group: false,
            ),
            avatarUrl: p.avatarUrl,
            peerUserId: p.userId,
            lastActivityMs:
                chats[dmChannelId(self, p.userId)]?.lastActivityMs ?? 0,
          ),
    ];
    return rows
      ..sort((a, b) {
        final byTime = b.lastActivityMs.compareTo(a.lastActivityMs);
        return byTime != 0
            ? byTime
            : a.target.title
                .toLowerCase()
                .compareTo(b.target.title.toLowerCase());
      });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(_Row r) {
    final id = r.target.channelId;
    setState(() {
      if (_picked.any((p) => p.target.channelId == id)) {
        _picked.removeWhere((p) => p.target.channelId == id);
      } else if (_picked.length < widget.limit) {
        _picked.add(r);
      } else {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(widget.limit == 1
                ? 'This message can be forwarded to one chat at a time'
                : 'You can send to up to ${widget.limit} chats'),
          ));
      }
    });
  }

  Future<void> _send() async {
    for (final r in _picked) {
      final peer = r.peerUserId;
      if (peer != null) {
        await widget.chatService.startDirectMessage(
          localUserId: widget.selfUserId,
          peerUserId: peer,
          peerName: r.target.title,
        );
      }
    }
    if (mounted) {
      Navigator.of(context).pop([for (final r in _picked) r.target]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onBar =
        Theme.of(context).appBarTheme.foregroundColor ?? scheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            if (_picked.isNotEmpty)
              Text(
                '${_picked.length} selected',
                style: TextStyle(
                    fontSize: 13, color: onBar.withValues(alpha: 0.85)),
              ),
          ],
        ),
      ),
      body: FutureBuilder<List<_Row>>(
        future: _rows,
        builder: (context, snap) {
          if (!snap.hasData) {
            return snap.hasError
                ? Center(child: Text('Error: ${snap.error}'))
                : const Center(child: CircularProgressIndicator());
          }
          final query = _search.text.trim().toLowerCase();
          final rows = [
            for (final r in snap.data!)
              if (r.target.title.toLowerCase().contains(query)) r,
          ];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    kSpaceMd, kSpaceSm, kSpaceMd, kSpaceSm),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: kSpaceMd),
                  ),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(kSpaceXl),
                          child: Text(
                            snap.data!.isEmpty
                                ? 'You can send to people who accepted '
                                    'your invite to chat, and to your groups.'
                                : 'No chats found',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (_, i) => _tile(context, rows[i]),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _picked.isEmpty
          ? null
          : FloatingActionButton(
              tooltip: 'Send',
              onPressed: _send,
              child: const Icon(Icons.send),
            ),
    );
  }

  Widget _tile(BuildContext context, _Row r) {
    final scheme = Theme.of(context).colorScheme;
    final picked = _picked.any((p) => p.target.channelId == r.target.channelId);
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Avator(
            text: r.target.title,
            seed: r.peerUserId == null
                ? r.target.channelId
                : personSeed(context, r.peerUserId!),
            avatarUrl: r.avatarUrl,
            isGroup: r.target.group,
            width: kAvatarMd,
            height: kAvatarMd,
          ),
          if (picked)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(Icons.check, size: 13, color: scheme.onPrimary),
              ),
            ),
        ],
      ),
      title: Text(r.target.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: picked,
      onTap: () => _toggle(r),
    );
  }
}
