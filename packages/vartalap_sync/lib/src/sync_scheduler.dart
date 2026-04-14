import 'dart:async';

import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

import 'backoff.dart';
import 'clock.dart';

/// Outbound-op scheduler per SPIKE_B_SYNC.md §5.
///
/// Three decoupled flows that coordinate only through the database:
///   A — Dispatcher: picks dispatchable ops, flips them to `in_flight`,
///       hands frames to the transport. No awaits on ACKs.
///   B — ACK handler: subscribes to [Transport.acks]; on each ACK,
///       transitions the matching op (delete on success, rejected on
///       permanent, retrying on transient).
///   C — Timeout sweep: periodic; transitions stuck `in_flight` rows
///       back to `retrying`.
///
/// This scaffold implements Flow A (dispatch path) and Flow B (success
/// path) end-to-end for `chat_payload` ops on WS so the smoke test
/// can exercise `pending → sending → sent`. Rejection cascade
/// (SPIKE_B §8), coalescing (§5a), Flow C (§5), and retry backoff are
/// stubbed; they land with step 9 of the V3_ARCHITECTURE roadmap.
class SyncScheduler {
  final ChatStore store;
  final Transport wsTransport;
  final Transport restTransport;
  final BackoffPolicy backoff;
  final Clock clock;

  StreamSubscription<AckFrame>? _wsAckSub;
  StreamSubscription<AckFrame>? _restAckSub;

  final _tickSoon = StreamController<void>.broadcast();
  bool _running = false;

  SyncScheduler({
    required this.store,
    required this.wsTransport,
    required this.restTransport,
    required this.backoff,
    this.clock = Clock.system,
  });

  /// Wire the ACK handlers and run an initial dispatch pass.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _wsAckSub = wsTransport.acks.listen(_onAck, onError: (_) {});
    _restAckSub = restTransport.acks.listen(_onAck, onError: (_) {});
    _tickSoon.stream.listen((_) => _dispatchOnce());
    await _dispatchOnce();
  }

  Future<void> stop() async {
    _running = false;
    await _wsAckSub?.cancel();
    await _restAckSub?.cancel();
    _wsAckSub = null;
    _restAckSub = null;
  }

  /// Debounced signal that the dispatchable set may have changed.
  /// Called on enqueue, on ACK, on timeout sweep.
  void tickSoon() {
    if (!_tickSoon.isClosed) _tickSoon.add(null);
  }

  // ---------------------------------------------------------------------
  // Flow A — Dispatcher
  // ---------------------------------------------------------------------

  Future<void> _dispatchOnce() async {
    if (!_running) return;
    final dispatchable = await store.selectDispatchable(now: clock.nowMs());
    for (final op in dispatchable) {
      await _dispatchOne(op);
    }
  }

  Future<void> _dispatchOne(OutboundOpRow op) async {
    final transport =
        op.transport == OpTransport.ws ? wsTransport : restTransport;
    if (transport.currentState != TransportState.connected) {
      // Transport unavailable — wait for state change. Per SPIKE_B §12a,
      // "Transport unavailable is not an attempt" — no backoff tick.
      return;
    }

    final messageId = op.targetMessageId;
    if (messageId == null) {
      throw UnimplementedError(
        'Non-message op dispatch — wired in step 9 '
        '(channel CRUD / profile / push topic)',
      );
    }

    await store.markOpInFlight(
      opId: op.opId,
      messageId: messageId,
      nowMs: clock.nowMs(),
    );

    final frame = OutboundFrame(
      kind: op.kind,
      resourceId: op.resourceId,
      ops: [
        FramedOp(
          opId: op.opId,
          resourceSeq: op.resourceSeq,
          payload: op.payload,
        ),
      ],
    );
    try {
      await transport.send(frame);
    } catch (_) {
      // Per SPIKE_B §7: scheduler reverts in_flight → pending on throw.
      // Revert logic lands with step 9 (cascading + error classification).
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // Flow B — ACK handler
  // ---------------------------------------------------------------------

  Future<void> _onAck(AckFrame ack) async {
    final op = await store.fetchOutboundOp(ack.opId);
    if (op == null) return; // Already handled (double-ack, old row GC'd).

    final messageId = op.targetMessageId;
    switch (ack.outcome) {
      case AckSuccess(:final serverTimestampMs, :final deliverySequence):
        if (messageId != null) {
          await store.applyAckSuccess(
            opId: ack.opId,
            messageId: messageId,
            serverTimestampMs: serverTimestampMs ?? clock.nowMs(),
            deliverySequence: deliverySequence ?? 0,
            nowMs: clock.nowMs(),
          );
        } else {
          throw UnimplementedError(
            'Non-message ACK handling — wired in step 9',
          );
        }
      case AckTransientReject():
      case AckPermanentReject():
      case AckAuthFailure():
        throw UnimplementedError(
          'Transient/permanent/auth ACK handling — wired in step 9',
        );
    }

    tickSoon();
  }
}
