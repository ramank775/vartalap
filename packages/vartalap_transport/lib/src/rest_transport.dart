import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ack.dart';
import 'auth_token_provider.dart';
import 'transport.dart';

/// REST adapter per SPIKE_B_SYNC.md §7a (REST side) and
/// SYNC_PROTOCOL.md §11.
///
/// - One HTTPS request per op (no batching — §11.5).
/// - Bearer auth; body is the op payload augmented with `op_id`,
///   `resource_seq`, `client_timestamp_ms` at frame time
///   (SYNC_PROTOCOL.md §11.2).
/// - HTTP status → [AckOutcome] per §8.1:
///     2xx → [AckSuccess]
///     401 → [AckAuthFailure]
///     4xx → [AckPermanentReject]
///     5xx → [AckTransientReject] (502/503/504 retriable)
class RestTransport implements Transport {
  final Uri baseUrl;
  final AuthTokenProvider auth;
  final http.Client _client;
  final bool _ownsClient;

  final _ackCtrl = StreamController<AckFrame>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();

  bool _disposed = false;

  // TODO(v3-step-10): replace hard-coded `connected` with
  // `connectivity_plus`-backed state so the scheduler pauses Flow A
  // when there's no network at all. For now REST is treated as always
  // available — `RestTransport.send` surfaces transport failures via
  // its ACK stream (transient on IO error) rather than via state.
  TransportState _state = TransportState.connected;

  RestTransport({
    required this.baseUrl,
    required this.auth,
    http.Client? httpClient,
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  @override
  Stream<AckFrame> get acks => _ackCtrl.stream;

  @override
  Stream<TransportState> get state => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;

  Future<void> dispose() async {
    _disposed = true;
    if (_ownsClient) _client.close();
    await _ackCtrl.close();
    await _stateCtrl.close();
  }

  // ---- Outbound -------------------------------------------------------

  @override
  Future<void> send(OutboundFrame frame) async {
    if (_disposed) {
      throw StateError('RestTransport.send after dispose');
    }
    if (frame.ops.length != 1) {
      // Per SYNC_PROTOCOL.md §11.5 REST is strictly single-op.
      throw StateError(
        'RestTransport.send: expected 1 op, got ${frame.ops.length}',
      );
    }
    final op = frame.ops.single;
    final method = op.restMethod;
    final path = op.restPath;
    if (method == null || path == null) {
      throw StateError(
        'RestTransport.send: FramedOp missing restMethod/restPath — '
        'scheduler must populate these for REST ops',
      );
    }

    final token = auth.currentAccesskey;
    if (token == null) {
      throw StateError('RestTransport.send: no accesskey');
    }

    // §11.2 — every REST write body carries op_id, resource_seq,
    // client_timestamp_ms merged with the endpoint-specific payload.
    // The scheduler persists payload as JSON bytes. Empty payload (e.g.
    // DELETE) is fine — we just send the three standard fields.
    Map<String, dynamic> body;
    if (op.payload.isEmpty) {
      body = <String, dynamic>{};
    } else {
      try {
        final decoded = jsonDecode(utf8.decode(op.payload));
        if (decoded is Map<String, dynamic>) {
          body = Map<String, dynamic>.from(decoded);
        } else {
          throw StateError(
            'RestTransport.send: payload is not a JSON object '
            '(got ${decoded.runtimeType})',
          );
        }
      } catch (e) {
        throw StateError('RestTransport.send: payload not JSON: $e');
      }
    }
    body['op_id'] = op.opId;
    body['resource_seq'] = op.resourceSeq;
    if (op.clientTimestampMs != null) {
      body['client_timestamp_ms'] = op.clientTimestampMs;
    }

    final uri = baseUrl.resolve(path);
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // Issue the request — failures are handed back via `acks`, not via
    // a throw. The only throw-path is "couldn't queue at all": no
    // network library, no auth token, no path. Wire errors become
    // AckTransientReject so the scheduler retries with backoff.
    unawaited(_issue(
      method: method,
      uri: uri,
      headers: headers,
      body: jsonEncode(body),
      opId: op.opId,
    ));
  }

  Future<void> _issue({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required String opId,
  }) async {
    http.Response resp;
    try {
      resp = await _send(method, uri, headers, body);
    } catch (e) {
      // Network failure before we got an HTTP status. Treat as transient
      // per SPIKE_B §7 (ACK taxonomy); scheduler backs off and retries.
      _emit(AckFrame(
        opId: opId,
        outcome: AckTransientReject(reason: 'network_error:${e.runtimeType}'),
      ));
      return;
    }

    final reason = _parseErrorCode(resp);
    final outcome = classifyHttpStatus(resp.statusCode, reason: reason);
    _emit(AckFrame(opId: opId, outcome: outcome));
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String body,
  ) {
    switch (method.toUpperCase()) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri, headers: headers, body: body);
      case 'PATCH':
        return _client.patch(uri, headers: headers, body: body);
      case 'PUT':
        return _client.put(uri, headers: headers, body: body);
      case 'DELETE':
        return _client.delete(uri, headers: headers, body: body);
      default:
        throw ArgumentError('RestTransport: unsupported method $method');
    }
  }

  /// Pull `error.code` off an AUTH_CONTRACT §11 error envelope for
  /// non-2xx responses. Returns null if the body is empty, not JSON, or
  /// doesn't carry the expected shape.
  String? _parseErrorCode(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return null;
    if (resp.body.isEmpty) return null;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        final err = decoded['error'];
        if (err is Map<String, dynamic>) {
          final code = err['code'];
          if (code is String && code.isNotEmpty) return code;
        }
      }
    } catch (_) {
      // Non-JSON body (HTML from a reverse proxy, plain text) — no
      // code to extract. The transport's status-code classification
      // still stands.
    }
    return null;
  }

  void _emit(AckFrame frame) {
    if (!_ackCtrl.isClosed) _ackCtrl.add(frame);
  }
}

/// Map an HTTP response to the internal ACK taxonomy per §8.1.
///
/// Pure function so the sync package can reuse the mapping in tests
/// without a live HTTP client.
AckOutcome classifyHttpStatus(int status, {String? reason}) {
  if (status >= 200 && status < 300) {
    return const AckSuccess();
  }
  if (status == 401) return const AckAuthFailure();
  if (status == 502 || status == 503 || status == 504) {
    return AckTransientReject(reason: reason);
  }
  if (status >= 400 && status < 500) {
    return AckPermanentReject(reason: reason ?? 'http_$status');
  }
  // All other 5xx — treat as transient.
  return AckTransientReject(reason: reason ?? 'http_$status');
}
