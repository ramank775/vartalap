/// Shared test double for [AssetCache].
///
/// Widgets resolve an `Attachment.url` / `avatarUrl` through the cache,
/// which in production means a presigned GET and a download. Tests
/// hand it the bytes instead.
library vartalap.test.fake_asset_cache;

import 'dart:convert';
import 'dart:typed_data';

import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// A real 1×1 PNG — `Image.memory` needs bytes it can actually decode.
final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM'
  'IQAAAABJRU5ErkJggg==',
);

class FakeAssetCache extends AssetCache {
  /// Keyed by the whole uri, or by its last path segment so an
  /// `https://host/shot.jpg` and a bare fileId both hit.
  final Map<String, Uint8List> blobs;

  FakeAssetCache(this.blobs)
      : super(
          client: AssetClient(
            baseUrl: Uri.parse('https://example.invalid'),
            auth: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          ),
        );

  @override
  Future<Uint8List?> bytes(String uri) async =>
      blobs[uri] ?? blobs[uri.split('/').last];
}
