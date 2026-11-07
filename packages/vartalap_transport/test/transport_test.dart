import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_transport/vartalap_transport.dart';

/// A UUIDv7 op id carrying [userId]'s bits (Uuid7Gen's layout), [n] in
/// its tail: an independent check of the edge's reading of them.
String _opId(int n, [String userId = '000000000']) {
  final u = int.parse(userId, radix: 16);
  return uuidText(Uint8List(16)
    ..[6] = 0x70
    ..[8] = 0x80 | (u >> 30) & 0x3f
    ..[9] = (u >> 22) & 0xff
    ..[10] = (u >> 14) & 0xff
    ..[11] = (u >> 6) & 0xff
    ..[12] = (u & 0x3f) << 2
    ..[15] = n);
}

const _group = '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0000';

void main() {
  _appBuildTests();
  _wireTests();
  group('WsTransport', () {
    late _WsEchoServer server;

    setUp(() async {
      server = _WsEchoServer();
      await server.start();
    });

    tearDown(() async => server.stop());

    test('sends WS_OP, receives ACK_SUCCESS via AckFrame', () async {
      server.respondWith = (env) => pb.Ack(
            opId: env.opId,
            outcome: pb.AckOutcome.ACK_SUCCESS,
            serverTimestampMs: fixnum.Int64(1700000),
          );

      final transport = WsTransport(
        endpoint: server.uri,
        auth: _FakeAuth('acc-1'),
      );
      addTearDown(transport.dispose);

      final ackFuture = transport.acks.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw StateError('no ack received'),
      );

      await transport.start();
      await _waitForState(transport, TransportState.connected);
      // Release the post-connect buffer (no sync pull in this test).
      transport.endSyncBuffer();

      await transport.send(OutboundFrame(
        kind: 'chat_payload',
        resourceId: _group,
        ops: [
          FramedOp(
            opId: _opId(1),
            payload: const [1, 2, 3],
            frameClass: FrameClass.receipt,
          ),
        ],
      ));

      final ack = await ackFuture;
      expect(ack.opId, _opId(1));
      expect(ack.outcome, isA<AckSuccess>());
      final success = ack.outcome as AckSuccess;
      expect(success.serverTimestampMs, 1700000);

      // Server saw the accesskey subprotocol.
      expect(server.lastSubprotocol, 'accesskey.acc-1');

      // Server decoded the outbound envelope correctly.
      expect(server.lastEnvelope, isNotNull);
      // Decision 218: ids as bytes, a group's channel and no peer, the
      // class in flags.
      expect(server.lastEnvelope!.opId, uuidBytes(_opId(1)));
      expect(server.lastEnvelope!.channelId, uuidBytes(_group));
      expect(server.lastEnvelope!.hasPeer(), isFalse);
      expect(server.lastEnvelope!.flags, 5, reason: 'RECEIPT, SILENT');
      expect(server.lastEnvelope!.payload, const [1, 2, 3]);
    });

    test('ACK_TRANSIENT maps to AckTransientReject with retry hint',
        () async {
      server.respondWith = (env) => pb.Ack(
            opId: env.opId,
            outcome: pb.AckOutcome.ACK_TRANSIENT,
            reason: 'server_busy',
            retryAfterMs: fixnum.Int64(2500),
          );

      final transport = WsTransport(
        endpoint: server.uri,
        auth: _FakeAuth('acc-1'),
      );
      addTearDown(transport.dispose);

      await transport.start();
      await _waitForState(transport, TransportState.connected);
      // Release the post-connect buffer (no sync pull in this test).
      transport.endSyncBuffer();

      final ackFuture = transport.acks.first.timeout(
        const Duration(seconds: 3),
      );
      await transport.send(OutboundFrame(
        kind: 'chat_payload',
        resourceId: _group,
        ops: [
          FramedOp(opId: _opId(2), payload: const [0]),
        ],
      ));

      final ack = await ackFuture;
      expect(ack.outcome, isA<AckTransientReject>());
      final rej = ack.outcome as AckTransientReject;
      expect(rej.reason, 'server_busy');
      expect(rej.serverRetryAfter, const Duration(milliseconds: 2500));
    });

    test('ACK_AUTH_FAILURE maps to AckAuthFailure', () async {
      server.respondWith = (env) => pb.Ack(
            opId: env.opId,
            outcome: pb.AckOutcome.ACK_AUTH_FAILURE,
            reason: 'invalid_accesskey',
          );

      final transport = WsTransport(
        endpoint: server.uri,
        auth: _FakeAuth('acc-1'),
      );
      addTearDown(transport.dispose);

      await transport.start();
      await _waitForState(transport, TransportState.connected);
      // Release the post-connect buffer (no sync pull in this test).
      transport.endSyncBuffer();

      final ackFuture = transport.acks.first.timeout(
        const Duration(seconds: 3),
      );
      await transport.send(OutboundFrame(
        kind: 'chat_payload',
        resourceId: _group,
        ops: [
          FramedOp(opId: _opId(3), payload: const [0]),
        ],
      ));

      final ack = await ackFuture;
      expect(ack.outcome, isA<AckAuthFailure>());
    });

    test('start while connecting or connected opens no second socket',
        () async {
      // A push wake calls start() on a transport that may already be up.
      // A second socket for the same device makes the server replace one
      // with the other, and the orphan's reconnect replaced the new one
      // back, once a second, for good.
      final transport = WsTransport(
        endpoint: server.uri,
        auth: _FakeAuth('acc-1'),
      );
      addTearDown(transport.dispose);

      await Future.wait([transport.start(), transport.start()]);
      await _waitForState(transport, TransportState.connected);
      await transport.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(server.upgrades, 1);
      expect(transport.currentState, TransportState.connected);
    });

    test('send before connect throws', () async {
      final transport = WsTransport(
        endpoint: server.uri,
        auth: _FakeAuth('acc-1'),
      );
      addTearDown(transport.dispose);

      expect(
        () => transport.send(OutboundFrame(
          kind: 'chat_payload',
          resourceId: 'c',
          ops: [FramedOp(opId: 'op', payload: const [0])],
        )),
        throwsStateError,
      );
    });

    test('WS_PUSH lands on pushes stream, not acks', () async {
      server.respondWith = (env) => null; // don't ACK this op
      final transport = WsTransport(
        endpoint: server.uri,
        auth: _FakeAuth('acc-1'),
      );
      addTearDown(transport.dispose);

      final pushFuture = transport.pushes.first.timeout(
        const Duration(seconds: 3),
      );

      await transport.start();
      await _waitForState(transport, TransportState.connected);
      // Release the post-connect buffer (no sync pull in this test).
      transport.endSyncBuffer();

      server.pushEnvelope(wireEnvelope(
        opId: _opId(9, '1a2b3c4d5'),
        channelId: _group,
        senderDeviceId: _group,
        serverTimestampMs: 1800000,
        payload: utf8.encode('hi'),
      ));

      final pushed = await pushFuture;
      expect(pushed.opId, _opId(9, '1a2b3c4d5'));
      expect(pushed.channelId, _group);
      expect(pushed.senderUserId, '1a2b3c4d5',
          reason: 'decision 218: the sender is the op id\'s user bits');
      expect(pushed.senderDeviceId, _group);
      expect(pushed.serverTimestampMs, 1800000);
    });
  });

  group('RestTransport', () {
    late _HttpServer server;

    setUp(() async {
      server = _HttpServer();
      await server.start();
    });

    tearDown(() async => server.stop());

    test('2xx → AckSuccess', () async {
      server.handler = (req) async {
        if (req.method == 'POST' && req.uri.path == '/v3.0/channels') {
          final body =
              jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
          expect(body['op_id'], 'op-rest-1');
          expect(body.containsKey('resource_seq'), isFalse,
              reason: 'retired: the server keeps no ordering state');
          expect(body['channel_id'], 'ch-new');
          req.response.statusCode = 201;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'channel_id': 'ch-new'}));
          await req.response.close();
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      };

      final transport = RestTransport(
        baseUrl: server.uri,
        auth: _FakeAuth('acc-rest'),
      );
      addTearDown(transport.dispose);

      final ackFuture = transport.acks.first.timeout(
        const Duration(seconds: 3),
      );

      await transport.send(OutboundFrame(
        kind: 'create_channel',
        resourceId: 'ch-new',
        ops: [
          FramedOp(
            opId: 'op-rest-1',
            payload: utf8.encode(jsonEncode({'channel_id': 'ch-new'})),
            restMethod: 'POST',
            restPath: '/v3.0/channels',
          ),
        ],
      ));

      final ack = await ackFuture;
      expect(ack.opId, 'op-rest-1');
      expect(ack.outcome, isA<AckSuccess>());
      expect(server.lastAuthHeader, 'Bearer acc-rest');
    });

    test('503 → AckTransientReject with server reason', () async {
      server.handler = (req) async {
        req.response.statusCode = 503;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'error': {'code': 'server_busy', 'message': 'try later'}
        }));
        await req.response.close();
      };

      final transport = RestTransport(
        baseUrl: server.uri,
        auth: _FakeAuth('acc-rest'),
      );
      addTearDown(transport.dispose);

      final ackFuture = transport.acks.first.timeout(
        const Duration(seconds: 3),
      );

      await transport.send(OutboundFrame(
        kind: 'create_channel',
        resourceId: 'ch',
        ops: [
          FramedOp(
            opId: 'op-503',
            payload: utf8.encode(jsonEncode({'name': 'x'})),
            restMethod: 'POST',
            restPath: '/v3.0/channels',
          ),
        ],
      ));

      final ack = await ackFuture;
      expect(ack.opId, 'op-503');
      expect(ack.outcome, isA<AckTransientReject>());
      expect((ack.outcome as AckTransientReject).reason, 'server_busy');
    });

    test('401 → AckAuthFailure', () async {
      server.handler = (req) async {
        req.response.statusCode = 401;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'error': {'code': 'INVALID_ACCESSKEY', 'message': 'nope'}
        }));
        await req.response.close();
      };

      final transport = RestTransport(
        baseUrl: server.uri,
        auth: _FakeAuth('acc-rest'),
      );
      addTearDown(transport.dispose);

      final ackFuture = transport.acks.first.timeout(
        const Duration(seconds: 3),
      );

      await transport.send(OutboundFrame(
        kind: 'create_channel',
        resourceId: 'ch',
        ops: [
          FramedOp(
            opId: 'op-401',
            payload: utf8.encode(jsonEncode({})),
            restMethod: 'POST',
            restPath: '/v3.0/channels',
          ),
        ],
      ));

      final ack = await ackFuture;
      expect(ack.outcome, isA<AckAuthFailure>());
    });

    test('404 → AckPermanentReject with parsed code', () async {
      server.handler = (req) async {
        req.response.statusCode = 404;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'error': {'code': 'not_found', 'message': 'no channel'}
        }));
        await req.response.close();
      };

      final transport = RestTransport(
        baseUrl: server.uri,
        auth: _FakeAuth('acc-rest'),
      );
      addTearDown(transport.dispose);

      final ackFuture = transport.acks.first.timeout(
        const Duration(seconds: 3),
      );

      await transport.send(OutboundFrame(
        kind: 'edit_channel',
        resourceId: 'ch-bad',
        ops: [
          FramedOp(
            opId: 'op-404',
            payload: utf8.encode(jsonEncode({'name': 'x'})),
            restMethod: 'PATCH',
            restPath: '/v3.0/channels/ch-bad',
          ),
        ],
      ));

      final ack = await ackFuture;
      expect(ack.outcome, isA<AckPermanentReject>());
      expect((ack.outcome as AckPermanentReject).reason, 'not_found');
    });

    test('send throws when FramedOp lacks REST fields', () async {
      final transport = RestTransport(
        baseUrl: server.uri,
        auth: _FakeAuth('acc-rest'),
      );
      addTearDown(transport.dispose);

      expect(
        () => transport.send(OutboundFrame(
          kind: 'create_channel',
          resourceId: 'ch',
          ops: [
            FramedOp(opId: 'op', payload: utf8.encode('{}')),
          ],
        )),
        throwsStateError,
      );
    });

    test('injected connectivity stream drives state: disconnected/connected',
        () async {
      final connectivityCtrl = StreamController<bool>();
      final transport = RestTransport(
        baseUrl: server.uri,
        auth: _FakeAuth('acc-rest'),
        connectivityStream: connectivityCtrl.stream,
      );
      addTearDown(transport.dispose);
      addTearDown(connectivityCtrl.close);

      expect(transport.currentState, TransportState.connected);

      final states = <TransportState>[];
      final sub = transport.state.listen(states.add);
      addTearDown(sub.cancel);

      connectivityCtrl.add(false);
      await pumpEventQueue();
      expect(transport.currentState, TransportState.disconnected);
      expect(states, [TransportState.disconnected]);

      connectivityCtrl.add(true);
      await pumpEventQueue();
      expect(transport.currentState, TransportState.connected);
      expect(states, [TransportState.disconnected, TransportState.connected]);

      // Duplicate values don't re-emit.
      connectivityCtrl.add(true);
      await pumpEventQueue();
      expect(states, [TransportState.disconnected, TransportState.connected]);
    });

    test('no connectivity stream injected → stays connected', () async {
      final transport = RestTransport(
        baseUrl: server.uri,
        auth: _FakeAuth('acc-rest'),
      );
      addTearDown(transport.dispose);

      expect(transport.currentState, TransportState.connected);
    });

    test('pullPendingSync asks from `since` and returns the page with '
        '`more`; null when it could not ask (§10.6)', () async {
      String? query;
      String? accept;
      pb.Envelope env(int n) => wireEnvelope(
          opId: _opId(n), channelId: _group, payload: [n], serverTimestampMs: n);
      server.handler = (req) async {
        query = req.uri.query;
        accept = req.headers.value('accept');
        req.response.statusCode = 200;
        req.response.headers.contentType =
            ContentType('application', 'x-protobuf');
        // Decision 218: a protobuf PendingPage.
        req.response.add(pb.PendingPage(envelopes: [
          env(11),
          pb.Envelope(opId: [1, 2, 3], channelId: uuidBytes(_group)),
          env(12),
        ], more: true)
            .writeToBuffer());
        await req.response.close();
      };
      final transport = RestTransport(
        baseUrl: server.uri,
        auth: _FakeAuth('acc-pull'),
      );
      addTearDown(transport.dispose);

      final page = await transport.pullPendingSync(since: 10);
      expect(query, 'since=10');
      expect(server.lastAuthHeader, 'Bearer acc-pull');
      expect(accept, 'application/x-protobuf');
      expect(page!.envelopes.map((e) => e.opId), [_opId(11), _opId(12)],
          reason: 'a malformed envelope (a 3-byte op id) is dropped');
      expect(page.envelopes.last.serverTimestampMs, 12);
      expect(page.more, isTrue);

      server.handler = (req) async {
        req.response.statusCode = 503;
        await req.response.close();
      };
      expect(await transport.pullPendingSync(since: 12), isNull,
          reason: 'could not ask is not the same as nothing new');
    });

    test('classifyHttpStatus maps across the §8.1 table', () {
      expect(classifyHttpStatus(200), isA<AckSuccess>());
      expect(classifyHttpStatus(201), isA<AckSuccess>());
      expect(classifyHttpStatus(401), isA<AckAuthFailure>());
      expect(classifyHttpStatus(403), isA<AckPermanentReject>());
      expect(classifyHttpStatus(404, reason: 'not_found'),
          predicate<AckOutcome>((o) =>
              o is AckPermanentReject && o.reason == 'not_found'));
      // decision 192: a refused build waits for the update
      expect(classifyHttpStatus(426), isA<AckTransientReject>());
      expect(classifyHttpStatus(502), isA<AckTransientReject>());
      expect(classifyHttpStatus(503), isA<AckTransientReject>());
      expect(classifyHttpStatus(504), isA<AckTransientReject>());
      expect(classifyHttpStatus(500), isA<AckTransientReject>());
    });
  });
}

// ---------------------------------------------------------------------
// In-memory test WS server — validates subprotocol, decodes WS_OP,
// echoes ACK via a caller-provided shaper.
// ---------------------------------------------------------------------

class _WsEchoServer {
  HttpServer? _http;
  WebSocket? _activeSocket;

  /// Called for each decoded inbound Envelope. Returning null means
  /// "don't ACK" (useful for testing push-only paths).
  pb.Ack? Function(pb.Envelope env)? respondWith;

  String? lastSubprotocol;
  pb.Envelope? lastEnvelope;

  /// WS upgrades accepted so far.
  int upgrades = 0;

  /// Upgrade attempts, refused ones included.
  int attempts = 0;
  String? lastAppBuild;

  /// Answer every upgrade with this status instead of accepting it.
  int? refuseWith;

  Uri get uri => Uri.parse('ws://127.0.0.1:${_http!.port}/wss');

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http!.listen(_onRequest);
  }

  Future<void> stop() async {
    try {
      await _activeSocket?.close();
    } catch (_) {}
    await _http?.close(force: true);
  }

  void pushEnvelope(pb.Envelope envelope) {
    final sock = _activeSocket;
    if (sock == null) {
      throw StateError('no active WS client');
    }
    final wsEnv = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: envelope,
    );
    sock.add(wsEnv.writeToBuffer());
  }

  Future<void> _onRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    lastSubprotocol = req.headers.value('sec-websocket-protocol');
    attempts++;
    lastAppBuild = req.headers.value('x-app-build');
    final refuse = refuseWith;
    if (refuse != null) {
      req.response.statusCode = refuse;
      await req.response.close();
      return;
    }
    // Echo the first subprotocol token back — required for a valid
    // upgrade when the client requested one.
    final sock = await WebSocketTransformer.upgrade(
      req,
      protocolSelector: (protocols) =>
          protocols.isNotEmpty ? protocols.first : '',
    );
    upgrades++;
    _activeSocket = sock;
    sock.listen((dynamic data) {
      if (data is! List<int>) return;
      final bytes = Uint8List.fromList(data);
      final wsEnv = pb.WsEnvelope.fromBuffer(bytes);
      if (wsEnv.type != pb.WsType.WS_OP) return;
      final acks = <pb.Ack>[];
      for (final env in wsEnv.ops.envelopes) {
        lastEnvelope = env;
        final ack = respondWith?.call(env);
        if (ack != null) acks.add(ack);
      }
      if (acks.isEmpty) return;
      final ackEnv = pb.WsEnvelope(
        type: pb.WsType.WS_ACK,
        acks: pb.AckBatch(acks: acks),
      );
      sock.add(ackEnv.writeToBuffer());
    }, onDone: () {
      if (identical(_activeSocket, sock)) _activeSocket = null;
    });
  }
}

void _appBuildTests() {
  group('OpsTransport', () {
    late _HttpServer server;

    setUp(() async {
      server = _HttpServer();
      await server.start();
    });

    tearDown(() async => server.stop());

    OutboundFrame frame(List<String> opIds) => OutboundFrame(
          kind: 'chat_payload',
          resourceId: dmChannelId('000000000', 'b1c2d3e4f'),
          peer: 'b1c2d3e4f',
          ops: [
            for (final id in opIds) FramedOp(opId: id, payload: [1, 2]),
          ],
        );

    test('posts the WS_OP beside the socket; the reply WS_ACK is the acks',
        () async {
      server.handler = (req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/wss/ops');
        final body =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        final sent = pb.WsEnvelope.fromBuffer(base64Decode(body['frame']));
        expect(sent.type, pb.WsType.WS_OP);
        expect(sent.ops.envelopes.single.opId, uuidBytes(_opId(1)));
        expect(sent.ops.envelopes.single.peer, userIdBytes('b1c2d3e4f'));
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'frame': base64Encode(pb.WsEnvelope(
            type: pb.WsType.WS_ACK,
            acks: pb.AckBatch(acks: [
              pb.Ack(
                  opId: uuidBytes(_opId(1)),
                  outcome: pb.AckOutcome.ACK_SUCCESS,
                  serverTimestampMs: fixnum.Int64(42)),
            ]),
          ).writeToBuffer()),
        }));
        await req.response.close();
      };
      final transport = OpsTransport(
        wsEndpoint: server.uri.replace(scheme: 'ws', path: '/wss'),
        auth: _FakeAuth('acc-ops'),
        httpClient: http.Client(),
      );
      final ack = transport.acks.first.timeout(const Duration(seconds: 3));
      await transport.send(frame([_opId(1)]));

      final got = await ack;
      expect(got.opId, _opId(1));
      expect((got.outcome as AckSuccess).serverTimestampMs, 42);
      expect(server.lastAuthHeader, 'Bearer acc-ops');
    });

    test('a refused request is an ack for every op in the frame', () async {
      server.handler = (req) async {
        req.response.statusCode = 401;
        await req.response.close();
      };
      final transport = OpsTransport(
        wsEndpoint: server.uri.replace(scheme: 'ws', path: '/wss'),
        auth: _FakeAuth('acc-ops'),
        httpClient: http.Client(),
      );
      final acks = transport.acks.take(2).toList();
      await transport.send(frame([_opId(1), _opId(2)]));

      final got = await acks.timeout(const Duration(seconds: 3));
      expect(got.map((a) => a.opId), [_opId(1), _opId(2)]);
      expect(got.every((a) => a.outcome is AckAuthFailure), isTrue);
    });
  });

  test('AssetClient.putBytes streams the body with its length, counting '
      'what went (SYNC_PROTOCOL 25.4)', () async {
    final server = _HttpServer();
    await server.start();
    addTearDown(server.stop);
    final got = BytesBuilder();
    String? length, md5;
    server.handler = (req) async {
      length = req.headers.value(HttpHeaders.contentLengthHeader);
      md5 = req.headers.value('content-md5');
      await req.forEach(got.add);
      await req.response.close();
    };
    final client = AssetClient(baseUrl: server.uri, auth: _FakeAuth('a'));
    addTearDown(client.dispose);
    final body = List<int>.generate(200 * 1024, (i) => i % 251);
    final seen = <int>[];
    await client.putBytes(
      url: server.uri.resolve('/put').toString(),
      bytes: body,
      contentType: 'application/octet-stream',
      contentMd5: 'bWQ1',
      onProgress: (sent, total) {
        expect(total, body.length);
        seen.add(sent);
      },
    );
    expect(got.takeBytes(), body);
    expect(length, '${body.length}', reason: 'never chunked: S3 refuses it');
    expect(md5, 'bWQ1');
    expect(seen, [65536, 131072, 196608, 204800]);
  });

  group('AppBuild (decision 192)', () {
    test('the socket sends the build and stops retrying once refused',
        () async {
      final server = _WsEchoServer()..refuseWith = 426;
      await server.start();
      addTearDown(server.stop);
      final appBuild = AppBuild(80);
      final transport = WsTransport(
          endpoint: server.uri, auth: _FakeAuth('acc-1'), appBuild: appBuild);
      addTearDown(transport.dispose);

      final refused = appBuild.changes.first;
      await transport.start();
      await refused.timeout(const Duration(seconds: 3));
      expect(appBuild.upgradeRequired, isTrue);
      expect(server.lastAppBuild, '80');
      // past the first backoff (1 s ± 25%): no second attempt
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(server.attempts, 1);
      expect(transport.currentState, TransportState.disconnected);
    });

    test('the client tags our server only and reads its answers', () async {
      final server = _HttpServer();
      await server.start();
      addTearDown(server.stop);
      String? seen;
      var status = 200;
      server.handler = (req) async {
        seen = req.headers.value('x-app-build');
        req.response.statusCode = status;
        req.response.headers.set('x-latest-app-build', '82');
        await req.response.close();
      };
      final appBuild = AppBuild(80);

      final other = AppBuildClient(appBuild, 'api.example.invalid');
      addTearDown(other.close);
      await other.get(server.uri);
      expect(seen, isNull, reason: 'a presigned R2 link is not our server');
      expect(appBuild.updateAvailable, isFalse);

      final ours = AppBuildClient(appBuild, server.uri.host);
      addTearDown(ours.close);
      await ours.get(server.uri);
      expect(seen, '80');
      expect(appBuild.updateAvailable, isTrue);
      expect(appBuild.upgradeRequired, isFalse);

      status = 426;
      await ours.get(server.uri);
      expect(appBuild.upgradeRequired, isTrue);
    });
  });
}

// ---------------------------------------------------------------------
// In-memory test HTTP server — runs a handler per request.
// ---------------------------------------------------------------------

class _HttpServer {
  HttpServer? _http;
  Future<void> Function(HttpRequest req)? handler;
  String? lastAuthHeader;

  Uri get uri => Uri.parse('http://127.0.0.1:${_http!.port}');

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http!.listen((req) async {
      lastAuthHeader = req.headers.value(HttpHeaders.authorizationHeader);
      final h = handler;
      if (h == null) {
        req.response.statusCode = 500;
        await req.response.close();
        return;
      }
      try {
        await h(req);
      } catch (e) {
        // If the handler crashes, make sure the response is closed so
        // the client doesn't hang indefinitely.
        try {
          req.response.statusCode = 500;
          req.response.write('handler_error: $e');
        } catch (_) {}
        try {
          await req.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> stop() async {
    await _http?.close(force: true);
  }
}

class _FakeAuth implements AuthTokenProvider {
  _FakeAuth(this.currentAccesskey);

  @override
  String? currentAccesskey;

  @override
  String? get currentUserId => 'u-self';

  @override
  Future<String?> refresh() async => currentAccesskey;
}

Future<void> _waitForState(WsTransport t, TransportState target) async {
  if (t.currentState == target) return;
  await t.state
      .firstWhere((s) => s == target)
      .timeout(const Duration(seconds: 3));
}

/// Decision 218: the edge between text ids and wire bytes.
void _wireTests() {
  group('wire edge', () {
    test('ids convert both ways and refuse a wrong length', () {
      expect(uuidText(uuidBytes(_group)), _group);
      expect(uuidBytes(_group), hasLength(16));
      expect(userIdBytes('1a2b3c4d5'), [0x01, 0xa2, 0xb3, 0xc4, 0xd5]);
      expect(userIdText([0x01, 0xa2, 0xb3, 0xc4, 0xd5]), '1a2b3c4d5');
      expect(opIdUserId(uuidBytes(_opId(1, 'fedcba987'))), 'fedcba987');
      for (final bad in [
        () => uuidText(List.filled(15, 0)),
        () => uuidText(List.filled(17, 0)),
        () => uuidBytes('g-1'),
        () => userIdText(List.filled(4, 0)),
        () => userIdText([0x10, 0, 0, 0, 0]), // past 36 bits
        () => userIdBytes('u-peer'),
        () => opIdUserId(List.filled(5, 0)),
      ]) {
        expect(bad, throwsFormatException);
      }
    });

    test('a DM sends its peer and no channel, a group the reverse; the '
        'class rides flags', () {
      final dm = wireEnvelope(
          opId: _opId(1, '0a1b2c3d4'),
          channelId: dmChannelId('0a1b2c3d4', 'f00dcafe1'),
          peer: 'f00dcafe1',
          payload: const [1],
          flags: FrameClass.message.flags);
      expect(dm.hasChannelId(), isFalse);
      expect(dm.peer, userIdBytes('f00dcafe1'));
      expect(dm.hasFlags(), isFalse, reason: 'a default is never encoded');
      expect(dm.hasEphemeral() || dm.hasTtlSec(), isFalse);

      final group = wireEnvelope(
          opId: _opId(2),
          channelId: _group,
          payload: const [1],
          flags: FrameClass.key.flags);
      expect(group.hasPeer(), isFalse);
      expect(group.channelId, uuidBytes(_group));
      expect((group.flags >> 1) & 15, 3);
      expect(group.flags & kEnvelopeFlagSilent, 1, reason: 'a key shows no notification');
    });

    test('inbound: the sender is the op id\'s bits, a DM\'s channel is '
        'derived from the pair, a server event has no sender', () {
      final dm = InboundEnvelope.fromWire(wireEnvelope(
          opId: _opId(1, '0a1b2c3d4'),
          channelId: '',
          peer: 'f00dcafe1',
          payload: const [8],
          senderDeviceId: _group,
          serverTimestampMs: 5));
      expect(dm.senderUserId, '0a1b2c3d4');
      expect(dm.peer, 'f00dcafe1');
      expect(dm.channelId, dmChannelId('f00dcafe1', '0a1b2c3d4'));
      expect(dm.serverTimestampMs, 5);

      final event = InboundEnvelope.fromWire(pb.Envelope(
          opId: uuidBytes('0190aaaa-bbbb-4ccc-8ddd-eeeeffff0001'),
          channelId: uuidBytes(_group),
          payload: const [0x53, 1]));
      expect(event.senderUserId, '', reason: 'a v4 op id carries no user');
      expect(event.channelId, _group);
      final byActor = InboundEnvelope.fromWire(pb.Envelope(
          opId: uuidBytes(_opId(3, '0a1b2c3d4')),
          channelId: uuidBytes(_group),
          payload: const [0x53, 1]));
      expect(byActor.senderUserId, '0a1b2c3d4',
          reason: 'a UUIDv7 the server minted names its actor');

      for (final bad in [
        pb.Envelope(opId: [1], channelId: uuidBytes(_group)),
        pb.Envelope(opId: uuidBytes(_opId(4))), // neither
        pb.Envelope(
            opId: uuidBytes(_opId(4)),
            channelId: uuidBytes(_group),
            peer: userIdBytes('f00dcafe1')), // both
        pb.Envelope(opId: uuidBytes(_opId(4)), peer: [1, 2, 3, 4]),
        pb.Envelope(opId: uuidBytes(_opId(4)), channelId: [1, 2]),
      ]) {
        expect(() => InboundEnvelope.fromWire(bad), throwsFormatException);
      }
    });

    test('an op id the wire cannot carry fails the op, not the socket',
        () async {
      final server = _WsEchoServer();
      await server.start();
      addTearDown(server.stop);
      final transport = WsTransport(endpoint: server.uri, auth: _FakeAuth('a'));
      addTearDown(transport.dispose);
      await transport.start();
      await _waitForState(transport, TransportState.connected);
      transport.endSyncBuffer();
      final ack = transport.acks.first;
      await transport.send(OutboundFrame(
          kind: 'chat_payload',
          resourceId: _group,
          ops: [FramedOp(opId: 'op-1', payload: const [0])]));
      final got = await ack.timeout(const Duration(seconds: 3));
      expect(got.opId, 'op-1');
      expect((got.outcome as AckPermanentReject).reason, 'validation_failed');
    });
  });
}
