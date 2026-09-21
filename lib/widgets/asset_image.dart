/// Image widgets backed by [AssetCache].
///
/// Everything that shows a stored image — chat bubbles, the media grid,
/// avatars — goes through here so one fileId is presigned, downloaded
/// and cached once no matter how many widgets want it.
library vartalap.widgets.asset_image;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vartalap/services/asset_cache.dart';

/// An image identified by an `Attachment.url` / `avatarUrl` — a local
/// path, an http url, or a media-ms fileId (see [AssetCache]).
///
/// Shows [placeholder] while the bytes are in flight and [fallback]
/// (defaulting to [placeholder]) if they never arrive. Both are
/// ordinary widgets, so a caller that wants an avatar's initials behind
/// a loading photo just passes them.
class AssetImageView extends StatelessWidget {
  final String uri;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget placeholder;
  final Widget? fallback;

  /// Injected by tests; defaults to the app-wide cache.
  final AssetCache? cache;

  const AssetImageView({
    super.key,
    required this.uri,
    required this.placeholder,
    this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cache,
  });

  @override
  Widget build(BuildContext context) {
    final c = cache ?? AssetCache.instance;
    if (c == null || uri.isEmpty) return fallback ?? placeholder;
    return FutureBuilder<Uint8List?>(
      future: c.bytes(uri),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return placeholder;
        final bytes = snap.data;
        if (bytes == null) return fallback ?? placeholder;
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback ?? placeholder,
        );
      },
    );
  }
}

/// Neutral block behind an image that hasn't loaded, so a bubble or a
/// grid tile keeps its shape instead of collapsing.
class AssetImagePlaceholder extends StatelessWidget {
  final Color? tint;
  final IconData icon;
  const AssetImagePlaceholder({
    super.key,
    this.tint,
    this.icon = Icons.image_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tint ?? scheme.onSurfaceVariant;
    return Container(
      alignment: Alignment.center,
      color: color.withValues(alpha: 0.08),
      child: Icon(icon, color: color.withValues(alpha: 0.6)),
    );
  }
}

/// Full-screen viewer — pinch to zoom, tap or back to dismiss. Share
/// and Save are out of scope for 3.0.
void showAssetViewer(
  BuildContext context, {
  required String uri,
  String? title,
  AssetCache? cache,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _AssetViewer(uri: uri, title: title, cache: cache),
    ),
  );
}

class _AssetViewer extends StatelessWidget {
  final String uri;
  final String? title;
  final AssetCache? cache;

  const _AssetViewer({required this.uri, this.title, this.cache});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: title == null ? null : Text(title!),
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: AssetImageView(
              uri: uri,
              cache: cache,
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
      ),
    );
  }
}
