/// Occasion albums in a chat (decision 233): chat info's Albums section,
/// an album's photo grid, and a full-screen viewer to swipe through. All
/// online, from the server's album API: nothing is kept on the phone and
/// albums are not end-to-end encrypted. The server decides who may do
/// what; the screens only hide the buttons that would be refused.
library vartalap.screens.albums;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:vartalap/services/album_client.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/app_services.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap/widgets/name_dialog.dart';
import 'package:vartalap_transport/vartalap_transport.dart'
    show AuthClientException;

String _day(int ms) =>
    DateFormat('d MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));

/// '2026-11-01' as '1 Nov 2026'.
String albumDate(String date) {
  final d = DateTime.tryParse(date);
  return d == null ? date : DateFormat('d MMM yyyy').format(d);
}

String _photos(int n) => n == 1 ? '1 photo' : '$n photos';

/// What the server refused, in plain words.
String _failure(Object e, String action) {
  if (e is AuthClientException) {
    if (e.isRateLimited)
      return "You've done that a lot today. Try again later.";
    if (e.errorCode == 'album_full') return 'This album is full.';
    if (e.errorCode == 'album_limit') {
      return 'This chat has too many albums. Delete an old one first.';
    }
    if (e.statusCode == 403) return "You can't $action.";
  }
  return "Couldn't $action. Check your connection and try again.";
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// The chat message an album's creator sent: open that album.
void openAlbumNote(BuildContext context, AlbumNote note) {
  final chatService = AppServicesProvider.maybeOf(context)?.chatService;
  if (chatService == null) return;
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => AlbumScreen(
      chatService: chatService,
      channelId: note.channelId,
      albumId: note.albumId,
    ),
  ));
}

/// The square cover of [album]: its newest photo.
Widget _cover(Album album, double size) => ClipRRect(
      borderRadius: BorderRadius.circular(kRadiusSm),
      child: SizedBox.square(
        dimension: size,
        child: album.cover == null
            ? const AssetImagePlaceholder(icon: Icons.photo_library_outlined)
            : AssetImageView(
                uri: album.cover!.fileId,
                placeholder: const AssetImagePlaceholder(),
              ),
      ),
    );

/// Chat info's Albums row: how many, the newest covers; a tap opens
/// [AlbumsScreen]. Not shown at all where the server says the chat has
/// none for us (a 1:1 that is not connected, or blocked).
class AlbumsTile extends StatefulWidget {
  final ChatService chatService;
  final String channelId;

  /// A 1:1's other person; null in a group.
  final String? peer;

  const AlbumsTile({
    super.key,
    required this.chatService,
    required this.channelId,
    this.peer,
  });

  @override
  State<AlbumsTile> createState() => _AlbumsTileState();
}

class _AlbumsTileState extends State<AlbumsTile> {
  List<Album>? _albums;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final albums = await widget.chatService
          .albumsOf(widget.channelId, peer: widget.peer);
      if (mounted) setState(() => _albums = albums);
    } catch (e) {
      if (mounted && e is AuthClientException && e.statusCode == 403) {
        setState(() => _hidden = true);
      }
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AlbumsScreen(
        chatService: widget.chatService,
        channelId: widget.channelId,
        peer: widget.peer,
      ),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final albums = _albums;
    final n = albums?.length ?? 0;
    return ListTile(
      leading: Icon(Icons.photo_library_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: const Text('Albums'),
      subtitle: albums == null
          ? null
          : Text(n == 0
              ? 'Photos of a day, for everyone here'
              : n == 1
                  ? '1 album'
                  : '$n albums'),
      trailing: n == 0
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final album in albums!.take(3))
                  Padding(
                    padding: const EdgeInsets.only(left: kSpaceXs),
                    child: _cover(album, 40),
                  ),
              ],
            ),
      onTap: _open,
    );
  }
}

/// A chat's albums, newest first, each with its cover, and a big New
/// album button.
class AlbumsScreen extends StatefulWidget {
  final ChatService chatService;
  final String channelId;

  /// A 1:1's other person; null in a group.
  final String? peer;

  const AlbumsScreen({
    super.key,
    required this.chatService,
    required this.channelId,
    this.peer,
  });

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  List<Album>? _albums;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final albums = await widget.chatService
          .albumsOf(widget.channelId, peer: widget.peer);
      if (mounted) {
        setState(() {
          _albums = albums;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _open(Album album) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AlbumScreen(
        chatService: widget.chatService,
        channelId: album.channelId,
        albumId: album.albumId,
        album: album,
      ),
    ));
    await _load();
  }

  Future<void> _create() async {
    final picked = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => const NewAlbumDialog(),
    );
    if (picked == null || !mounted) return;
    try {
      final album = await widget.chatService.createAlbum(
        channelId: widget.channelId,
        peer: widget.peer,
        title: picked.$1,
        date: picked.$2,
      );
      if (mounted) await _open(album);
    } catch (e) {
      if (mounted) _toast(context, _failure(e, 'make the album'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final albums = _albums;
    return Scaffold(
      appBar: AppBar(title: const Text('Albums')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('New album', style: TextStyle(fontSize: 18)),
      ),
      body: albums == null && _failed
          ? _Notice(
              icon: Icons.cloud_off_outlined,
              title: "Couldn't load the albums",
              text: 'Check your connection.',
              action: FilledButton(
                  onPressed: _load, child: const Text('Try again')),
            )
          : albums == null
              ? const Center(child: CircularProgressIndicator())
              : albums.isEmpty
                  ? const _Notice(
                      icon: Icons.photo_library_outlined,
                      title: 'No albums yet',
                      text: 'Make an album for a family day. Everyone in '
                          'this chat can see it and add their photos.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        // Clear of the New album button.
                        padding: const EdgeInsets.only(bottom: 96),
                        children: [
                          for (final album in albums)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: kSpaceMd, vertical: kSpaceXs),
                              leading: _cover(album, kAvatarLg),
                              title: Text(album.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text([
                                if (album.date != null) albumDate(album.date!),
                                _photos(album.photoCount),
                              ].join(' · ')),
                              onTap: () => _open(album),
                            ),
                        ],
                      ),
                    ),
    );
  }
}

/// A new album's name and, if the user wants, its day. Pops
/// `(title, 'YYYY-MM-DD' or null)`, or null on Cancel.
class NewAlbumDialog extends StatefulWidget {
  const NewAlbumDialog({super.key});

  @override
  State<NewAlbumDialog> createState() => _NewAlbumDialogState();
}

class _NewAlbumDialogState extends State<NewAlbumDialog> {
  final _title = TextEditingController();
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 50),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _done() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop((
      title,
      _date == null ? null : DateFormat('yyyy-MM-dd').format(_date!),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New album'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Album name', hintText: 'Diwali 2026'),
              onSubmitted: (_) => _done(),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text(_date == null
                  ? 'Add the day (optional)'
                  : DateFormat('d MMM yyyy').format(_date!)),
              onPressed: _pickDate,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _title.text.trim().isEmpty ? null : _done,
            child: const Text('Create'),
          ),
        ],
      );
}

/// One album: its photos in a grid, newest first, a big Add photos
/// button, and Rename / Delete for its creator or a group admin.
class AlbumScreen extends StatefulWidget {
  final ChatService chatService;
  final String channelId;
  final String albumId;

  /// Shown while the album loads, when the caller has it.
  final Album? album;

  /// Picks photos ([camera]: takes one) and copies them somewhere
  /// durable; injected by tests.
  final Future<List<String>> Function(bool camera)? pickPhotos;

  const AlbumScreen({
    super.key,
    required this.chatService,
    required this.channelId,
    required this.albumId,
    this.album,
    this.pickPhotos,
  });

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late Album? _album = widget.album;
  List<AlbumPhoto>? _photos;
  String? _next;
  bool _loadingMore = false;
  bool _failed = false;

  /// No such album any more (deleted, expired), or not ours to see.
  bool _gone = false;

  /// While photos go up: how many of how many.
  (int, int)? _adding;
  bool _isAdmin = false;
  Map<String, String> _names = const {};

  ChatService get _chat => widget.chatService;
  String? get _me => _chat.selfUserId;

  bool get _canEdit {
    final album = _album;
    return album != null && (album.creator == _me || _isAdmin);
  }

  bool _canRemove(AlbumPhoto p) => p.uploader == _me || _canEdit;

  String _nameOf(String userId) =>
      userId == _me ? 'You' : _names[userId] ?? 'Someone';

  @override
  void initState() {
    super.initState();
    _load();
    _loadPeople();
  }

  /// Roles and names from this phone's own copy of the chat.
  Future<void> _loadPeople() async {
    try {
      final members = await _chat.fetchChannelMembers(widget.channelId);
      if (!mounted) return;
      setState(() {
        _isAdmin = members.any(
            (m) => m.userId == _me && (m.role == 'owner' || m.role == 'admin'));
        _names = {
          for (final m in members)
            if (m.contact != null) m.userId: m.contact!.displayLabel,
        };
      });
    } catch (_) {
      // Names fall back to 'Someone'; the server still decides.
    }
  }

  Future<void> _load() async {
    try {
      final page = await _chat.albumPage(widget.channelId, widget.albumId);
      if (!mounted) return;
      setState(() {
        _album = page.album;
        _photos = page.photos;
        _next = page.next;
        _failed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gone = e is AuthClientException &&
            (e.statusCode == 404 || e.statusCode == 403);
        _failed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _next;
    if (cursor == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final page = await _chat.albumPage(widget.channelId, widget.albumId,
          cursor: cursor);
      if (mounted) {
        setState(() {
          _photos = [...?_photos, ...page.photos];
          _next = page.next;
        });
      }
    } catch (_) {
      // The next scroll tries again.
    } finally {
      _loadingMore = false;
    }
  }

  Future<List<String>> _pick(bool camera) async {
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
            maxWidth: 2048, maxHeight: 2048, imageQuality: 85);
    return [
      for (final p in picked) await _chat.assets.importPicked(p.path),
    ];
  }

  Future<void> _addPhotos() async {
    final album = _album;
    if (album == null || _adding != null) return;
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    if (camera == null || !mounted) return;
    List<String> paths;
    try {
      paths = await (widget.pickPhotos ?? _pick)(camera);
    } on PlatformException catch (e) {
      if (mounted) _toast(context, 'Could not open the photos: ${e.code}');
      return;
    }
    if (paths.isEmpty || !mounted) return;
    setState(() => _adding = (0, paths.length));
    try {
      await _chat.addAlbumPhotos(album, paths, onAdded: (n) {
        if (mounted) setState(() => _adding = (n, paths.length));
      });
    } catch (e) {
      if (mounted) _toast(context, _failure(e, 'add the photos'));
    }
    if (!mounted) return;
    setState(() => _adding = null);
    await _load();
  }

  Future<void> _rename() async {
    final album = _album!;
    final title = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(title: 'Rename album', initial: album.title),
    );
    if (title == null || title.isEmpty || title == album.title) return;
    try {
      final edited = await _chat.editAlbum(album, title: title);
      if (mounted) setState(() => _album = edited);
    } catch (e) {
      if (mounted) _toast(context, _failure(e, 'rename the album'));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this album?'),
        content:
            const Text('Its photos are deleted for everyone in this chat.'),
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
    if (ok != true || !mounted) return;
    try {
      await _chat.deleteAlbum(_album!);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _toast(context, _failure(e, 'delete the album'));
    }
  }

  /// From the viewer: true once the server took it out.
  Future<bool> _removePhoto(AlbumPhoto photo) async {
    try {
      await _chat.removeAlbumPhoto(_album!, photo);
      if (mounted) {
        setState(() => _photos = [
              for (final p in _photos ?? const <AlbumPhoto>[])
                if (p.fileId != photo.fileId) p,
            ]);
      }
      return true;
    } catch (e) {
      if (mounted) _toast(context, _failure(e, 'remove the photo'));
      return false;
    }
  }

  void _view(int index) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AlbumPhotoViewer(
        photos: _photos!,
        initialIndex: index,
        nameOf: _nameOf,
        canRemove: _canRemove,
        onRemove: _removePhoto,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final album = _album;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(album?.title ?? 'Album',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (album?.date != null)
              Text(albumDate(album!.date!),
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (_canEdit && !_gone)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'rename' ? _rename() : _delete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete album')),
              ],
            ),
        ],
      ),
      body: _body(scheme),
      floatingActionButton: _gone || album == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _adding == null ? _addPhotos : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add photos', style: TextStyle(fontSize: 18)),
            ),
    );
  }

  Widget _body(ColorScheme scheme) {
    final photos = _photos;
    if (_gone) {
      return const _Notice(
        icon: Icons.photo_library_outlined,
        title: 'This album is not here any more',
        text: 'It was deleted, or you are no longer in this chat.',
      );
    }
    if (photos == null && _failed) {
      return _Notice(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load the album",
        text: 'Check your connection.',
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (photos == null) return const Center(child: CircularProgressIndicator());
    final adding = _adding;
    final keptUntil = _album?.keptUntil;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (adding != null) ...[
          LinearProgressIndicator(
              value: adding.$2 == 0 ? null : adding.$1 / adding.$2),
          Padding(
            padding: const EdgeInsets.all(kSpaceSm),
            child: Text('Added ${adding.$1} of ${adding.$2}…',
                textAlign: TextAlign.center),
          ),
        ],
        if (keptUntil != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                kSpaceMd, kSpaceSm, kSpaceMd, kSpaceSm),
            child: Text('Album kept until ${_day(keptUntil)}',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        Expanded(
          child: photos.isEmpty
              ? const _Notice(
                  icon: Icons.add_photo_alternate_outlined,
                  title: 'No photos yet',
                  text: 'Add the photos of the day. Everyone in this chat '
                      'can see them and add theirs.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.extentAfter < 600) _loadMore();
                      return false;
                    },
                    child: GridView.builder(
                      // Clear of the Add photos button.
                      padding: const EdgeInsets.only(bottom: 96),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                      ),
                      itemCount: photos.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => _view(i),
                        child: AssetImageView(
                          uri: photos[i].fileId,
                          placeholder: const AssetImagePlaceholder(),
                          fallback: const AssetImagePlaceholder(
                              icon: Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  const _Notice({
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
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
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

/// Full screen, swipe left and right, pinch to zoom. Save to phone, and
/// Remove for whoever may.
class AlbumPhotoViewer extends StatefulWidget {
  final List<AlbumPhoto> photos;
  final int initialIndex;
  final String Function(String userId) nameOf;
  final bool Function(AlbumPhoto) canRemove;
  final Future<bool> Function(AlbumPhoto) onRemove;

  /// Injected by tests; defaults to the app-wide cache.
  final AssetCache? cache;

  const AlbumPhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.nameOf,
    required this.canRemove,
    required this.onRemove,
    this.cache,
  });

  @override
  State<AlbumPhotoViewer> createState() => _AlbumPhotoViewerState();
}

class _AlbumPhotoViewerState extends State<AlbumPhotoViewer> {
  late final List<AlbumPhoto> _photos = [...widget.photos];
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  AlbumPhoto get _photo => _photos[_index];

  /// The system "Save to…" picker, so it lands where the user wants it.
  Future<void> _save() async {
    final bytes =
        await (widget.cache ?? AssetCache.instance)?.bytes(_photo.fileId);
    var saved = false;
    if (bytes != null) {
      try {
        saved = await FilePicker.saveFile(
              fileName: 'Vartalap-${_photo.fileId}.jpg',
              bytes: bytes,
              mimeType: 'image/jpeg',
            ) !=
            null;
      } catch (_) {
        saved = false;
      }
    }
    if (mounted) {
      _toast(
          context, saved ? 'Saved to your phone' : "Couldn't save the photo.");
    }
  }

  Future<void> _remove() async {
    final photo = _photo;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: const Text('It is removed for everyone in this chat.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !await widget.onRemove(photo) || !mounted) return;
    if (_photos.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _photos.remove(photo);
      _index = _index.clamp(0, _photos.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.nameOf(photo.uploader)),
            if (photo.addedAt > 0)
              Text(_day(photo.addedAt),
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Save to phone',
            onPressed: _save,
          ),
          if (widget.canRemove(photo))
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove photo',
              onPressed: _remove,
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: _photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 5,
          child: AssetImageView(
            uri: _photos[i].fileId,
            cache: widget.cache,
            fit: BoxFit.contain,
            placeholder: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            fallback: const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}
