import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vartalap/screens/chat/video_view.dart';
import 'package:vartalap/screens/chat/voice_note.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/attachment_text.dart';

/// What the preview pops on send: the trimmed caption ('' for none), and
/// whether a photo goes in HD.
typedef AttachmentChoice = ({String caption, bool hd});

/// The look before sending (WhatsApp's send preview): the picked photo
/// full screen, a video on its first frame that plays in place, or a card
/// for anything else, and a caption field. A photo
/// from the camera or gallery ([offerHd]) offers HD (decision 130's
/// standard size otherwise). Pops an [AttachmentChoice] on send, null on
/// cancel.
///
/// ponytail: no crop/draw, one caption for several items.
class AttachmentPreviewScreen extends StatefulWidget {
  final String path;
  final bool offerHd;

  /// Further files sent with [path] (share-to): a strip switches between
  /// them, and the caption goes with the first.
  final List<String> more;

  const AttachmentPreviewScreen(
      {super.key,
      required this.path,
      this.offerHd = false,
      this.more = const []});

  @override
  State<AttachmentPreviewScreen> createState() =>
      _AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends State<AttachmentPreviewScreen> {
  final _caption = TextEditingController();
  bool _hd = false;
  late final _paths = [widget.path, ...widget.more];
  int _shown = 0;

  /// A video's first frame, as its bubble will show it (decision 240).
  /// ponytail: made again on send; pass it along if that ever shows.
  final _frames = <String, Future<Uint8List?>>{};
  Future<Uint8List?> _frame(String video) =>
      _frames[video] ??= videoThumbnail(video).then((t) => t?.jpeg);

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _send() => Navigator.of(context)
      .pop<AttachmentChoice>((caption: _caption.text.trim(), hd: _hd));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = _paths[_shown];
    final mime = mimeForPath(path);
    final card = _FileCard(path: path, mime: mime);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (widget.offerHd)
            IconButton(
              icon: Icon(_hd ? Icons.hd : Icons.hd_outlined),
              tooltip: _hd ? 'HD quality' : 'Standard quality',
              isSelected: _hd,
              onPressed: () {
                setState(() => _hd = !_hd);
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(
                    duration: const Duration(seconds: 2),
                    content: Text(_hd
                        ? 'HD quality: sharper, a bigger file to send'
                        : 'Standard quality: smaller, faster to send'),
                  ));
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: mime.startsWith('video/')
                  ? FutureBuilder<Uint8List?>(
                      future: _frame(path),
                      builder: (context, snap) => VideoView(
                        key: ValueKey(path),
                        path: path,
                        poster: snap.data == null
                            ? const SizedBox.expand()
                            : Image.memory(snap.data!, fit: BoxFit.contain),
                      ),
                    )
                  : Center(
                    child: mime.startsWith('image/')
                        ? InteractiveViewer(
                            key: ValueKey(path),
                            child: Image.file(
                              File(path),
                              // Never decode a 12 MP original just to look.
                              cacheWidth: 1440,
                              errorBuilder: (_, __, ___) => card,
                            ),
                          )
                        : card,
                  ),
            ),
            if (_paths.length > 1) _strip(scheme),
            Padding(
              padding: const EdgeInsets.all(kSpaceSm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _caption,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        hintText: 'Add a caption…',
                        hintStyle: const TextStyle(color: Colors.white60),
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: kSpaceMd,
                          vertical: kSpaceSm + kSpaceXs,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: kSpaceSm),
                  Material(
                    color: scheme.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _send,
                      child: Padding(
                        padding: const EdgeInsets.all(kSpaceSm + kSpaceXs),
                        child: Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: scheme.onPrimary,
                          semanticLabel: 'Send',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// WhatsApp's row of everything being sent; tap one to look at it.
  Widget _strip(ColorScheme scheme) => SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: kSpaceSm),
          itemCount: _paths.length,
          separatorBuilder: (_, __) => const SizedBox(width: kSpaceXs),
          itemBuilder: (_, i) {
            final mime = mimeForPath(_paths[i]);
            final glyph = Icon(_glyph(mime), color: Colors.white70);
            return Semantics(
              button: true,
              selected: i == _shown,
              label: _paths[i].split('/').last,
              child: GestureDetector(
                onTap: () => setState(() => _shown = i),
                child: Container(
                  width: 56,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(kRadiusSm),
                    border: Border.all(
                      color: i == _shown ? scheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: mime.startsWith('image/')
                      ? Image.file(
                          File(_paths[i]),
                          fit: BoxFit.cover,
                          cacheWidth: 112,
                          errorBuilder: (_, __, ___) => glyph,
                        )
                      : glyph,
                ),
              ),
            );
          },
        ),
      );
}

IconData _glyph(String mime) => switch (mime.split('/').first) {
      'video' => Icons.play_circle_outline,
      'audio' => Icons.headphones,
      _ => Icons.insert_drive_file_outlined,
    };

/// What a document or audio file looks like before sending:
/// its glyph, name and size.
class _FileCard extends StatelessWidget {
  final String path;
  final String mime;

  const _FileCard({required this.path, required this.mime});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return Padding(
      padding: const EdgeInsets.all(kSpaceLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _glyph(mime),
            size: 96,
            color: Colors.white70,
          ),
          const SizedBox(height: kSpaceMd),
          Text(
            path.split('/').last,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: kSpaceXs),
          Text(
            humanFileSize(file.existsSync() ? file.lengthSync() : 0),
            style: const TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

/// A file ready for [ChatService.sendAttachment]: where it is now, and
/// what the bubble shows before the bytes land.
typedef PreparedFile = ({
  String path,
  int width,
  int height,
  int durationMs,
  Uint8List? thumbnail,
});

/// A picked or shared file made ready for [ChatService.sendAttachment],
/// the one way a file is sent: copied out of the picker's or the share's
/// temp folder (the upload may not run for hours). [media] (camera,
/// gallery, a shared photo or video): a photo is sized for sending, HD
/// on request (decision 130), a video gets its first frame. Anything
/// else goes byte for byte. Sizes let the bubble keep its shape before
/// the bytes land; an audio file's length shows before it plays.
Future<PreparedFile> prepareAttachment(AssetCache assets, String sourcePath,
    {required bool media, bool hd = false}) async {
  final mime = mimeForPath(sourcePath);
  final photo = media && mime.startsWith('image/') && mime != 'image/gif';
  final ready = photo ? await preparePhoto(assets, sourcePath, hd: hd) : null;
  final path = ready?.path ?? await assets.importPicked(sourcePath);
  var (width, height, durationMs) = (ready?.width ?? 0, ready?.height ?? 0, 0);
  Uint8List? thumbnail;
  if (ready == null && mime.startsWith('image/')) {
    final size = await _decodeSize(path);
    (width, height) = (size?.$1 ?? 0, size?.$2 ?? 0);
  } else if (media && mime.startsWith('video/')) {
    final video = await videoThumbnail(path);
    if (video != null) {
      (width, height, durationMs) =
          (video.width, video.height, video.durationMs);
      thumbnail = video.jpeg;
    }
  } else if (mime.startsWith('audio/')) {
    durationMs = await audioLengthMs(path);
  }
  return (
    path: path,
    width: width,
    height: height,
    durationMs: durationMs,
    thumbnail: thumbnail,
  );
}

/// Intrinsic pixel size of an image, or null if it will not decode (the
/// bubble then falls back to a fixed height).
Future<(int, int)?> _decodeSize(String path) async {
  try {
    final codec =
        await ui.instantiateImageCodec(await File(path).readAsBytes());
    final frame = await codec.getNextFrame();
    final size = (frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}
