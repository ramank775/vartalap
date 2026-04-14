import 'dart:async';

import 'ack.dart';
import 'auth_token_provider.dart';
import 'transport.dart';

/// WS adapter per SPIKE_B_SYNC.md §7a (WS side) and SYNC_PROTOCOL.md
/// §5.
///
/// - `wss://<host>/wss`, `Sec-WebSocket-Protocol: accesskey.<token>`
///   subprotocol auth.
/// - Frames carry `WsEnvelope` protos; `WS_OP` up (batched up to 20
///   envelopes per frame, §5a), `WS_ACK` / `WS_PUSH` / `WS_ERROR` /
///   `WS_REAUTH_REQUIRED` down.
/// - Only `chat_payload` ops ride this transport. Server never parses
///   `Envelope.payload` (§6a).
///
/// This scaffold exposes the surface; the wire encoding and reconnect
/// loop land with step 8 of the V3_ARCHITECTURE roadmap.
class WsTransport implements Transport {
  final Uri endpoint;
  final AuthTokenProvider auth;

  WsTransport({required this.endpoint, required this.auth});

  @override
  Future<void> send(OutboundFrame frame) =>
      throw UnimplementedError('WsTransport.send — wired in step 8');

  @override
  Stream<AckFrame> get acks =>
      throw UnimplementedError('WsTransport.acks — wired in step 8');

  @override
  Stream<TransportState> get state =>
      throw UnimplementedError('WsTransport.state — wired in step 8');

  @override
  TransportState get currentState => TransportState.disconnected;
}
