import 'dart:async';

import 'ack.dart';
import 'auth_token_provider.dart';
import 'transport.dart';

/// REST adapter per SPIKE_B_SYNC.md §7a (REST side) and
/// SYNC_PROTOCOL.md §11.
///
/// - One HTTPS request per op (no batching — §11.5).
/// - Bearer auth; body is the op payload augmented with `op_id`,
///   `resource_seq`, `client_timestamp_ms` at frame time.
/// - HTTP status → [AckOutcome] per §8.1:
///     2xx → [AckSuccess]
///     401 → [AckAuthFailure]
///     4xx → [AckPermanentReject]
///     5xx → [AckTransientReject] (502/503/504 retriable)
///
/// Wired in step 8 of the V3_ARCHITECTURE roadmap.
class RestTransport implements Transport {
  final Uri baseUrl;
  final AuthTokenProvider auth;

  RestTransport({required this.baseUrl, required this.auth});

  @override
  Future<void> send(OutboundFrame frame) =>
      throw UnimplementedError('RestTransport.send — wired in step 8');

  @override
  Stream<AckFrame> get acks =>
      throw UnimplementedError('RestTransport.acks — wired in step 8');

  @override
  Stream<TransportState> get state =>
      throw UnimplementedError('RestTransport.state — wired in step 8');

  @override
  TransportState get currentState => TransportState.disconnected;
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
