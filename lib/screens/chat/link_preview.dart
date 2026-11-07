/// Link previews in the chat (SYNC_PROTOCOL §27): the composer's card,
/// fetched by this phone as the link is typed, and the card in a text
/// bubble, which shows only what the sender's phone fetched.
library vartalap.screens.chat.link_preview;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vartalap/services/link_preview.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart' show MessageRow;

/// What the composer fetches previews with; tests swap it.
Future<pb.ChatLinkPreview?> Function(String url) linkPreviewFetcher =
    fetchLinkPreview;

/// The composer's preview: a moment after the first link in [input]
/// changes, its preview is fetched; [value] is it once ready, for that
/// link. Nothing is fetched while [enabled] says no (the setting is off;
/// a secure, timed or edited message).
class ComposerLinkPreview extends ValueNotifier<pb.ChatLinkPreview?> {
  ComposerLinkPreview(
    this.input, {
    required this.enabled,
    this.debounce = const Duration(milliseconds: 800),
  }) : super(null) {
    input.addListener(_onText);
  }

  final TextEditingController input;
  final bool Function() enabled;
  final Duration debounce;

  String? _url;
  String? _dismissed;
  Timer? _timer;

  void _onText() {
    final url = enabled() ? firstLink(input.text) : null;
    if (url == _url) return;
    _url = url;
    _timer?.cancel();
    value = null;
    if (url == null) _dismissed = null;
    if (url == null || url == _dismissed) return;
    _timer = Timer(debounce, () async {
      final preview = await linkPreviewFetcher(url);
      if (url == _url && url != _dismissed) value = preview;
    });
  }

  /// The card's ✕: no preview for this link in this message.
  void dismiss() {
    _dismissed = _url;
    _timer?.cancel();
    value = null;
  }

  /// The preview to send with [body], when it is ready and still of its
  /// first link. Sending never waits for one.
  pb.ChatLinkPreview? previewFor(String body) {
    final p = value;
    return p != null && enabled() && firstLink(body) == p.url ? p : null;
  }

  @override
  void dispose() {
    _url = null; // a fetch still running lands nowhere
    _timer?.cancel();
    input.removeListener(_onText);
    super.dispose();
  }
}

/// The compact card over the composer's text while [controller] has a
/// preview to send: thumbnail, title, domain, and a ✕ that drops it.
class ComposerLinkPreviewCard extends StatelessWidget {
  final ComposerLinkPreview controller;

  const ComposerLinkPreviewCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, _, __) {
          final p = controller.previewFor(controller.input.text);
          return p == null ? const SizedBox.shrink() : _card(context, p);
        },
      );

  Widget _card(BuildContext context, pb.ChatLinkPreview preview) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: ColoredBox(
          color: scheme.surface.withValues(alpha: 0.7),
          child: Row(
            children: [
              if (preview.imageJpeg.isNotEmpty)
                Image.memory(
                  Uint8List.fromList(preview.imageJpeg),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              const SizedBox(width: kSpaceSm + kSpaceXs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _heading(preview),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      linkPreviewDomain(preview),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove preview',
                onPressed: controller.dismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [m]'s preview to show in its bubble: only while it is of the first
/// link in the text, so an edit that took the link out drops it and a
/// tap opens what the text says.
pb.ChatLinkPreview? bubbleLinkPreview(MessageRow m) {
  final bytes = m.linkPreview;
  if (bytes == null || m.tombstoned) return null;
  try {
    final p = pb.ChatLinkPreview.fromBuffer(bytes);
    return firstLink(m.body ?? '') == p.url ? p : null;
  } catch (_) {
    return null;
  }
}

/// The card at the top of a text bubble, as WhatsApp's: the image, the
/// title and description (two lines each) and the site. A tap opens the
/// link.
class LinkPreviewCard extends StatelessWidget {
  final pb.ChatLinkPreview preview;
  final Color tint;

  /// About an image bubble's width, so a short link still gets a card.
  static const double width = 240;

  const LinkPreviewCard({super.key, required this.preview, required this.tint});

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(preview.url);
    final ok = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication)
            .catchError((_) => false);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open this link")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = tint.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.only(bottom: kSpaceXs),
      child: GestureDetector(
        onTap: () => _open(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kRadiusSm),
          child: Container(
            width: width,
            color: tint.withValues(alpha: 0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (preview.imageJpeg.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: Image.memory(
                      Uint8List.fromList(preview.imageJpeg),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(kSpaceSm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_heading(preview).isNotEmpty)
                        Text(
                          _heading(preview),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: tint,
                          ),
                        ),
                      if (preview.description.isNotEmpty &&
                          preview.description != _heading(preview))
                        Text(
                          preview.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                      Text(
                        linkPreviewDomain(preview),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The link's host without "www.".
String linkPreviewDomain(pb.ChatLinkPreview p) {
  final host = Uri.tryParse(p.url)?.host ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}

String _heading(pb.ChatLinkPreview p) => [p.title, p.siteName, p.description]
    .firstWhere((s) => s.isNotEmpty, orElse: () => '');
