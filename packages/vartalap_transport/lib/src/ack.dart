/// Normalized ACK shape surfaced by every transport adapter.
///
/// SPIKE_B_SYNC.md §7: both `WsTransport` and `RestTransport` decode
/// their wire responses into an [AckFrame] so the scheduler can handle
/// them uniformly. Neither transport retries, rolls back, or dedups —
/// those concerns live in `vartalap_sync`.
library vartalap_transport.ack;

sealed class AckOutcome {
  const AckOutcome();
}

/// Op applied. For WS, `serverTimestampMs` and `deliverySequence` carry
/// the same values the recipients will see on the fanout envelope
/// (SYNC_PROTOCOL.md §8).
class AckSuccess extends AckOutcome {
  final int? serverTimestampMs;
  final int? deliverySequence;
  const AckSuccess({this.serverTimestampMs, this.deliverySequence});
}

/// Server is temporarily unavailable. Scheduler retries with backoff.
class AckTransientReject extends AckOutcome {
  final Duration? serverRetryAfter;
  final String? reason;
  const AckTransientReject({this.serverRetryAfter, this.reason});
}

/// Server authoritatively rejects. Scheduler rolls back.
///
/// Reason codes per SYNC_PROTOCOL.md §8.1 (WS) / AUTH_CONTRACT error
/// envelope (REST): `prefix_mismatch`, `forbidden`, `out_of_order`,
/// `validation_failed`, `rate_limited`, `not_found`, `gone`, ...
class AckPermanentReject extends AckOutcome {
  final String reason;
  const AckPermanentReject({required this.reason});
}

/// 401 / `ACK_AUTH_FAILURE` — scheduler pauses, triggers refresh, resumes.
class AckAuthFailure extends AckOutcome {
  const AckAuthFailure();
}

/// Single ACK surfaced on [Transport.acks].
class AckFrame {
  final String opId;
  final AckOutcome outcome;
  const AckFrame({required this.opId, required this.outcome});
}
