/// Resolve an `Attachment.url` / `avatarUrl` to bytes, once.
///
/// Three shapes land here and all three are just "a string somebody
/// stored":
///   - an absolute local path — our own not-yet-uploaded file;
///   - an `http(s)://` url — a peer on some other server;
///   - a media-ms fileId — everything else, which needs a presigned
///     `GET` before it can be fetched.
///
/// Downloads are memoized in memory and on disk (app documents dir,
/// keyed by fileId), so scrolling a chat or opening "Media, links and
/// docs" twice costs nothing. Presigned urls expire, so only the bytes
/// are cached on disk; the url itself is re-signed on a cold read.
library vartalap.services.asset_cache;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// Extension → MIME for the handful of things a picker hands us.
/// `application/octet-stream` is a fine answer for everything else —
/// media-ms signs the type it derives from the extension either way.
String mimeForPath(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'mp4' => 'video/mp4',
    'mp3' => 'audio/mpeg',
    _ => 'application/octet-stream',
  };
}

/// Bare extension without the dot (`png`), `bin` when there is none —
/// media-ms requires a non-empty `ext` on the presign call.
String extForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return 'bin';
  return path.substring(dot + 1).toLowerCase();
}

class AssetCache {
  /// Installed by [ChatService] at construction. Widgets deep in the
  /// tree (avatars, bubbles) read it here rather than having it threaded
  /// through every constructor between them and `main.dart`.
  ///
  /// ponytail: a process-global because the cache is one per app and
  /// `AppServices` lives in main.dart, which this change must not
  /// touch. Move it into `AppServices` when that file is next open.
  static AssetCache? instance;

  /// Where the file cache lives. Overridable because
  /// `path_provider` has no platform channel under `flutter test`.
  static Future<Directory> Function() dirProvider = () async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}/assets');

  final AssetClient client;

  final Map<String, Uint8List> _mem = {};
  final Map<String, Future<Uint8List?>> _inflight = {};
  Future<Directory>? _dir;

  AssetCache({required this.client});

  Future<Directory> get dir async =>
      _dir ??= dirProvider().then((d) async => d.create(recursive: true));

  /// Bytes for [uri], or null if they cannot be had (unknown fileId,
  /// deleted local file, no network). Never throws: every caller is a
  /// widget that must render something regardless.
  Future<Uint8List?> bytes(String uri) {
    if (uri.isEmpty) return Future.value(null);
    final cached = _mem[uri];
    if (cached != null) return Future.value(cached);
    return _inflight[uri] ??= _load(uri).whenComplete(() {
      _inflight.remove(uri);
    });
  }

  Future<Uint8List?> _load(String uri) async {
    try {
      if (uri.startsWith('/')) {
        final f = File(uri);
        if (!await f.exists()) return null;
        return _mem[uri] = await f.readAsBytes();
      }
      if (!uri.startsWith('http')) {
        // A fileId: disk cache first, then presign + download.
        final f = File('${(await dir).path}/$uri');
        if (await f.exists()) return _mem[uri] = await f.readAsBytes();
        final bytes = await client.download(await client.downloadUrl(uri));
        await f.writeAsBytes(bytes, flush: true);
        return _mem[uri] = bytes;
      }
      return _mem[uri] = await client.download(uri);
    } catch (_) {
      // Missing file, 404, expired signature, offline. The widget shows
      // its placeholder and a later rebuild retries.
      return null;
    }
  }

  /// Copy a picked file out of the picker's temp dir, which the OS is
  /// free to sweep, into ours — the upload op may not run for hours.
  /// Returns the new absolute path.
  Future<String> importPicked(String sourcePath) async {
    final base = await dir;
    final name = '${DateTime.now().microsecondsSinceEpoch}-'
        '${sourcePath.split('/').last}';
    final copied = await File(sourcePath).copy('${base.path}/$name');
    return copied.path;
  }

  /// Point [from] (a local path) at [to] (the fileId it uploaded to)
  /// without re-reading the bytes we already hold.
  void rekey(String from, String to) {
    final bytes = _mem[from];
    if (bytes != null) _mem[to] = bytes;
  }
}

/// Pick one photo and copy it somewhere durable. Returns the new local
/// path, or null if the user backed out (or there is no picker — a
/// widget test, a platform without one).
Future<String?> pickPhoto(AssetCache cache) async {
  try {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    return await cache.importPicked(picked.path);
  } catch (_) {
    return null;
  }
}
