/// A voice note in a bubble: play/pause, progress and the time.
///
/// One note plays at a time app-wide — starting another stops the
/// first — so the player, and which note it holds, are process-wide
/// like [AssetCache.instance].
library vartalap.screens.chat.voice_note;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;

/// `00:07`, `14:59` — the recording timer and the bubble's time.
String mmss(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:'
    '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Created on first play, so a chat that never plays anything (and a
/// widget test) never touches the audio plugin.
AudioPlayer? _player;

/// The `Attachment.url` loaded in [_player]; null when none is.
final ValueNotifier<String?> _loaded = ValueNotifier(null);

AudioPlayer _playerOrNew() {
  final existing = _player;
  if (existing != null) return existing;
  final player = _player = AudioPlayer();
  player.processingStateStream.listen((state) async {
    // Played to the end: back to the start, ready to play again.
    if (state != ProcessingState.completed) return;
    await player.pause();
    await player.seek(Duration.zero);
  });
  return player;
}

/// Stop whatever note is playing — the chat it lives in was left.
Future<void> stopVoiceNote() async {
  await _player?.stop();
  // After the await on purpose: called from a dispose, when the tree
  // is locked and another chat's bubbles may be listening.
  _loaded.value = null;
}

/// A file the player can open. Our own note is one already until its
/// upload lands; anything else goes through [AssetCache] to a temp file.
Future<String?> _playablePath(pb.Attachment a) async {
  if (a.url.startsWith('/')) return a.url;
  final bytes = await AssetCache.instance?.bytes(a.url);
  if (bytes == null) return null;
  final file = File(
    '${(await getTemporaryDirectory()).path}/'
    '${safeFileName(a.url)}.${extForPath(a.filename)}',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

class VoiceNoteView extends StatelessWidget {
  final pb.Attachment attachment;
  final Color tint;

  /// The bubble's time + tick, on the length's line (WhatsApp).
  final Widget? footer;

  const VoiceNoteView({
    super.key,
    required this.attachment,
    required this.tint,
    this.footer,
  });

  Future<void> _toggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final player = _playerOrNew();
    if (_loaded.value == attachment.url) {
      if (player.playing) {
        await player.pause();
      } else {
        // play() completes only when playback stops; don't wait on it.
        unawaited(player.play());
      }
      return;
    }
    _loaded.value = attachment.url;
    await player.stop();
    try {
      final path = await _playablePath(attachment);
      // Another note was tapped while this one was loading.
      if (_loaded.value != attachment.url) return;
      if (path == null) throw StateError('no bytes');
      await player.setFilePath(path);
      unawaited(player.play());
    } catch (_) {
      // Interrupted by another note: that one owns the player now.
      if (_loaded.value != attachment.url) return;
      _loaded.value = null;
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't play this voice message")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = Duration(milliseconds: attachment.durationMs);
    return ValueListenableBuilder<String?>(
      valueListenable: _loaded,
      builder: (context, loaded, _) {
        final player = _player;
        if (loaded != attachment.url || player == null) {
          return _row(context,
              playing: false, position: Duration.zero, total: sent);
        }
        return StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, _) => StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, _) => _row(
              context,
              playing: player.playing,
              position: player.position,
              total: player.duration ?? sent,
            ),
          ),
        );
      },
    );
  }

  Widget _row(
    BuildContext context, {
    required bool playing,
    required Duration position,
    required Duration total,
  }) {
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final time = footer;
    return SizedBox(
      width: 240,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 6, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: tint.withValues(alpha: 0.1),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _toggle(context),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 30,
                    color: tint,
                    semanticLabel: playing ? 'Pause' : 'Play voice message',
                  ),
                ),
              ),
            ),
            const SizedBox(width: kSpaceSm + kSpaceXs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Puts the bar on the button's centre line.
                  const SizedBox(height: 20),
                  // ponytail: a bar, no seek; a Slider here when someone
                  // asks to scrub.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      color: tint,
                      backgroundColor: tint.withValues(alpha: 0.2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        // Total while idle, position once started.
                        mmss(playing || position > Duration.zero
                            ? position
                            : total),
                        style: TextStyle(
                          color: tint.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      if (time != null) time,
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
