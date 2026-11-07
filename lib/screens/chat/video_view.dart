/// Videos in the app, as WhatsApp: [VideoView] plays a local file in
/// place, over its first frame until Play; [VideoPlayerScreen] is the
/// full-screen player a video bubble opens, with "Open with…" for another
/// app. video_player is the Flutter team's (ExoPlayer on Android, no Play
/// services). A received video plays from the opened copy
/// [AssetCache.file] keeps on disk, never from the encrypted download.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat/voice_note.dart' show mmss;
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:video_player/video_player.dart';

Future<void> showVideoPlayer(BuildContext context, pb.Attachment video) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VideoPlayerScreen(video: video),
    ));

/// Full screen on black: the video plays at once, tap to pause, a seek
/// bar with the time, and ⋮ › Open with….
class VideoPlayerScreen extends StatefulWidget {
  final pb.Attachment video;

  /// Injected by tests; defaults to the app-wide cache.
  final AssetCache? cache;

  const VideoPlayerScreen({super.key, required this.video, this.cache});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final AssetCache? _cache = widget.cache ?? AssetCache.instance;
  late final Future<String?> _file =
      _cache?.file(widget.video.url) ?? Future.value(null);

  String get _name =>
      widget.video.filename.isEmpty ? 'Video' : widget.video.filename;

  Future<void> _openWith() async {
    final messenger = ScaffoldMessenger.of(context);
    final cache = _cache;
    final ok = cache != null &&
        await openAttachment(cache,
            uri: widget.video.url, name: _name, mime: widget.video.mimeType);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't open $_name")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = widget.video.thumbnail;
    final poster = thumb.isEmpty
        ? const SizedBox.expand()
        : Image.memory(Uint8List.fromList(thumb),
            fit: BoxFit.contain, gaplessPlayback: true);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: widget.video.filename.isEmpty ? null : Text(_name),
        actions: [
          PopupMenuButton<void>(
            tooltip: 'More options',
            itemBuilder: (_) => [
              PopupMenuItem(onTap: _openWith, child: const Text('Open with…')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<String?>(
          future: _file,
          builder: (context, snap) =>
              snap.connectionState != ConnectionState.done
                  ? Stack(fit: StackFit.expand, children: [
                      poster,
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ])
                  : VideoView(path: snap.data, poster: poster, autoplay: true),
        ),
      ),
    );
  }
}

/// A video file playing in place: [poster] with a play button until
/// tapped (or at once with [autoplay]), then the video, tap to pause, and
/// a seek bar with the time under it. [path] null: nothing to play.
class VideoView extends StatefulWidget {
  final String? path;
  final Widget poster;
  final bool autoplay;

  const VideoView({
    super.key,
    required this.path,
    required this.poster,
    this.autoplay = false,
  });

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  VideoPlayerController? _player;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) _player = _open();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  VideoPlayerController? _open() {
    final path = widget.path;
    if (path == null) {
      _failed = true;
      return null;
    }
    final player = VideoPlayerController.file(File(path));
    player.initialize().then((_) => player.play()).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    return player;
  }

  void _start() => setState(() => _player = _open());

  Widget _overPoster(Widget middle) => Stack(
        fit: StackFit.expand,
        children: [widget.poster, Center(child: middle)],
      );

  static Widget _bigPlay(VoidCallback onPressed) => IconButton(
        iconSize: 48,
        tooltip: 'Play video',
        style: IconButton.styleFrom(
          backgroundColor: Colors.black45,
          foregroundColor: Colors.white,
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.play_arrow_rounded),
      );

  @override
  Widget build(BuildContext context) {
    const failed = Text("Couldn't play this video",
        style: TextStyle(color: Colors.white, fontSize: 16));
    final player = _player;
    if (_failed) return _overPoster(failed);
    if (player == null) return _overPoster(_bigPlay(_start));
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (context, v, _) {
        if (v.hasError) return _overPoster(failed);
        if (!v.isInitialized) {
          return _overPoster(
              const CircularProgressIndicator(color: Colors.white));
        }
        void toggle() => v.isPlaying ? player.pause() : player.play();
        final length = v.duration.inMilliseconds;
        return Column(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: toggle,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: v.aspectRatio,
                        child: VideoPlayer(player),
                      ),
                    ),
                    if (!v.isPlaying) Center(child: _bigPlay(toggle)),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  color: Colors.white,
                  tooltip: v.isPlaying ? 'Pause' : 'Play',
                  onPressed: toggle,
                  icon: Icon(v.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                ),
                Text(mmss(v.position),
                    style: const TextStyle(color: Colors.white)),
                Expanded(
                  child: Slider(
                    value:
                        math.min(v.position.inMilliseconds, length).toDouble(),
                    max: math.max(length, 1).toDouble(),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white38,
                    onChanged: (ms) =>
                        player.seekTo(Duration(milliseconds: ms.round())),
                  ),
                ),
                Text(mmss(v.duration),
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(width: 12),
              ],
            ),
          ],
        );
      },
    );
  }
}
