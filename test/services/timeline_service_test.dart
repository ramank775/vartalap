/// Decision 223 on the poster's phone: a post's audience is resolved from
/// the labels here and goes to the server as user ids only; photos go up
/// unencrypted first; reactions and deletes are single REST calls; the
/// feed and our own posts merge newest first, and what was shown counts
/// as seen.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/timeline_client.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const _self = 'abcdef012';
const _asha = '00000000b';
const _ravi = '00000000c';
const _meena = '00000000d';

/// A stand-in server: records every request, answers from [feed].
class _Server {
  final requests = <http.Request>[];
  List<Map<String, dynamic>> feed = [];
  List<Map<String, dynamic>> mine = [];
  var _files = 0;

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
    if (path == '/v3.0/timeline/posts') {
      return json({
        ...jsonDecode(req.body) as Map<String, dynamic>,
        'author': _self,
        'createdAt': 5,
        'reactions': [],
      }, 201);
    }
    if (path == '/v3.0/timeline/feed') {
      final limit = int.parse(req.url.queryParameters['limit']!);
      return json({'posts': feed.take(limit).toList(), 'next': null});
    }
    if (path == '/v3.0/timeline/posts/mine') {
      return json({'posts': mine, 'next': null});
    }
    return http.Response('', 204);
  });

  Iterable<http.Request> to(String path) =>
      requests.where((r) => r.url.path == path);
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
  // 1:1 chats with Asha and Ravi; Meena is a contact with no chat.
  for (final peer in [_asha, _ravi]) {
    final id = dmChannelId(_self, peer);
    await store.insertChannel(
        channelId: id, kind: 'one_to_one', ownerUserId: _self, createdAt: 1);
    for (final u in [_self, peer]) {
      await store.insertChannelMember(
          channelId: id, userId: u, role: 'member', joinedAt: 1);
    }
  }
  return (chat, store, server);
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('a post names its audience as user ids, never a label', () async {
    final (chat, _, server) = await _rig();
    final family = (await chat.fetchLabels()).first;
    await chat.setLabelMembers(family.labelId, {_asha, _meena});

    await chat
        .postToTimeline(body: '  Reached Pune  ', labelIds: {family.labelId});

    final sent = jsonDecode(server.to('/v3.0/timeline/posts').single.body)
        as Map<String, dynamic>;
    expect(sent['audience'], [_asha],
        reason: 'Meena has no 1:1 chat with us, so is not connected');
    expect(sent['text'], 'Reached Pune');
    expect(sent['photos'], isEmpty);
    expect(sent.keys.toSet(), {'postId', 'text', 'photos', 'audience'},
        reason: 'nothing about the label goes');
    expect(jsonEncode(sent).contains('Family'), isFalse);
    expect(await chat.lastTimelineAudience(), {family.labelId});
  });

  test('photos go up first, unencrypted, as the timeline category', () async {
    final (chat, _, server) = await _rig();
    final dir = await Directory.systemTemp.createTemp('vartalap_tl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = [
      for (final n in ['a.jpg', 'b.jpg'])
        (File('${dir.path}/$n')..writeAsBytesSync([1, 2, 3])).path,
    ];

    await chat.postToTimeline(photoPaths: paths);

    final presigns = server.to('/v3.0/assets/upload/presigned_url').toList();
    expect(presigns.map((r) => r.url.queryParameters['category']),
        ['timeline', 'timeline']);
    expect(
        presigns.any((r) => r.url.queryParameters.containsKey('md5')), isFalse,
        reason: 'not sealed: the bytes go as picked');
    expect(
        server.requests
            .where((r) => r.url.path.startsWith('/put/'))
            .map((r) => r.bodyBytes),
        [
          [1, 2, 3],
          [1, 2, 3]
        ]);
    final sent = jsonDecode(server.to('/v3.0/timeline/posts').single.body);
    expect([for (final p in sent['photos']) p['fileId']], ['file-1', 'file-2']);
    expect(sent['audience'], [_asha, _ravi], reason: 'no label: everyone');
    expect(await chat.lastTimelineAudience(), isNull);
  });

  test('nobody to share with: nothing is sent', () async {
    final (chat, _, server) = await _rig();
    final close = (await chat.fetchLabels()).last;
    await expectLater(
        chat.postToTimeline(body: 'hi', labelIds: {close.labelId}),
        throwsStateError);
    expect(server.requests, isEmpty);
  });

  test('ours and theirs merge newest first; what was shown is seen', () async {
    final (chat, _, server) = await _rig();
    Map<String, dynamic> post(String id, String author, int at) =>
        {'postId': id, 'author': author, 'createdAt': at, 'photos': []};
    server
      ..feed = [post('p3', _asha, 30), post('p1', _ravi, 10)]
      ..mine = [
        {
          ...post('p2', _self, 20),
          'audience': [_asha],
          'reactions': []
        }
      ];

    expect(await chat.timelineHasNew(), isTrue);
    final posts = await chat.loadTimeline();
    expect([for (final p in posts) p.postId], ['p3', 'p2', 'p1']);
    expect(posts[1].mine, isTrue);
    expect(await chat.timelineHasNew(), isFalse);

    server.feed = [post('p4', _ravi, 40), ...server.feed];
    expect(await chat.timelineHasNew(), isTrue);
  });

  test('a reaction is a PUT or a DELETE of ours; a delete is one call',
      () async {
    final (chat, _, server) = await _rig();
    const theirs = TimelinePost(
        postId: '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0001',
        author: _asha,
        createdAt: 1);
    await chat.reactToPost(theirs, '❤️');
    await chat.reactToPost(theirs, null);
    await chat.deletePost(theirs);
    final calls = [
      for (final r in server.requests)
        if (r.url.path.contains('/timeline/posts/')) '${r.method} ${r.url.path}'
    ];
    final id = theirs.postId;
    expect(calls, [
      'PUT /v3.0/timeline/posts/$id/reaction',
      'DELETE /v3.0/timeline/posts/$id/reaction',
      'DELETE /v3.0/timeline/posts/$id',
    ]);
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
