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
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart';
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
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    '3gp' => 'video/3gpp',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'ogg' || 'opus' => 'audio/ogg',
    'zip' => 'application/zip',
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

  /// How far each upload under way has got, 0 to 1, by the local path
  /// its bubble shows until it is up (SYNC_PROTOCOL §25.4).
  final ValueNotifier<Map<String, double>> uploads = ValueNotifier(const {});

  /// [AssetUploadTransport.onProgress]; null when [path] is done. Whole
  /// percents only, so a 25 MB file repaints its bubble 100 times, not 400.
  void reportUpload(String path, double? done) {
    final was = uploads.value[path];
    final same = done == null
        ? was == null
        : (done * 100).floor() == ((was ?? -1) * 100).floor();
    if (same) return;
    final next = {...uploads.value}..remove(path);
    uploads.value = done == null ? next : {...next, path: done};
  }

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
        // A fileId, `#key` for an end-to-end encrypted one (decision
        // 188): disk cache first (the opened bytes, by fileId), then
        // presign + download + open.
        final (:object, :key) = parseAttachmentUrl(uri);
        final f = File('${(await dir).path}/$object');
        if (await f.exists()) return _mem[uri] = await f.readAsBytes();
        var bytes = await client.download(await client.downloadUrl(object));
        if (key != null) {
          final sealed = bytes;
          bytes = await Isolate.run(() => openSealedAttachment(key, sealed));
        }
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
    final to = await durablePath(sourcePath.split('/').last);
    return (await File(sourcePath).copy(to)).path;
  }

  /// Where to keep a file named [name] until it is sent and after. A
  /// unique folder, not a name prefix: the basename is what the recipient
  /// sees as the file name.
  Future<String> durablePath(String name) async {
    final folder = await Directory(
      '${(await dir).path}/${DateTime.now().microsecondsSinceEpoch}',
    ).create();
    return '${folder.path}/$name';
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
    // Avatars render at most a screen wide; every contact downloads one.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 640,
      maxHeight: 640,
      imageQuality: 85,
    );
    if (picked == null) return null;
    return await cache.importPicked(picked.path);
  } catch (_) {
    return null;
  }
}

const _media = MethodChannel('vartalap/media');

/// A picked photo made ready to send (decision 130, SYNC_PROTOCOL §25.4):
/// a JPEG about 2048 px on its long side at quality 85, or with [hd] up to
/// 4096 at 92; turned upright and with its EXIF (location too) left out.
/// Kept in [cache]'s durable folder. Null when the phone cannot make one
/// (it will not decode, no platform side): send the picked file.
Future<({String path, int width, int height})?> preparePhoto(
    AssetCache cache, String picked,
    {bool hd = false}) async {
  final name = picked.split('/').last;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final out = await cache.durablePath('$base.jpg');
  try {
    final size = await _media.invokeListMethod<int>('photo', {
      'path': picked,
      'out': out,
      'maxSide': hd ? 4096 : 2048,
      'quality': hd ? 92 : 85,
    });
    if (size != null && size.length == 2) {
      return (path: out, width: size[0], height: size[1]);
    }
  } on Exception {
    // Sent as picked.
  }
  return null;
}

/// A sent video's thumbnail (SYNC_PROTOCOL §25.4): its first frame as a
/// small JPEG, and the video's upright size and length. Null when the
/// phone cannot read it.
Future<({Uint8List jpeg, int width, int height, int durationMs})?>
    videoThumbnail(String video) async {
  final out = File('$video.thumb.jpg');
  try {
    final info = await _media.invokeMapMethod<String, int>(
        'videoThumbnail', {'path': video, 'out': out.path});
    if (info == null || !await out.exists()) return null;
    return (
      jpeg: await out.readAsBytes(),
      width: info['width'] ?? 0,
      height: info['height'] ?? 0,
      durationMs: info['durationMs'] ?? 0,
    );
  } on Exception {
    return null;
  } finally {
    if (await out.exists()) await out.delete();
  }
}

/// The sender chose [name]: keep a bare basename so it cannot climb
/// out of the folder we write it into.
String safeFileName(String name) {
  final base = name.split(RegExp(r'[/\\]')).last;
  return (base.isEmpty || base == '.' || base == '..') ? 'attachment' : base;
}

/// Fetch an attachment and hand it to whatever installed app opens
/// [mime]; when none does, offer the system "Save to…" picker instead.
/// False if the bytes could not be had or the hand-off failed.
Future<bool> openAttachment(
  AssetCache cache, {
  required String uri,
  required String name,
  required String mime,
}) async {
  try {
    final bytes = await cache.bytes(uri);
    if (bytes == null) return false;
    final safe = safeFileName(name);
    final dir = await Directory(
      '${(await getTemporaryDirectory()).path}/open',
    ).create(recursive: true);
    final file = await File('${dir.path}/$safe').writeAsBytes(bytes);
    final opened = await const MethodChannel('vartalap/files')
        .invokeMethod<bool>('open', {
      'path': file.path,
      'mime': mime.isEmpty ? '*/*' : mime,
    });
    if (opened != true) {
      await FilePicker.saveFile(fileName: safe, bytes: bytes, mimeType: mime.isEmpty ? 'application/octet-stream' : mime);
    }
    return true;
  } catch (_) {
    return false;
  }
}
