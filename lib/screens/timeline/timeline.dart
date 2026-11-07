/// The private timeline (decision 223), the tab next to Chats: posts
/// shared with us and our own, newest first, no ranking. Loaded from the
/// server when the tab opens (and on a pull down); nothing is kept on the
/// phone. Reactions go to the poster alone; only the poster sees who
/// reacted, and there are no counts.
library vartalap.screens.timeline;

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chats/chats.dart' show ChannelTile;
import 'package:vartalap/screens/labels/labels.dart';
import 'package:vartalap/screens/timeline/post_composer.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/timeline_client.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_store/vartalap_store.dart';

/// The reactions on offer, WhatsApp's row.
const List<String> kPostReactions = ['❤️', '👍', '😂', '😮', '😢', '🙏'];

class TimelineScreen extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;

  const TimelineScreen({
    super.key,
    required this.chatService,
    required this.authService,
  });

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<TimelinePost>? _posts;
  bool _failed = false;

  /// user_id → contact, for names and photos.
  Map<String, ContactRow> _people = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (posts, contacts) = await (
        widget.chatService.loadTimeline(),
        widget.chatService.discoverContacts(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _people = {for (final c in contacts) c.userId: c};
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _compose({bool photo = false}) async {
    final posted = await Navigator.of(context).push(MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) =>
          PostComposerScreen(chatService: widget.chatService, photo: photo),
    ));
    if (posted == true) await _load();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// The server first; the card changes once it said yes.
  Future<void> _react(TimelinePost post, String? emoji) async {
    try {
      await widget.chatService.reactToPost(post, emoji);
      setState(() => _posts = [
            for (final p in _posts!)
              p.postId == post.postId ? p.withMyReaction(emoji) : p
          ]);
    } catch (_) {
      _toast("Couldn't send your reaction. Check your connection.");
    }
  }

  Future<void> _delete(TimelinePost post) async {
    try {
      await widget.chatService.deletePost(post);
      setState(
          () => _posts = [..._posts!.where((p) => p.postId != post.postId)]);
    } catch (_) {
      _toast("Couldn't delete the post. Check your connection.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Labels',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => LabelsScreen(chatService: widget.chatService),
            )),
          ),
        ],
      ),
      body: _body(),
      // WhatsApp's pair: a small pencil for words over the camera.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            // Chats' button lives in the same tab stack: no shared hero.
            heroTag: null,
            tooltip: 'Write a post',
            onPressed: _compose,
            child: const Icon(Icons.edit),
          ),
          const SizedBox(height: kSpaceMd),
          FloatingActionButton(
            heroTag: null,
            tooltip: 'Photo post',
            onPressed: () => _compose(photo: true),
            child: const Icon(Icons.photo_camera),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final posts = _posts;
    if (posts == null && _failed) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load the timeline",
        text: 'Check your connection.',
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (posts == null) return const Center(child: CircularProgressIndicator());
    final me = widget.authService.currentUserId;
    return RefreshIndicator(
      onRefresh: _load,
      child: posts.isEmpty
          // scrollable, so a pull down still refreshes
          ? ListView(children: const [
              SizedBox(height: 96),
              _Message(
                icon: Icons.dynamic_feed_outlined,
                title: 'No posts yet',
                text: 'Share a photo or a few words with family and friends. '
                    'Only the people you choose see it.',
              ),
            ])
          : ListView.separated(
              // Clear of the post buttons.
              padding: const EdgeInsets.only(bottom: 136),
              itemCount: posts.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 0),
              itemBuilder: (_, i) => PostCard(
                post: posts[i],
                mine: posts[i].author == me,
                people: _people,
                onReact: (emoji) => _react(posts[i], emoji),
                onDelete: () => _delete(posts[i]),
              ),
            ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kSpaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: kSpaceMd),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: kSpaceSm),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            if (action != null) ...[
              const SizedBox(height: kSpaceMd),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// One post: who, when, the words, the photos; then our reaction row on
/// someone else's, or who reacted on ours.
class PostCard extends StatelessWidget {
  final TimelinePost post;
  final bool mine;
  final Map<String, ContactRow> people;
  final void Function(String? emoji) onReact;
  final VoidCallback onDelete;

  const PostCard({
    super.key,
    required this.post,
    required this.mine,
    required this.people,
    required this.onReact,
    required this.onDelete,
  });

  String _name(String userId) => people[userId]?.displayLabel ?? 'Unknown';

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text('It is removed for everyone it was shared with.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = mine ? 'You' : _name(post.author);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpaceSm + kSpaceXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
            child: Row(
              children: [
                Avator(
                  text: name,
                  seed: personSeed(context, post.author),
                  avatarUrl: mine ? null : people[post.author]?.avatarUrl,
                  width: kAvatarMd,
                  height: kAvatarMd,
                ),
                const SizedBox(width: kSpaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(ChannelTile.formatTime(context, post.createdAt),
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (mine)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete post',
                    onPressed: () => _confirmDelete(context),
                  ),
              ],
            ),
          ),
          if (post.text != null) ...[
            const SizedBox(height: kSpaceSm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
              child: Text(post.text!, style: const TextStyle(fontSize: 17)),
            ),
          ],
          if (post.photos.isNotEmpty) ...[
            const SizedBox(height: kSpaceSm),
            _Photos(photos: post.photos, title: name),
          ],
          const SizedBox(height: kSpaceSm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
            child: mine ? _whoReacted(scheme) : _reactRow(scheme, name),
          ),
        ],
      ),
    );
  }

  /// Ours: who it went to and who reacted, names not numbers.
  Widget _whoReacted(ColorScheme scheme) {
    final n = post.audience?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(n == 1 ? 'Shared with 1 person' : 'Shared with $n people',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        if (post.reactions.isNotEmpty) ...[
          const SizedBox(height: kSpaceXs),
          Wrap(
            spacing: kSpaceSm,
            runSpacing: kSpaceXs,
            children: [
              for (final r in post.reactions)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${r.emoji} ${_name(r.userId)}'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Someone else's: tap a face to react, tap it again to take it back.
  Widget _reactRow(ColorScheme scheme, String poster) {
    final current = post.myReaction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final emoji in kPostReactions)
              Material(
                shape: const CircleBorder(),
                color: emoji == current
                    ? scheme.primaryContainer
                    : Colors.transparent,
                child: IconButton(
                  iconSize: 28,
                  tooltip: emoji == current ? 'Remove reaction' : 'React',
                  icon: Text(emoji, style: const TextStyle(fontSize: 26)),
                  onPressed: () => onReact(emoji == current ? null : emoji),
                ),
              ),
          ],
        ),
        Text('Only $poster sees your reaction',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

/// One photo across the width; more in a two-up grid. A tap opens it.
class _Photos extends StatelessWidget {
  final List<TimelinePhoto> photos;
  final String title;

  const _Photos({required this.photos, required this.title});

  @override
  Widget build(BuildContext context) {
    Widget tile(TimelinePhoto p) => GestureDetector(
          onTap: () => showAssetViewer(context, uri: p.fileId, title: title),
          child: AssetImageView(
            uri: p.fileId,
            placeholder: const AssetImagePlaceholder(),
            fallback:
                const AssetImagePlaceholder(icon: Icons.broken_image_outlined),
          ),
        );
    if (photos.length == 1) {
      return AspectRatio(aspectRatio: 4 / 3, child: tile(photos.single));
    }
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [for (final p in photos) tile(p)],
    );
  }
}
