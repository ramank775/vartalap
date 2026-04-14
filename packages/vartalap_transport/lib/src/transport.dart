import 'ack.dart';

/// Transport state per SPIKE_B_SYNC.md §7.
enum TransportState { connected, connecting, disconnected }

/// One wire frame, potentially batching multiple ops (SPIKE_B §5a).
///
/// - WS: batched envelopes in a single `WS_OP` frame.
/// - REST: always single-op (no batching — SYNC_PROTOCOL.md §11.5).
class OutboundFrame {
  final String kind;
  final String resourceId;
  final List<FramedOp> ops;

  const OutboundFrame({
    required this.kind,
    required this.resourceId,
    required this.ops,
  });

  bool get isBatch => ops.length > 1;
}

class FramedOp {
  final String opId;
  final int resourceSeq;
  final List<int> payload;
  final int? clientTimestampMs;

  const FramedOp({
    required this.opId,
    required this.resourceSeq,
    required this.payload,
    this.clientTimestampMs,
  });
}

/// Transport contract per SPIKE_B_SYNC.md §7.
///
/// Executes framing only. Never retries, rolls back, or dedups.
/// Scheduler is the only consumer.
abstract class Transport {
  /// Handoff a frame to the wire. Completes when the frame is written;
  /// NOT when the server ACKs. Throws only on "frame could not be queued
  /// at all" (malformed payload, send buffer full, no network).
  Future<void> send(OutboundFrame frame);

  /// Inbound ACK stream. One event per server-produced Ack.
  Stream<AckFrame> get acks;

  /// Availability state — scheduler uses this to pause Flow A when the
  /// channel is unavailable.
  Stream<TransportState> get state;

  TransportState get currentState;
}
