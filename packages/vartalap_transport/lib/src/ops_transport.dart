import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vartalap_proto/vartalap_proto.dart' as pb;

import 'ack.dart';
import 'auth_token_provider.dart';
import 'rest_transport.dart' show classifyHttpStatus;
import 'transport.dart';
import 'ws_transport.dart' show ackOutcomeOf, opFrame;

/// The socket's op frames over https, `POST <ws endpoint>/ops`
/// (SYNC_PROTOCOL.md §5.11), for an engine with no socket: a push wake,
/// the queued-send job. One request per frame; the reply carries the
/// `WS_ACK` the socket would have sent. Wire failures come back as
/// transient acks, as on [RestTransport].
class OpsTransport implements Transport {
  final Uri endpoint;
  final AuthTokenProvider auth;
  final http.Client _client;

  final _ackCtrl = StreamController<AckFrame>.broadcast();

  /// [wsEndpoint]: the socket's own URL; the route lives beside it.
  OpsTransport({
    required Uri wsEndpoint,
    required this.auth,
    required http.Client httpClient,
  })  : endpoint = wsEndpoint.replace(
          scheme: wsEndpoint.scheme == 'wss' ? 'https' : 'http',
          path: '${wsEndpoint.path}/ops',
        ),
        _client = httpClient;

  @override
  Stream<AckFrame> get acks => _ackCtrl.stream;

  // Only ever started where there is network (a push just arrived, the
  // job's network constraint held); a request that fails is an ack.
  @override
  Stream<TransportState> get state => const Stream.empty();

  @override
  TransportState get currentState => TransportState.connected;

  @override
  Future<void> send(OutboundFrame frame) async {
    final token = auth.currentAccesskey;
    if (token == null) throw StateError('OpsTransport.send: no accesskey');
    final body = jsonEncode(
        {'frame': base64Encode(opFrame(frame).writeToBuffer())});
    unawaited(_issue(frame, token, body));
  }

  Future<void> _issue(OutboundFrame frame, String token, String body) async {
    AckOutcome failed;
    try {
      final resp = await _client
          .post(endpoint,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: body)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        failed = classifyHttpStatus(resp.statusCode);
      } else {
        final reply = pb.WsEnvelope.fromBuffer(base64Decode(
            (jsonDecode(resp.body) as Map<String, dynamic>)['frame']
                as String));
        for (final ack in reply.acks.acks) {
          _emit(AckFrame(opId: ack.opId, outcome: ackOutcomeOf(ack)));
        }
        return;
      }
    } catch (e) {
      failed = AckTransientReject(reason: 'network_error:${e.runtimeType}');
    }
    for (final op in frame.ops) {
      _emit(AckFrame(opId: op.opId, outcome: failed));
    }
  }

  void _emit(AckFrame frame) {
    if (!_ackCtrl.isClosed) _ackCtrl.add(frame);
  }
}
