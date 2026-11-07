/// Link previews (SYNC_PROTOCOL §27): the page parser, the fetch limits
/// against a fake HTTP client, the SSRF host check and the wire field.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vartalap/services/link_preview.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;

const _page = '''<!doctype html><html><head>
<title>Fallback title</title>
<meta property="og:title" content="The &amp; Title &#8212; &#x41;">
<meta content='A page about things' property='og:description'>
<meta property="og:site_name" content="Example">
<meta property="og:image" content="/img.png">
</head><body>hi</body></html>''';

/// Every host is public unless a test says otherwise.
Future<List<InternetAddress>> _public(String host) async =>
    [InternetAddress('93.184.216.34')];

Future<Uint8List?> _shrink(Uint8List image) async =>
    Uint8List.fromList([0xff, 0xd8, image.length & 0xff]);

http.Response _html(String body, {int status = 200}) =>
    http.Response(body, status,
        headers: {'content-type': 'text/html; charset=utf-8'});

void main() {
  group('parsePageMeta', () {
    test(
        'Open Graph tags, attributes in any order, quoted either way, '
        'character references decoded', () {
      final m = parsePageMeta(_page);
      expect(m.title, 'The & Title — A');
      expect(m.description, 'A page about things');
      expect(m.siteName, 'Example');
      expect(m.image, '/img.png');
    });

    test('Twitter card tags when there is no Open Graph', () {
      final m = parsePageMeta('''<head>
        <meta name="twitter:title" content="Tweet title">
        <meta name="twitter:description" content="Tweet text">
        <meta name="twitter:image:src" content="https://x.test/t.jpg">
      </head>''');
      expect([m.title, m.description, m.image],
          ['Tweet title', 'Tweet text', 'https://x.test/t.jpg']);
    });

    test('<title> and the meta description last', () {
      final m = parsePageMeta('''<HEAD><TITLE>
          Plain   page &lt;3
        </TITLE><META NAME="Description" CONTENT="Described"></HEAD>''');
      expect([m.title, m.description, m.image],
          ['Plain page <3', 'Described', '']);
    });

    test('junk: comments, scripts and a > inside a value do not confuse it',
        () {
      final m = parsePageMeta('''<head>
        <!-- <meta property="og:title" content="commented out"> -->
        <script>var s = '<meta property="og:title" content="in a script">';</script>
        <meta property="og:title" content="a > b">
        <meta property="og:description">
        <meta content="no key">
      </head>''');
      expect(m.title, 'a > b');
      expect(m.description, '');
      expect(parsePageMeta('not html at all <<< >>>').title, '');
      expect(parsePageMeta('').title, '');
    });
  });

  group('fetchLinkPreview', () {
    test('fetches the page and its image, resolved against the page', () async {
      final asked = <String>[];
      final client = MockClient((r) async {
        asked.add('${r.url} ${r.headers['user-agent']}');
        if (r.url.path == '/img.png') {
          return http.Response.bytes(List.filled(100, 7), 200,
              headers: {'content-type': 'image/png'});
        }
        return _html(_page);
      });
      final p = (await fetchLinkPreview('https://example.com/a?b=1',
          client: client, lookup: _public, shrink: _shrink))!;
      expect(p.url, 'https://example.com/a?b=1');
      expect(p.title, 'The & Title — A');
      expect(p.description, 'A page about things');
      expect(p.siteName, 'Example');
      expect(p.imageJpeg, [0xff, 0xd8, 100]);
      expect(asked, [
        'https://example.com/a?b=1 $kLinkPreviewUserAgent',
        'https://example.com/img.png $kLinkPreviewUserAgent',
      ]);
    });

    test('https first for a link typed as http, then http', () async {
      final asked = <String>[];
      final client = MockClient((r) async {
        asked.add('${r.url}');
        if (r.url.isScheme('https')) throw const SocketException('no tls');
        return _html(_page);
      });
      final p = await fetchLinkPreview('http://example.com/',
          client: client, lookup: _public, shrink: _shrink);
      expect(p?.title, 'The & Title — A');
      expect(asked.take(2), ['https://example.com/', 'http://example.com/']);
    });

    test('follows 3 redirects, not 4', () async {
      Future<pb.ChatLinkPreview?> after(int hops) => fetchLinkPreview(
            'https://example.com/0',
            client: MockClient((r) async {
              final n = int.parse(r.url.pathSegments.last);
              return n < hops
                  ? http.Response('', 301, headers: {'location': '/${n + 1}'})
                  : _html('<title>Landed</title>');
            }),
            lookup: _public,
            shrink: _shrink,
          );
      expect((await after(3))?.title, 'Landed');
      expect(await after(4), isNull);
    });

    test('only text/html', () async {
      final client = MockClient((r) async => http.Response(
          '<title>x</title>', 200,
          headers: {'content-type': 'application/json'}));
      expect(
          await fetchLinkPreview('https://example.com/',
              client: client, lookup: _public, shrink: _shrink),
          isNull);
    });

    test('reads at most 512 KB of the page', () async {
      Future<pb.ChatLinkPreview?> titleAt(int offset) => fetchLinkPreview(
            'https://example.com/',
            client: MockClient((r) async =>
                _html('${' ' * offset}<title>Late</title>${'x' * 100000}')),
            lookup: _public,
            shrink: _shrink,
          );
      expect((await titleAt(400 * 1024))?.title, 'Late');
      expect(await titleAt(kLinkPreviewPageBytes), isNull);
    });

    test('an image over 2 MB is left out, the preview kept', () async {
      var shrunk = false;
      final client = MockClient((r) async => r.url.path == '/img.png'
          ? http.Response.bytes(Uint8List(kLinkPreviewImageBytes + 1), 200,
              headers: {'content-type': 'image/png'})
          : _html(_page));
      final p = await fetchLinkPreview('https://example.com/',
          client: client, lookup: _public, shrink: (b) async {
        shrunk = true;
        return b;
      });
      expect(p?.title, 'The & Title — A');
      expect(p?.imageJpeg, isEmpty);
      expect(shrunk, isFalse);
    });

    test('a private host, or a redirect to one, is never fetched', () async {
      final asked = <Uri>[];
      final client = MockClient((r) async {
        asked.add(r.url);
        return r.url.host == 'example.com'
            ? http.Response('', 302,
                headers: {'location': 'http://intranet.test/'})
            : _html(_page);
      });
      Future<List<InternetAddress>> lookup(String host) async => [
            InternetAddress(
                host == 'intranet.test' ? '192.168.1.10' : '93.184.216.34'),
          ];
      expect(
          await fetchLinkPreview('https://example.com/',
              client: client, lookup: lookup, shrink: _shrink),
          isNull);
      expect(
          await fetchLinkPreview('https://127.0.0.1/',
              client: client, lookup: lookup, shrink: _shrink),
          isNull);
      expect(asked.map((u) => u.host).toSet(), {'example.com'});
    });

    test('gives up after 5 seconds', () async {
      final client = MockClient((r) => Completer<http.Response>().future);
      final watch = Stopwatch()..start();
      expect(
          await fetchLinkPreview('https://example.com/',
              client: client, lookup: _public, shrink: _shrink),
          isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 7)));
    });

    test('nothing to say, nothing to send', () async {
      final client = MockClient((r) async => _html('<p>no head</p>'));
      expect(
          await fetchLinkPreview('https://example.com/',
              client: client, lookup: _public, shrink: _shrink),
          isNull);
      expect(
          await fetchLinkPreview('ftp://example.com/', client: client), isNull);
    });
  });

  test(
      'isPublicAddress: loopback, private, link-local and carrier NAT are '
      'not', () {
    for (final (ip, public) in [
      ('93.184.216.34', true),
      ('8.8.8.8', true),
      ('2606:4700::1111', true),
      ('127.0.0.1', false),
      ('10.1.2.3', false),
      ('172.16.0.1', false),
      ('172.31.255.255', false),
      ('172.32.0.1', true),
      ('192.168.0.1', false),
      ('169.254.169.254', false),
      ('100.64.0.1', false),
      ('0.0.0.0', false),
      ('224.0.0.1', false),
      ('::1', false),
      ('::', false),
      ('fe80::1', false),
      ('fd00::1', false),
      ('::ffff:10.0.0.1', false),
      ('::ffff:93.184.216.34', true),
    ]) {
      expect(isPublicAddress(InternetAddress(ip)), public, reason: ip);
    }
  });

  test('isPublicHost: a name with any private address is not public', () async {
    expect(await isPublicHost('localhost'), isFalse);
    expect(
        await isPublicHost(
            'mixed.test',
            (_) async => [
                  InternetAddress('93.184.216.34'),
                  InternetAddress('10.0.0.1'),
                ]),
        isFalse);
    expect(await isPublicHost('gone.test', (_) async => throw 'nxdomain'),
        isFalse);
  });

  test('ChatLinkPreview rides ChatPayload field 75 and round-trips', () {
    final sent = pb.ChatPayload(
      version: 1,
      type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
      body: 'look https://example.com',
      linkPreview: pb.ChatLinkPreview(
        url: 'https://example.com',
        title: 'T',
        description: 'D',
        siteName: 'S',
        imageJpeg: [1, 2, 3],
      ),
    ).writeToBuffer();
    final got = pb.ChatPayload.fromBuffer(sent).linkPreview;
    expect([
      got.url,
      got.title,
      got.description,
      got.siteName,
      got.imageJpeg
    ], [
      'https://example.com',
      'T',
      'D',
      'S',
      [1, 2, 3]
    ]);
    expect(
        pb.ChatPayload.getDefault().info_.byName['linkPreview']?.tagNumber, 75);
  });
}
