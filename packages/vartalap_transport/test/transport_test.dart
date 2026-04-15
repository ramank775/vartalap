import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:test/test.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
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
            deliverySequence: fixnum.Int64(99),
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

      await transport.send(OutboundFrame(
        kind: 'chat_payload',
        resourceId: 'channel-xyz',
        ops: [
          FramedOp(
            opId: 'op-1',
            resourceSeq: 1,
            payload: const [1, 2, 3],
            clientTimestampMs: 1000,
          ),
        ],
      ));

      final ack = await ackFuture;
      expect(ack.opId, 'op-1');
      expect(ack.outcome, isA<AckSuccess>());
      final success = ack.outcome as AckSuccess;
      expect(success.serverTimestampMs, 1700000);
      expect(success.deliverySequence, 99);

      // Server saw the accesskey subprotocol.
      expect(server.lastSubprotocol, 'accesskey.acc-1');

      // Server decoded the outbound envelope correctly.
      expect(server.lastEnvelope, isNotNull);
      expect(server.lastEnvelope!.opId, 'op-1');
      expect(server.lastEnvelope!.channelId, 'channel-xyz');
      expect(server.lastEnvelope!.resourceSeq.toInt(), 1);
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

      final ackFuture = transport.acks.first.timeout(
        const Duration(seconds: 3),
      );
      await transport.send(OutboundFrame(
        kind: 'chat_payload',
        resourceId: 'c',
        ops: [
          FramedOp(opId: 'op-2', resourceSeq: 1, payload: const [0]),
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

      final ackFuture = transport.acks.first.timeout(
        const Duration(seconds: 3),
      );
      await transport.send(OutboundFrame(
        kind: 'chat_payload',
        resourceId: 'c',
        ops: [
          FramedOp(opId: 'op-3', resourceSeq: 1, payload: const [0]),
        ],
      ));

      final ack = await ackFuture;
      expect(ack.outcome, isA<AckAuthFailure>());
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
          ops: [FramedOp(opId: 'op', resourceSeq: 1, payload: const [0])],
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

      server.pushEnvelope(pb.Envelope(
        opId: 'push-op-1',
        channelId: 'ch-abc',
        resourceSeq: fixnum.Int64(7),
        senderUserId: '1a2b3c4d5',
        serverTimestampMs: fixnum.Int64(1800000),
        deliverySequence: fixnum.Int64(42),
        payload: utf8.encode('hi'),
      ));

      final pushed = await pushFuture;
      expect(pushed.opId, 'push-op-1');
      expect(pushed.senderUserId, '1a2b3c4d5');
      expect(pushed.deliverySequence.toInt(), 42);
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
          expect(body['resource_seq'], 5);
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
            resourceSeq: 5,
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
            resourceSeq: 1,
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
            resourceSeq: 1,
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
            resourceSeq: 2,
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
            FramedOp(opId: 'op', resourceSeq: 1, payload: utf8.encode('{}')),
          ],
        )),
        throwsStateError,
      );
    });

    test('classifyHttpStatus maps across the §8.1 table', () {
      expect(classifyHttpStatus(200), isA<AckSuccess>());
      expect(classifyHttpStatus(201), isA<AckSuccess>());
      expect(classifyHttpStatus(401), isA<AckAuthFailure>());
      expect(classifyHttpStatus(403), isA<AckPermanentReject>());
      expect(classifyHttpStatus(404, reason: 'not_found'),
          predicate<AckOutcome>((o) =>
              o is AckPermanentReject && o.reason == 'not_found'));
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
    // Echo the first subprotocol token back — required for a valid
    // upgrade when the client requested one.
    final sock = await WebSocketTransformer.upgrade(
      req,
      protocolSelector: (protocols) =>
          protocols.isNotEmpty ? protocols.first : '',
    );
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
