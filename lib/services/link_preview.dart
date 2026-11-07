/// Link previews (SYNC_PROTOCOL §27): the sender's phone fetches the page
/// and its image; the preview rides inside the end-to-end encrypted
/// message, so the people it goes to never contact the website.
library vartalap.services.link_preview;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart' show ChatStore;

const String kLinkPreviewUserAgent = 'Vartalap/3 (link preview)';
const Duration kLinkPreviewTimeout = Duration(seconds: 5);
const int kLinkPreviewPageBytes = 512 * 1024;
const int kLinkPreviewImageBytes = 2 * 1024 * 1024;
const int kLinkPreviewRedirects = 3;

/// Resolves a host name; [InternetAddress.lookup] outside tests.
typedef HostLookup = Future<List<InternetAddress>> Function(String host);

/// The first http(s) URL in [text], or null.
String? firstLink(String text) =>
    ChatStore.linkPattern.firstMatch(text)?.group(0);

/// The preview of [url], or null when there is none to be had: the site
/// is private, slow, not HTML, or says nothing about itself. Never
/// throws. [shrink] makes the page's image small ([shrinkImage]).
Future<pb.ChatLinkPreview?> fetchLinkPreview(
  String url, {
  http.Client? client,
  HostLookup lookup = InternetAddress.lookup,
  Future<Uint8List?> Function(Uint8List image) shrink = shrinkImage,
}) async {
  final typed = Uri.tryParse(url);
  if (typed == null || !(typed.isScheme('http') || typed.isScheme('https'))) {
    return null;
  }
  final c = client ?? http.Client();
  try {
    // https first, even for a link typed as http.
    _Got? page;
    for (final u in [
      if (typed.isScheme('http')) typed.replace(scheme: 'https'),
      typed,
    ]) {
      page = await _get(c, u, lookup, 'text/html', kLinkPreviewPageBytes)
          .timeout(kLinkPreviewTimeout)
          .catchError((Object _) => null);
      if (page != null) break;
    }
    if (page == null) return null;
    final text = utf8.decode(page.bytes, allowMalformed: true);
    final meta = await Isolate.run(() => parsePageMeta(text));
    if (meta.title.isEmpty && meta.description.isEmpty) return null;

    Uint8List? jpeg;
    final ref = meta.image.isEmpty ? null : Uri.tryParse(meta.image);
    final imageUrl = ref == null ? null : page.url.resolveUri(ref);
    if (imageUrl != null) {
      final image =
          await _get(c, imageUrl, lookup, 'image/', kLinkPreviewImageBytes)
              .timeout(kLinkPreviewTimeout)
              .catchError((Object _) => null);
      if (image != null) jpeg = await shrink(image.bytes);
    }
    return pb.ChatLinkPreview(
      url: url,
      title: _cap(meta.title, 200),
      description: _cap(meta.description, 300),
      siteName: _cap(meta.siteName, 100),
      imageJpeg: jpeg,
    );
  } catch (_) {
    return null;
  } finally {
    // Also ends a request still running past its timeout.
    if (client == null) c.close();
  }
}

typedef _Got = ({Uri url, Uint8List bytes});

/// GET [url] within the preview's limits: public hosts only, checked at
/// every hop; at most [kLinkPreviewRedirects] redirects; a content type
/// starting [type]. A page is cut at [max] bytes (its head is what
/// counts); anything else longer is refused.
Future<_Got?> _get(
    http.Client c, Uri url, HostLookup lookup, String type, int max) async {
  for (var hop = 0; hop <= kLinkPreviewRedirects; hop++) {
    if (!(url.isScheme('http') || url.isScheme('https')) ||
        !await isPublicHost(url.host, lookup)) {
      return null;
    }
    final res = await c.send(http.Request('GET', url)
      ..followRedirects = false
      ..headers['user-agent'] = kLinkPreviewUserAgent
      ..headers['accept'] = type == 'image/' ? 'image/*' : type);
    final location = res.headers['location'];
    if (const {301, 302, 303, 307, 308}.contains(res.statusCode) &&
        location != null) {
      unawaited(res.stream.listen(null).cancel());
      url = url.resolve(location);
      continue;
    }
    final cut = type == 'text/html';
    if (res.statusCode != 200 ||
        !(res.headers['content-type'] ?? '').toLowerCase().startsWith(type) ||
        (!cut && (res.contentLength ?? 0) > max)) {
      unawaited(res.stream.listen(null).cancel());
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in res.stream) {
      bytes.add(chunk);
      if (bytes.length > max) {
        if (!cut) return null;
        break;
      }
    }
    final all = bytes.takeBytes();
    return (
      url: url,
      bytes: all.length > max ? Uint8List.sublistView(all, 0, max) : all,
    );
  }
  return null;
}

/// Whether [host] resolves only to public addresses: no loopback,
/// private, link-local or carrier NAT one (SSRF hygiene; resolve and
/// check, so a rebinding DNS answer between here and the connect is not
/// covered).
Future<bool> isPublicHost(String host,
    [HostLookup lookup = InternetAddress.lookup]) async {
  try {
    final literal = InternetAddress.tryParse(host);
    final all = literal != null ? [literal] : await lookup(host);
    return all.isNotEmpty && all.every(isPublicAddress);
  } catch (_) {
    return false;
  }
}

bool isPublicAddress(InternetAddress a) {
  var b = a.rawAddress;
  if (a.type == InternetAddressType.IPv6) {
    final mapped =
        b.take(10).every((x) => x == 0) && b[10] == 0xff && b[11] == 0xff;
    if (!mapped) {
      return !(a.isLoopback ||
          a.isLinkLocal ||
          a.isMulticast ||
          b.every((x) => x == 0) ||
          (b[0] & 0xfe) == 0xfc); // fc00::/7, unique local
    }
    b = b.sublist(12); // ::ffff:a.b.c.d is that IPv4 address
  }
  final (x, y) = (b[0], b[1]);
  return !(x == 0 ||
      x == 10 ||
      x == 127 ||
      x >= 224 ||
      (x == 100 && y >= 64 && y < 128) ||
      (x == 169 && y == 254) ||
      (x == 172 && y >= 16 && y < 32) ||
      (x == 192 && y == 168));
}

/// What a page says about itself, '' for what it does not.
typedef PageMeta = ({
  String title,
  String description,
  String siteName,
  String image,
});

/// Open Graph, then Twitter card tags, then `<title>` and the meta
/// description. ponytail: regular expressions over the head, not an HTML
/// parser; enough for meta tags, which is all a preview reads.
PageMeta parsePageMeta(String html) {
  final head = html.replaceAll(_skipped, '');
  final meta = <String, String>{};
  for (final tag in _metaTag.allMatches(head)) {
    final attrs = {
      for (final a in _attr.allMatches(tag[1]!))
        a[1]!.toLowerCase(): a[2]!.startsWith(RegExp('["\']'))
            ? a[2]!.substring(1, a[2]!.length - 1)
            : a[2]!,
    };
    final key = (attrs['property'] ?? attrs['name'])?.toLowerCase();
    final content = _text(attrs['content'] ?? '');
    if (key != null && content.isNotEmpty) meta.putIfAbsent(key, () => content);
  }
  String pick(List<String> keys) =>
      keys.map((k) => meta[k]).nonNulls.firstOrNull ?? '';
  final title = pick(['og:title', 'twitter:title']);
  return (
    title: title.isNotEmpty ? title : _text(_title.firstMatch(head)?[1] ?? ''),
    description: pick(['og:description', 'twitter:description', 'description']),
    siteName: pick(['og:site_name']),
    image: pick([
      'og:image',
      'og:image:secure_url',
      'og:image:url',
      'twitter:image',
      'twitter:image:src',
    ]),
  );
}

final _skipped = RegExp(
    r'<!--[\s\S]*?-->|<script\b[\s\S]*?</script\s*>|<style\b[\s\S]*?</style\s*>',
    caseSensitive: false);
final _metaTag =
    RegExp(r'''<meta\b((?:[^>"']|"[^"]*"|'[^']*')*)>''', caseSensitive: false);
final _attr = RegExp(r'''([^\s=/>"']+)\s*=\s*("[^"]*"|'[^']*'|[^\s"'>]+)''');
final _title = RegExp(r'<title\b[^>]*>([\s\S]*?)</title', caseSensitive: false);
final _entity = RegExp(r'&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);');
const _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'laquo': '«',
  'raquo': '»',
  'middot': '·',
  'bull': '•',
  'copy': '©',
  'reg': '®',
  'trade': '™',
};

/// [s] with its character references decoded and its white space
/// collapsed.
String _text(String s) => s
    .replaceAllMapped(_entity, (m) {
      final e = m[1]!;
      if (!e.startsWith('#')) return _entities[e] ?? m[0]!;
      final code = e[1] == 'x' || e[1] == 'X'
          ? int.tryParse(e.substring(2), radix: 16)
          : int.tryParse(e.substring(1));
      return code == null || code == 0 || code > 0x10FFFF
          ? m[0]!
          : String.fromCharCode(code);
    })
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _cap(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';

const _media = MethodChannel('vartalap/media');

/// [image] as a JPEG at most 300 px on its long side and about 30 KB, by
/// the native code that readies photos to send (turned upright, EXIF
/// dropped). Null when it will not decode or stay that small.
Future<Uint8List?> shrinkImage(Uint8List image) async {
  File? src, out;
  try {
    final dir = (await getTemporaryDirectory()).path;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    src = File('$dir/link-preview-$stamp');
    out = File('$dir/link-preview-$stamp.jpg');
    await src.writeAsBytes(image);
    for (final quality in const [70, 40]) {
      final size = await _media.invokeListMethod<int>('photo', {
        'path': src.path,
        'out': out.path,
        'maxSide': 300,
        'quality': quality,
      });
      if (size == null) return null;
      final jpeg = await out.readAsBytes();
      if (jpeg.length <= 30 * 1024) return jpeg;
    }
    return null;
  } on Exception {
    return null;
  } finally {
    for (final f in [src, out].nonNulls) {
      if (await f.exists()) await f.delete();
    }
  }
}
