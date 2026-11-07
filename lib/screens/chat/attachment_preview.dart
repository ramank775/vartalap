import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/attachment_text.dart';

/// What the preview pops on send: the trimmed caption ('' for none), and
/// whether a photo goes in HD.
typedef AttachmentChoice = ({String caption, bool hd});

/// The look before sending (WhatsApp's send preview): the picked photo
/// full screen, or a card for anything else, and a caption field. A photo
/// from the camera or gallery ([offerHd]) offers HD (decision 130's
/// standard size otherwise). Pops an [AttachmentChoice] on send, null on
/// cancel.
///
/// ponytail: one item, no crop/draw; multi-select slots in here when
/// wanted.
class AttachmentPreviewScreen extends StatefulWidget {
  final String path;
  final bool offerHd;

  const AttachmentPreviewScreen(
      {super.key, required this.path, this.offerHd = false});

  @override
  State<AttachmentPreviewScreen> createState() =>
      _AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends State<AttachmentPreviewScreen> {
  final _caption = TextEditingController();
  bool _hd = false;

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
    final mime = mimeForPath(widget.path);
    final card = _FileCard(path: widget.path, mime: mime);
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
              child: Center(
                child: mime.startsWith('image/')
                    ? InteractiveViewer(
                        child: Image.file(
                          File(widget.path),
                          // Never decode a 12 MP original just to look.
                          cacheWidth: 1440,
                          errorBuilder: (_, __, ___) => card,
                        ),
                      )
                    : card,
              ),
            ),
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
}

/// What a document, video or audio file looks like before sending:
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
            switch (mime.split('/').first) {
              'video' => Icons.play_circle_outline,
              'audio' => Icons.headphones,
              _ => Icons.insert_drive_file_outlined,
            },
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
