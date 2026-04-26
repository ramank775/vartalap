import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
/// Reconnect is automatic with exponential backoff (1s → 30s, jittered)
/// on unintended disconnects. In-flight ops are NOT re-issued — that's
/// the scheduler's job (SPIKE_B §5 Flow C).
class WsTransport implements Transport {
  final Uri endpoint;
  final AuthTokenProvider auth;

  final _ackCtrl = StreamController<AckFrame>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();
  final _pushCtrl = StreamController<pb.Envelope>.broadcast();

  /// Fires when the server sends a WS_REAUTH_REQUIRED frame. The auth
  /// layer subscribes and runs a session refresh; the WS will reconnect
  /// on its existing schedule and pick up the freshened accesskey
  /// during the next handshake. Race-tolerant: if reconnect fires
  /// before refresh completes the server will WS_REAUTH_REQUIRED again
  /// and the cycle continues until the new key is in place. AUTH_CONTRACT
  /// §6.3/4.
  final StreamController<void> _reauthCtrl =
      StreamController<void>.broadcast();
  Stream<void> get reauthRequired => _reauthCtrl.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  TransportState _state = TransportState.disconnected;

  bool _disposed = false;

  /// While true, inbound WS_PUSH and WS_ACK frames are buffered instead
  /// of being emitted onto [pushes] / [acks]. The client flips this on
  /// at every [TransportState.connected] transition and flips it off
  /// (flushing the buffer in arrival order) after [pullPendingSync]
  /// has injected all server-queued envelopes. This keeps the apply
  /// order correct: a server-queued ChannelCreated must land before
  /// any live message that depends on it. ACKs for the client's own
  /// in-flight ops are buffered too — the scheduler can't act on them
  /// until the projection catches up either.
  bool _buffering = false;
  final List<pb.Envelope> _pushBuffer = [];
  final List<AckFrame> _ackBuffer = [];

  /// Monotonic reconnect-attempt counter used for backoff pacing. Reset
  /// on every successful `connected` transition.
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  /// Random source for backoff jitter. Seedable for deterministic tests
  /// (though the transport tests don't currently exercise backoff).
  final Random _rng;

  WsTransport({
    required this.endpoint,
    required this.auth,
    Random? random,
  }) : _rng = random ?? Random();

  @override
  Stream<AckFrame> get acks => _ackCtrl.stream;

  @override
  Stream<TransportState> get state => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;

  /// Inbound chat-content fanout. `WS_PUSH` frames are surfaced here for
  /// the future inbound-receiver layer (step 9+). Not part of the
  /// `Transport` contract — the scheduler only consumes [acks].
  Stream<pb.Envelope> get pushes => _pushCtrl.stream;

  /// Inject an envelope onto the [pushes] stream. Used by the
  /// client-triggered sync pull (REST `GET /v3.0/sync/pending`) to
  /// deliver server-queued frames through the same fanout pipeline as
  /// live WS_PUSH frames — `InboundReceiver` doesn't care which path
  /// the envelope arrived on; dedup is keyed on `op_id`.
  void injectPush(pb.Envelope env) {
    if (_pushCtrl.isClosed) return;
    _pushCtrl.add(env);
  }

  /// Open the WS connection. Idempotent; safe to call multiple times.
  /// Errors on the initial upgrade surface as a transition to
  /// `disconnected`, which triggers reconnect.
  Future<void> start() async {
    if (_disposed) {
      throw StateError('WsTransport.start called after dispose');
    }
    await _connect();
  }

  /// Close the connection and stop reconnecting. After dispose the
  /// streams are closed and the transport cannot be restarted.
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeChannel();
    await _ackCtrl.close();
    await _stateCtrl.close();
    await _pushCtrl.close();
    if (!_reauthCtrl.isClosed) await _reauthCtrl.close();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    final token = auth.currentAccesskey;
    if (token == null) {
      // No session yet — don't even try. Stay disconnected; the UI will
      // kick us once auth lands (step 7 has the AuthClient wire).
      _setState(TransportState.disconnected);
      return;
    }

    _setState(TransportState.connecting);

    try {
      final socket = await IOWebSocketChannel.connect(
        endpoint,
        protocols: ['accesskey.$token'],
      );
      // web_socket_channel v3: `ready` completes once the upgrade succeeds.
      await socket.ready;
      if (_disposed) {
        await socket.sink.close();
        return;
      }
      _channel = socket;
      _reconnectAttempt = 0;
      // Arm the buffer BEFORE announcing `connected` so any frame the
      // server sends out the gate is captured rather than fanned out.
      // The state-stream listener will trigger a sync pull and call
      // [endSyncBuffer] to flush.
      _buffering = true;
      _setState(TransportState.connected);

      _wsSub = socket.stream.listen(
        _onFrame,
        onError: (Object e, StackTrace st) {
          // Stream error — treat as disconnect and schedule reconnect.
          // ignore: avoid_print
          print('WsTransport: stream error: $e');
          _onDisconnected();
        },
        onDone: _onDisconnected,
        cancelOnError: true,
      );
    } catch (e) {
      // Upgrade failed (401, DNS, refused, etc.). Schedule reconnect.
      // ignore: avoid_print
      print('WsTransport: connect failed: $e');
      _setState(TransportState.disconnected);
      _scheduleReconnect();
    }
  }

  Future<void> _closeChannel() async {
    final ch = _channel;
    _channel = null;
    final sub = _wsSub;
    _wsSub = null;
    await sub?.cancel();
    if (ch != null) {
      try {
        await ch.sink.close();
      } catch (_) {
        // Already closed or broken — nothing to do.
      }
    }
  }

  void _onDisconnected() {
    // ignore pile-ons — multiple disconnect signals collapse into one
    // reconnect pass.
    if (_state == TransportState.disconnected) return;
    _setState(TransportState.disconnected);
    _wsSub?.cancel();
    _wsSub = null;
    _channel = null;
    // Drop any buffered frames captured during the prior connection —
    // they belonged to a session that's now gone. The reconnect will
    // arm a fresh buffer and the next pull will refetch whatever the
    // server still has queued.
    _buffering = false;
    _pushBuffer.clear();
    _ackBuffer.clear();
    if (!_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt++;
    final delay = _backoffDelay(_reconnectAttempt);
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  /// Exponential backoff, 1s baseline, cap 30s, ±25% jitter.
  Duration _backoffDelay(int attempt) {
    // attempt >= 1
    final exp = 1 << min(attempt - 1, 5); // 1,2,4,8,16,32 → clamp below
    final baseSeconds = min(exp, 30);
    final jitter = (_rng.nextDouble() * 0.5 - 0.25) * baseSeconds;
    final seconds = max(1, (baseSeconds + jitter).round());
    return Duration(seconds: min(seconds, 30));
  }

  void _setState(TransportState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateCtrl.isClosed) _stateCtrl.add(next);
  }

  // ---- Outbound -------------------------------------------------------

  @override
  Future<void> send(OutboundFrame frame) async {
    final ch = _channel;
    if (ch == null || _state != TransportState.connected) {
      throw StateError('WsTransport.send: not connected');
    }

    // Build envelopes from the frame's ops. Per SYNC_PROTOCOL.md §5.4,
    // client→server envelopes carry op_id / channel_id / resource_seq /
    // client_timestamp_ms / payload. sender_user_id, server_timestamp_ms,
    // delivery_sequence are absent (server stamps on fanout).
    final envelopes = <pb.Envelope>[];
    for (final op in frame.ops) {
      final env = pb.Envelope(
        opId: op.opId,
        channelId: frame.resourceId,
        resourceSeq: fixnum.Int64(op.resourceSeq),
        clientTimestampMs: op.clientTimestampMs != null
            ? fixnum.Int64(op.clientTimestampMs!)
            : null,
        payload: op.payload,
      );
      envelopes.add(env);
    }

    final wsEnv = pb.WsEnvelope(
      type: pb.WsType.WS_OP,
      ops: pb.EnvelopeBatch(envelopes: envelopes),
    );

    Uint8List bytes;
    try {
      bytes = wsEnv.writeToBuffer();
    } catch (e) {
      throw StateError('WsTransport.send: malformed envelope: $e');
    }

    try {
      ch.sink.add(bytes);
    } catch (e) {
      // `WebSocketSink.add` throws synchronously if the sink is
      // closed/broken; surface as a "couldn't queue" error per the
      // Transport contract (SPIKE_B §7).
      throw StateError('WsTransport.send: sink rejected frame: $e');
    }
  }

  /// Fire-and-forget ephemeral envelope (typing, presence). Bypasses the
  /// outbound queue entirely — there's no scheduler, no retries, no ACK
  /// expected. If the WS isn't connected the envelope is silently
  /// dropped; that's the correct semantics for the kind of events that
  /// would only confuse a recipient if they arrived stale.
  ///
  /// `opId` should be a fresh UUIDv7 (the server still uses it for
  /// fanout deduplication within a single delivery wave) but the client
  /// does NOT track it locally — there's no row to settle when the
  /// implicit "ack" never comes back.
  bool sendEphemeral({
    required String opId,
    required String channelId,
    required Uint8List payload,
    int? clientTimestampMs,
  }) {
    final ch = _channel;
    if (ch == null || _state != TransportState.connected) return false;

    final env = pb.Envelope(
      opId: opId,
      channelId: channelId,
      // Server uses resource_seq for strict-monotone validation per
      // (user, channel). Ephemeral envelopes don't participate in that
      // ordering by contract, but the field is required on the wire —
      // we stamp 0 and rely on the server's ephemeral path to skip the
      // monotone check.
      resourceSeq: fixnum.Int64.ZERO,
      clientTimestampMs:
          clientTimestampMs != null ? fixnum.Int64(clientTimestampMs) : null,
      payload: payload,
      ephemeral: true,
    );
    final wsEnv = pb.WsEnvelope(
      type: pb.WsType.WS_OP,
      ops: pb.EnvelopeBatch(envelopes: [env]),
    );
    try {
      ch.sink.add(wsEnv.writeToBuffer());
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- Inbound --------------------------------------------------------

  void _onFrame(dynamic frame) {
    final bytes = _coerceBinary(frame);
    if (bytes == null) {
      // ignore: avoid_print
      print('WsTransport: ignoring non-binary frame ${frame.runtimeType}');
      return;
    }

    pb.WsEnvelope wsEnv;
    try {
      wsEnv = pb.WsEnvelope.fromBuffer(bytes);
    } catch (e) {
      // ignore: avoid_print
      print('WsTransport: malformed WsEnvelope: $e');
      return;
    }

    switch (wsEnv.type) {
      case pb.WsType.WS_ACK:
        _handleAckBatch(wsEnv.acks);
      case pb.WsType.WS_PUSH:
        _emitPush(wsEnv.push);
      case pb.WsType.WS_REAUTH_REQUIRED:
        // Tell the auth layer to refresh, then close. The reconnect
        // schedule races with the refresh — if reconnect wins, the
        // server WS_REAUTH_REQUIREDs us again and we loop until the
        // refreshed key is in `auth.currentAccesskey`.
        if (!_reauthCtrl.isClosed) _reauthCtrl.add(null);
        _closeChannel();
        _onDisconnected();
      case pb.WsType.WS_ERROR:
        // ignore: avoid_print
        print(
          'WsTransport: WS_ERROR code=${wsEnv.error.code} '
          'message=${wsEnv.error.message}',
        );
        _closeChannel();
        _onDisconnected();
      default:
        // WS_OP client→server only; WS_TYPE_UNSPECIFIED is illegal on
        // wire. Either is a server bug — log and ignore.
        // ignore: avoid_print
        print('WsTransport: unexpected inbound WsType=${wsEnv.type}');
    }
  }

  void _handleAckBatch(pb.AckBatch batch) {
    for (final ack in batch.acks) {
      final frame = AckFrame(opId: ack.opId, outcome: _outcomeFor(ack));
      _emitAck(frame);
    }
  }

  void _emitPush(pb.Envelope env) {
    if (_pushCtrl.isClosed) return;
    if (_buffering) {
      _pushBuffer.add(env);
      return;
    }
    _pushCtrl.add(env);
  }

  void _emitAck(AckFrame frame) {
    if (_ackCtrl.isClosed) return;
    if (_buffering) {
      _ackBuffer.add(frame);
      return;
    }
    _ackCtrl.add(frame);
  }

  /// Release the post-connect buffer. Called by the client after it has
  /// pulled and applied all server-queued envelopes. Live WS_PUSH and
  /// WS_ACK frames captured during the buffer window are flushed in
  /// arrival order; afterwards new frames go straight to the streams.
  /// Idempotent and safe to call when not buffering.
  void endSyncBuffer() {
    if (!_buffering) return;
    _buffering = false;
    final pushes = List<pb.Envelope>.from(_pushBuffer);
    final acks = List<AckFrame>.from(_ackBuffer);
    _pushBuffer.clear();
    _ackBuffer.clear();
    for (final env in pushes) {
      if (_pushCtrl.isClosed) break;
      _pushCtrl.add(env);
    }
    for (final ack in acks) {
      if (_ackCtrl.isClosed) break;
      _ackCtrl.add(ack);
    }
  }

  static AckOutcome _outcomeFor(pb.Ack ack) {
    switch (ack.outcome) {
      case pb.AckOutcome.ACK_SUCCESS:
        return AckSuccess(
          serverTimestampMs: ack.hasServerTimestampMs()
              ? ack.serverTimestampMs.toInt()
              : null,
          deliverySequence: ack.hasDeliverySequence()
              ? ack.deliverySequence.toInt()
              : null,
        );
      case pb.AckOutcome.ACK_TRANSIENT:
        return AckTransientReject(
          serverRetryAfter: ack.hasRetryAfterMs()
              ? Duration(milliseconds: ack.retryAfterMs.toInt())
              : null,
          reason: ack.hasReason() ? ack.reason : null,
        );
      case pb.AckOutcome.ACK_PERMANENT:
        return AckPermanentReject(
          reason: ack.hasReason() ? ack.reason : 'permanent',
        );
      case pb.AckOutcome.ACK_AUTH_FAILURE:
        return const AckAuthFailure();
      default:
        // ACK_OUTCOME_UNSPECIFIED — server bug. Surface as permanent so
        // the op lands in dead_letter rather than spinning forever.
        return const AckPermanentReject(reason: 'unknown_outcome');
    }
  }

  /// WS frames arrive as `List<int>` / `Uint8List` (binary) or `String`
  /// (text). We only speak binary per SYNC_PROTOCOL.md §5.3.
  Uint8List? _coerceBinary(dynamic frame) {
    if (frame is Uint8List) return frame;
    if (frame is List<int>) return Uint8List.fromList(frame);
    return null;
  }
}
