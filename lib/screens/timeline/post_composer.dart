/// A new timeline post (decision 223), composed like a WhatsApp status:
/// a text post is large centred words on a full-screen colour; a photo
/// post is the photos full screen with a caption. Both end in the same
/// bar: who sees it (starts at the audience used last time) and a round
/// send button.
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

/// The backgrounds the palette button offers, all dark enough for white
/// text.
/// ponytail: the colour (and the font) stay on this screen. The timeline
/// API takes a post's text, photos and audience and refuses any other
/// field, so the feed shows a text post as it always has. Carry them with
/// an optional style field on the post once the server takes one.
const List<(String, Color)> kPostColors = [
  ('Teal', Color(0xFF00796B)),
  ('Purple', Color(0xFF5E35B1)),
  ('Red', Color(0xFFC62828)),
  ('Blue', Color(0xFF1565C0)),
  ('Orange', Color(0xFFE65100)),
  ('Green', Color(0xFF2E7D32)),
  ('Pink', Color(0xFFAD1457)),
  ('Brown', Color(0xFF4E342E)),
  ('Slate', Color(0xFF37474F)),
];

/// The fonts the T button offers: the app's, then Android's own serif,
/// monospace and handwriting families.
const List<(String, String?)> _fonts = [
  ('Default', null),
  ('Serif', 'serif'),
  ('Mono', 'monospace'),
  ('Cursive', 'cursive'),
];

/// The emoji button's choice (the app has no emoji keyboard of its own).
const List<String> _emoji = [
  '😊', '😂', '🥰', '😍', '😎', '🤗', '😇', '🙂', '😢', '😮', //
  '🙏', '👍', '👏', '🙌', '💪', '❤️', '💐', '🌹', '🎉', '🎂', //
  '🪔', '✨', '🌞', '🌙', '⭐', '🏠', '🍛', '☕', '🍬', '🎶', //
];

class PostComposerScreen extends StatefulWidget {
  final ChatService chatService;

  /// A photo post (the timeline's camera button); otherwise a text post.
  final bool photo;

  /// Takes a photo ([camera]) or picks up to [max] from the gallery, and
  /// copies them somewhere durable; injected by tests.
  final Future<List<String>> Function(bool camera, int max)? pickPhotos;

  const PostComposerScreen({
    super.key,
    required this.chatService,
    this.photo = false,
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
  int _color = 0;
  int _font = 0;

  /// The row of choices under the top bar: the palette's or the T's.
  IconData? _picker;
  int _page = 0;

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
    // A later choice won the race.
    if (mounted && _audience == labelIds) setState(() => _reach = reach);
  }

  Future<void> _pickAudience() async {
    final picked = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _AudienceSheet(chatService: widget.chatService, initial: _audience),
    );
    if (picked != null && mounted) {
      await _setAudience(picked.isEmpty ? null : picked);
    }
  }

  Future<List<String>> _pick(bool camera, int max) async {
    // the chat's photo quality
    final picker = ImagePicker();
    final picked = camera
        ? [
            await picker.pickImage(
              source: ImageSource.camera,
              maxWidth: 2048,
              maxHeight: 2048,
              imageQuality: 85,
            ),
          ].nonNulls
        : await picker.pickMultiImage(
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

  Future<void> _addPhotos(bool camera) async {
    final room = kMaxPostPhotos - _photos.length;
    if (room <= 0) return;
    try {
      final paths = await (widget.pickPhotos ?? _pick)(camera, room);
      if (!mounted || paths.isEmpty) return;
      // Show the first new one.
      setState(() {
        _page = _photos.length;
        _photos.addAll(paths.take(room));
      });
    } on PlatformException catch (e) {
      _toast('Could not open the photos: ${e.code}');
    }
  }

  void _removePhoto() => setState(() {
        _photos.removeAt(_page);
        if (_page == _photos.length && _page > 0) _page--;
      });

  Future<void> _addEmoji() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          padding: const EdgeInsets.all(kSpaceSm),
          children: [
            for (final e in _emoji)
              InkWell(
                onTap: () => Navigator.of(ctx).pop(e),
                child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 28))),
              ),
          ],
        ),
      ),
    );
    if (emoji == null) return;
    final sel = _text.selection;
    final at =
        sel.isValid ? sel : TextSelection.collapsed(offset: _text.text.length);
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(at.start, at.end, emoji),
      selection: TextSelection.collapsed(offset: at.start + emoji.length),
    );
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

  /// Large while short, smaller as it grows, like WhatsApp's.
  static double _textSize(int length) => length < 30
      ? 40
      : length < 80
          ? 32
          : length < 160
              ? 26
              : 22;

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    // White status bar icons over the colour or the photo.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: photo ? Colors.black : kPostColors[_color].$2,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(photo),
              if (!photo && _picker != null) _pickerRow(),
              Expanded(child: photo ? _photoBody() : _textBody()),
              if (photo && _photos.length > 1) _strip(),
              if (photo && _photos.isNotEmpty) _caption(),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(IconData icon, String tooltip, VoidCallback? onPressed) =>
      IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        color: Colors.white,
        onPressed: _posting ? null : onPressed,
      );

  Widget _topBar(bool photo) => Row(
        children: [
          _button(Icons.close, 'Cancel', () => Navigator.of(context).pop()),
          const Spacer(),
          if (!photo) ...[
            _button(Icons.emoji_emotions_outlined, 'Emoji', _addEmoji),
            _pickerButton(Icons.text_fields, 'Font'),
            _pickerButton(Icons.palette_outlined, 'Background colour'),
          ] else if (_photos.isNotEmpty) ...[
            _button(Icons.delete_outline, 'Remove photo', _removePhoto),
            if (_photos.length < kMaxPostPhotos) ...[
              _button(Icons.photo_camera_outlined, 'Take a photo',
                  () => _addPhotos(true)),
              _button(Icons.add_photo_alternate_outlined, 'Add photos',
                  () => _addPhotos(false)),
            ],
          ],
        ],
      );

  /// Opens its row of choices; again, or the other one, closes it.
  Widget _pickerButton(IconData icon, String tooltip) => _button(
      icon,
      tooltip,
      () => setState(() => _picker = _picker == icon ? null : icon));

  Widget _pickerRow() {
    final colours = _picker == Icons.palette_outlined;
    Widget choice(bool selected, VoidCallback onTap, Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: kSpaceXs),
          child: Semantics(
            selected: selected,
            button: true,
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: child,
            ),
          ),
        );
    BoxBorder ring(bool selected) =>
        Border.all(color: Colors.white, width: selected ? 3 : 1);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kSpaceSm),
        children: [
          if (colours)
            for (final (i, (name, colour)) in kPostColors.indexed)
              choice(
                i == _color,
                () => setState(() => _color = i),
                Tooltip(
                  message: name,
                  child: Container(
                    width: 36,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                        color: colour,
                        shape: BoxShape.circle,
                        border: ring(i == _color)),
                  ),
                ),
              )
          else
            for (final (i, (name, family)) in _fonts.indexed)
              choice(
                i == _font,
                () => setState(() => _font = i),
                Container(
                  alignment: Alignment.center,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
                  decoration: ShapeDecoration(
                    color: i == _font ? Colors.white24 : null,
                    shape: StadiumBorder(
                        side: BorderSide(
                            color: Colors.white, width: i == _font ? 2 : 1)),
                  ),
                  child: Text(name,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: family)),
                ),
              ),
        ],
      ),
    );
  }

  Widget _textBody() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
          child: TextField(
            controller: _text,
            autofocus: true,
            maxLines: null,
            maxLength: 2000,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: Colors.white,
            style: TextStyle(
              color: Colors.white,
              fontSize: _textSize(_text.text.length),
              fontFamily: _fonts[_font].$2,
              height: 1.25,
            ),
            decoration: const InputDecoration(
              hintText: 'Type a post',
              hintStyle: TextStyle(color: Colors.white60),
              filled: false,
              border: InputBorder.none,
              counterText: '',
            ),
          ),
        ),
      );

  Widget _photoBody() {
    if (_photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _addPhotos(false),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose from gallery'),
            ),
            const SizedBox(height: kSpaceMd),
            FilledButton.tonalIcon(
              onPressed: () => _addPhotos(true),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take a photo'),
            ),
          ],
        ),
      );
    }
    return Image.file(
      File(_photos[_page]),
      fit: BoxFit.contain,
      // Never decode a 12 MP original just to look.
      cacheWidth: 1440,
      errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined,
              size: 64, color: Colors.white54)),
    );
  }

  /// Every photo small; a tap shows it.
  Widget _strip() => SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: kSpaceSm),
          children: [
            for (final (i, p) in _photos.indexed)
              Semantics(
                button: true,
                selected: i == _page,
                label: 'Photo ${i + 1}',
                child: GestureDetector(
                  onTap: () => setState(() => _page = i),
                  child: Container(
                    width: 48,
                    margin: const EdgeInsets.all(kSpaceXs),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: i == _page ? Colors.white : Colors.transparent,
                          width: 2),
                      borderRadius: BorderRadius.circular(kRadiusSm),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(kRadiusSm - 2),
                      child: Image.file(File(p),
                          fit: BoxFit.cover,
                          cacheWidth: 96,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Colors.white24)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _caption() => Padding(
        padding: const EdgeInsets.fromLTRB(kSpaceSm, kSpaceSm, kSpaceSm, 0),
        child: TextField(
          controller: _text,
          minLines: 1,
          maxLines: 4,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Add a caption…',
            hintStyle: const TextStyle(color: Colors.white60),
            fillColor: Colors.white12,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusXl),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  /// Who sees it, bottom left; send, bottom right.
  Widget _bottomBar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(kSpaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_reach == 0)
            Padding(
              padding: const EdgeInsets.all(kSpaceSm),
              child: Text(
                'Nobody here yet. Add people to the label, or chat with '
                'them first.',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: StreamBuilder<List<Label>>(
                  stream: _labels,
                  builder: (context, snap) {
                    final names = [
                      for (final l in snap.data ?? const <Label>[])
                        if (_audience?.contains(l.labelId) ?? false) l.name
                    ];
                    return Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.black26,
                          ),
                          onPressed: _posting ? null : _pickAudience,
                          icon: const Icon(Icons.people_outline),
                          label: Text(
                            _audience == null || names.isEmpty
                                ? 'All contacts'
                                : names.join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ));
                  },
                ),
              ),
              const SizedBox(width: kSpaceSm),
              IconButton.filled(
                tooltip: 'Send',
                iconSize: 26,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  minimumSize: const Size.square(56),
                ),
                onPressed: _canPost ? _post : null,
                icon: _posting
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Who sees the post: all contacts, or the people in some labels, with
/// how many that is. Pops the chosen label ids (empty: all contacts) on
/// Done; nothing changes when it is dismissed.
class _AudienceSheet extends StatefulWidget {
  final ChatService chatService;
  final Set<int>? initial;

  const _AudienceSheet({required this.chatService, required this.initial});

  @override
  State<_AudienceSheet> createState() => _AudienceSheetState();
}

class _AudienceSheetState extends State<_AudienceSheet> {
  late final Stream<List<Label>> _labels = widget.chatService.watchLabels();
  late Set<int>? _chosen = widget.initial;
  int? _reach;

  @override
  void initState() {
    super.initState();
    _count();
  }

  Future<void> _count() async {
    final chosen = _chosen;
    final reach = (await widget.chatService.timelineAudience(chosen)).length;
    if (mounted && _chosen == chosen) setState(() => _reach = reach);
  }

  void _choose(Set<int>? labelIds) {
    setState(
        () => _chosen = labelIds == null || labelIds.isEmpty ? null : labelIds);
    _count();
  }

  void _toggle(int labelId) {
    final next = {...?_chosen};
    if (!next.remove(labelId)) next.add(labelId);
    _choose(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: StreamBuilder<List<Label>>(
        stream: _labels,
        builder: (context, snap) {
          final labels = snap.data ?? const <Label>[];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    kSpaceMd, kSpaceMd, kSpaceMd, kSpaceSm),
                child: Text('Who can see this',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    CheckboxListTile(
                      value: _chosen == null,
                      secondary: const Icon(Icons.people_outline),
                      title: const Text('All contacts'),
                      onChanged: (_) => _choose(null),
                    ),
                    for (final l in labels)
                      CheckboxListTile(
                        value: _chosen?.contains(l.labelId) ?? false,
                        secondary: const Icon(Icons.label_outline),
                        title: Text(l.name),
                        onChanged: (_) => _toggle(l.labelId),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
                child: Text(
                  switch (_reach) {
                    null => '',
                    0 => 'Nobody here yet. Add people to the label, or chat '
                        'with them first.',
                    1 => '1 person will see this',
                    final n => '$n people will see this',
                  },
                  style: TextStyle(
                      color:
                          _reach == 0 ? scheme.error : scheme.onSurfaceVariant),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(kSpaceSm),
                child: Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit labels'),
                      onPressed: () async {
                        await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => LabelsScreen(
                                    chatService: widget.chatService)));
                        // Members may have changed.
                        if (mounted) _count();
                      },
                    ),
                    const Spacer(),
                    FilledButton(
                      // Only labels that still exist.
                      onPressed: () => Navigator.of(context).pop({
                        for (final l in labels)
                          if (_chosen?.contains(l.labelId) ?? false) l.labelId
                      }),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
