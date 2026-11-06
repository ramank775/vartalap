/// A new timeline post (decision 223): a few words and/or photos, for
/// everyone or for the people in some labels. Starts at the audience
/// used last time; one big Post button at the bottom.
library vartalap.screens.timeline.post_composer;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vartalap/screens/labels/labels.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart'
    show AuthClientException;

/// How many photos one post holds.
const int kMaxPostPhotos = 10;

class PostComposerScreen extends StatefulWidget {
  final ChatService chatService;

  /// Picks photos and copies them somewhere durable; injected by tests.
  /// Defaults to the gallery at the chat's photo quality.
  final Future<List<String>> Function(int max)? pickPhotos;

  const PostComposerScreen({
    super.key,
    required this.chatService,
    this.pickPhotos,
  });

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  final _text = TextEditingController();
  final List<String> _photos = [];
  late final Stream<List<Label>> _labels = widget.chatService.watchLabels();

  /// Null: all contacts.
  Set<int>? _audience;
  int? _reach;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _restoreAudience();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _restoreAudience() async {
    final last = await widget.chatService.lastTimelineAudience();
    final existing = {
      for (final l in await widget.chatService.fetchLabels()) l.labelId
    };
    final kept = last?.intersection(existing);
    await _setAudience(kept == null || kept.isEmpty ? null : kept);
  }

  Future<void> _setAudience(Set<int>? labelIds) async {
    setState(() => _audience = labelIds);
    final reach = (await widget.chatService.timelineAudience(labelIds)).length;
    // A later tap won the race.
    if (mounted && _audience == labelIds) setState(() => _reach = reach);
  }

  void _toggleLabel(int labelId) {
    final next = {...?_audience};
    if (!next.remove(labelId)) next.add(labelId);
    _setAudience(next.isEmpty ? null : next);
  }

  Future<List<String>> _pickFromGallery(int max) async {
    final picked = await ImagePicker().pickMultiImage(
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
      limit: max < 2 ? null : max,
    );
    return [
      for (final p in picked.take(max))
        await widget.chatService.assets.importPicked(p.path),
    ];
  }

  Future<void> _addPhotos() async {
    final room = kMaxPostPhotos - _photos.length;
    if (room <= 0) return;
    try {
      final paths = await (widget.pickPhotos ?? _pickFromGallery)(room);
      if (mounted) setState(() => _photos.addAll(paths.take(room)));
    } on PlatformException catch (e) {
      _toast('Could not open the photos: ${e.code}');
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  bool get _canPost =>
      !_posting &&
      (_reach ?? 0) > 0 &&
      (_text.text.trim().isNotEmpty || _photos.isNotEmpty);

  Future<void> _post() async {
    setState(() => _posting = true);
    try {
      await widget.chatService.postToTimeline(
        body: _text.text,
        photoPaths: _photos,
        labelIds: _audience,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Not queued (the timeline is online only): say so, keep the post.
      _toast(e is AuthClientException && e.isRateLimited
          ? "You've posted a lot today. Try again later."
          : "Couldn't post. Check your connection and try again.");
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New post'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(kSpaceMd),
        children: [
          Text('Who can see this', style: text.titleMedium),
          const SizedBox(height: kSpaceSm),
          StreamBuilder<List<Label>>(
            stream: _labels,
            builder: (context, snap) => Wrap(
              spacing: kSpaceSm,
              runSpacing: kSpaceSm,
              children: [
                ChoiceChip(
                  label: const Text('All contacts'),
                  selected: _audience == null,
                  onSelected: (_) => _setAudience(null),
                ),
                for (final l in snap.data ?? const <Label>[])
                  FilterChip(
                    label: Text(l.name),
                    selected: _audience?.contains(l.labelId) ?? false,
                    onSelected: (_) => _toggleLabel(l.labelId),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Labels'),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) =>
                          LabelsScreen(chatService: widget.chatService),
                    ));
                    // Members may have changed.
                    if (mounted) _setAudience(_audience);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: kSpaceSm),
          if (_reach != null)
            Text(
              _reach == 0
                  ? 'Nobody here yet. Add people to the label, or chat '
                      'with them first.'
                  : _reach == 1
                      ? '1 person will see this'
                      : '$_reach people will see this',
              style: TextStyle(
                  color: _reach == 0 ? scheme.error : scheme.onSurfaceVariant),
            ),
          const SizedBox(height: kSpaceLg),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 8,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              hintText: 'Write something',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: kSpaceSm),
          Wrap(
            spacing: kSpaceSm,
            runSpacing: kSpaceSm,
            children: [
              for (final (i, p) in _photos.indexed)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(kRadiusSm),
                      child: Image.file(File(p),
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                          cacheWidth: 192,
                          errorBuilder: (_, __, ___) => Container(
                              width: 96,
                              height: 96,
                              color: scheme.surfaceContainerHighest)),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        tooltip: 'Remove photo',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _photos.removeAt(i)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (_photos.length < kMaxPostPhotos)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _posting ? null : _addPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Add photos'),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kSpaceMd),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(fontSize: 18),
            ),
            onPressed: _canPost ? _post : null,
            icon: const Icon(Icons.send_rounded),
            label: Text(_posting ? 'Posting…' : 'Post'),
          ),
        ),
      ),
    );
  }
}
