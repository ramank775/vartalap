import 'ack.dart';
import 'wire.dart' show FrameClass, kEnvelopeFlagSilent;

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

  /// Trim 4 — the other participant's `user_id` when [resourceId] is a
  /// derived DM channel (`"d"`-prefixed); null for groups. Stamped on
  /// every envelope in the frame as `Envelope.peer`, in place of the
  /// channel (decision 218): the server recomputes `dm_chan(sender,
  /// peer)` from it instead of reading a channel row.
  final String? peer;

  const OutboundFrame({
    required this.kind,
    required this.resourceId,
    required this.ops,
    this.peer,
  });
}

class FramedOp {
  final String opId;
  final List<int> payload;

  /// REST-only. Populated by the scheduler for ops whose transport is
  /// [OpTransport.rest]. `RestTransport.send` uses these to issue the
  /// HTTPS request; `WsTransport` ignores them.
  ///
  /// For WS ops these are null — the envelope is routed entirely by
  /// `channel_id` on the wire (see SYNC_PROTOCOL.md §5.4).
  final String? restMethod;
  final String? restPath;

  /// Sent in `Envelope.flags` (decision 218): only a message or a
  /// resend request wakes an offline recipient.
  final FrameClass frameClass;

  /// Null: as [frameClass] says. Set where one class holds both kinds,
  /// as live location does (a remote on/off wakes, a position does not).
  final bool? wakes;

  /// `Envelope.ttl_sec`; 0 is the server's maximum (30 days). A timed
  /// message's timer (decision 222), a live-location op's keep time.
  final int ttlSec;

  const FramedOp({
    required this.opId,
    required this.payload,
    this.restMethod,
    this.restPath,
    this.frameClass = FrameClass.message,
    this.wakes,
    this.ttlSec = 0,
  });

  /// `Envelope.flags`: the class, and SILENT unless the op wakes.
  int get flags => wakes == null
      ? frameClass.flags
      : (frameClass.index << 1) | (wakes! ? 0 : kEnvelopeFlagSilent);
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
