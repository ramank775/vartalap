/// Decision 233 on the phone: albums are plain REST under the chat's
/// channel, photos go up unencrypted as the `album` category and are
/// added one by one, and making an album says so in the chat with a
/// message that opens it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/album_client.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/utils/attachment_text.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const _self = 'abcdef012';
const _asha = '00000000b';
const _albumId = '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0001';

Map<String, dynamic> _album(String channelId, {int photos = 0}) => {
      'albumId': _albumId,
      'channelId': channelId,
      'title': 'Diwali',
      'date': '2026-11-01',
      'creator': _self,
      'createdAt': 5,
      'keptUntil': 9,
      'photoCount': photos,
      'cover': photos == 0
          ? null
          : {'fileId': 'file-$photos', 'uploader': _self, 'addedAt': 6},
    };

/// A stand-in server: records every request.
class _Server {
  final requests = <http.Request>[];
  var _files = 0;
  var _photos = 0;

  /// Answer every album call with this status and error code instead.
  int? refuse;

  late final client = MockClient((req) async {
    requests.add(req);
    final path = req.url.path;
    http.Response json(Object o, [int status = 200]) =>
        http.Response(jsonEncode(o), status);
    if (path == '/v3.0/assets/upload/presigned_url') {
      return json({
        'url': 'https://store.invalid/put/${++_files}',
        'fileId': 'file-$_files',
        'contentType': 'image/jpeg',
      });
    }
    if (path.startsWith('/put/') || path.endsWith('/status')) {
      return http.Response('', 200);
    }
    final channelId = path.split('/')[3];
    if (refuse != null) {
      return json({
        'error': {'code': 'forbidden', 'message': 'no'}
      }, refuse!);
    }
    if (path.endsWith('/albums') && req.method == 'GET') {
      return json({
        'albums': [_album(channelId, photos: 2)]
      });
    }
    if (path.endsWith('/albums')) return json(_album(channelId), 201);
    if (path.endsWith('/photos')) {
      _photos += 1;
      return json({'album': _album(channelId, photos: _photos), 'photos': []});
    }
    if (req.method == 'GET') {
      return json({
        'album': _album(channelId, photos: 1),
        'photos': [
          {'fileId': 'f1', 'uploader': _asha, 'addedAt': 7}
        ],
        'next': '7_f1',
      });
    }
    if (req.method == 'PATCH') return json(_album(channelId));
    return http.Response('', 204);
  });

  Iterable<http.Request> albumCalls() =>
      requests.where((r) => r.url.path.contains('/albums'));
}

Future<(ChatService, ChatStore, _Server)> _rig() async {
  SharedPreferences.setMockInitialValues({});
  final server = _Server();
  final store = await ChatStore.open(path: inMemoryDatabasePath);
  final scheduler = SyncScheduler(
    store: store,
    wsTransport: _Offline(),
    restTransport: _Offline(),
    backoff: const FixedBackoff(Duration(milliseconds: 10)),
    clock: FakeClock(1000000),
  );
  final auth = AuthClient(
      baseUrl: Uri.parse('http://api.invalid'), httpClient: server.client)
    ..restoreSession(accesskey: 'sk', userId: _self);
  final chat = ChatService(
    store: store,
    scheduler: scheduler,
    authClient: auth,
    wsTransport: WsTransport(
      endpoint: Uri.parse('ws://example.invalid/wss'),
      auth: AuthClient(baseUrl: Uri.parse('http://example.invalid')),
    ),
    uuidGen: Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(_self)),
    clock: FakeClock(1000000),
  );
  addTearDown(store.close);
  final dm = dmChannelId(_self, _asha);
  await store.insertChannel(
      channelId: dm, kind: 'one_to_one', ownerUserId: _self, createdAt: 1);
  return (chat, store, server);
}

void main() {
  setUpAll(sqfliteFfiInit);
  final dm = dmChannelId(_self, _asha);

  test('making a 1:1 album names the peer, then says so in the chat', () async {
    final (chat, store, server) = await _rig();
    final album = await chat.createAlbum(
        channelId: dm, peer: _asha, title: 'Diwali', date: '2026-11-01');
    expect(album.keptUntil, 9);

    final call = server.albumCalls().single;
    expect('${call.method} ${call.url.path}', 'POST /v3.0/channels/$dm/albums');
    final sent = jsonDecode(call.body) as Map<String, dynamic>;
    expect(sent.keys.toSet(), {'albumId', 'title', 'date', 'peer'});
    expect(sent['peer'], _asha);
    expect(sent['albumId'], matches(RegExp(r'^[0-9a-f-]{36}$')));

    final [note] = await store.fetchChannelMessages(dm);
    expect(note.contentType, kAlbumType);
    expect(note.authorUserId, _self);
    final parsed = AlbumNote.parse(note.body!)!;
    expect([parsed.albumId, parsed.channelId, parsed.title],
        [_albumId, dm, 'Diwali']);
    expect(messagePreview(note.body!, note.contentType, attachment: false),
        '🖼️ Album: Diwali');
    expect(ChatService.canForward(note), isFalse,
        reason: 'only its own chat can open the album');
  });

  test('photos go up unencrypted as the album category, added one by one',
      () async {
    final (chat, _, server) = await _rig();
    final dir = await Directory.systemTemp.createTemp('vartalap_album');
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = [
      for (final n in ['a.jpg', 'b.jpg'])
        (File('${dir.path}/$n')..writeAsBytesSync([1, 2, 3])).path,
    ];
    const start = Album(
        albumId: _albumId,
        channelId: 'g1',
        title: 'Diwali',
        creator: _self,
        createdAt: 5);
    final counted = <int>[];

    final after = await chat.addAlbumPhotos(start, paths, onAdded: counted.add);

    final presigns = server.requests
        .where((r) => r.url.path == '/v3.0/assets/upload/presigned_url');
    expect(presigns.map((r) => r.url.queryParameters['category']),
        ['album', 'album']);
    expect(
        presigns.any((r) => r.url.queryParameters.containsKey('md5')), isFalse);
    final adds = server.albumCalls().toList();
    expect(adds.map((r) => '${r.method} ${r.url.path}'),
        List.filled(2, 'POST /v3.0/channels/g1/albums/$_albumId/photos'));
    expect([
      for (final r in adds) jsonDecode(r.body)['photos']
    ], [
      [
        {'fileId': 'file-1'}
      ],
      [
        {'fileId': 'file-2'}
      ],
    ]);
    expect(counted, [1, 2]);
    expect(after.photoCount, 2);
    expect(after.cover!.fileId, 'file-2');
  });

  test('list, page, rename, remove and delete are one REST call each',
      () async {
    final (chat, _, server) = await _rig();
    final [listed] = await chat.albumsOf(dm, peer: _asha);
    expect(listed.cover!.uploader, _self);
    final page = await chat.albumPage(dm, _albumId);
    expect(page.photos.single.uploader, _asha);
    expect(page.next, '7_f1');
    await chat.albumPage(dm, _albumId, newestFirst: false, cursor: page.next);
    await chat.editAlbum(listed, title: 'Diwali 2026', date: '');
    await chat.removeAlbumPhoto(listed, page.photos.single);
    await chat.deleteAlbum(listed);

    final base = '/v3.0/channels/$dm/albums';
    expect([
      for (final r in server.albumCalls()) '${r.method} ${r.url}'
    ], [
      'GET http://api.invalid$base?peer=$_asha',
      'GET http://api.invalid$base/$_albumId?order=newest&limit=60',
      'GET http://api.invalid$base/$_albumId?order=oldest&limit=60&cursor=7_f1',
      'PATCH http://api.invalid$base/$_albumId',
      'DELETE http://api.invalid$base/$_albumId/photos/f1',
      'DELETE http://api.invalid$base/$_albumId',
    ]);
    final patch = server.albumCalls().firstWhere((r) => r.method == 'PATCH');
    expect(jsonDecode(patch.body), {'title': 'Diwali 2026', 'date': null},
        reason: "'' clears the date");
  });

  test("a refusal is the server's code; a refused album sends no message",
      () async {
    final (chat, store, server) = await _rig();
    server.refuse = 403;
    await expectLater(
        chat.createAlbum(channelId: dm, peer: _asha, title: 'x'),
        throwsA(isA<AuthClientException>()
            .having((e) => e.statusCode, 'status', 403)
            .having((e) => e.errorCode, 'code', 'forbidden')));
    expect(await store.fetchChannelMessages(dm), isEmpty);
  });
}

class _Offline implements Transport {
  @override
  Future<void> send(OutboundFrame frame) async {}
  @override
  Stream<AckFrame> get acks => const Stream.empty();
  @override
  Stream<TransportState> get state => const Stream.empty();
  @override
  TransportState get currentState => TransportState.disconnected;
}
