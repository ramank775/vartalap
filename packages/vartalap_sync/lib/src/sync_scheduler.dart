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
///   B — ACK handler: subscribes to [Transport.acks]; transitions ops
///       on success / transient reject / permanent reject / auth
///       failure.
///   C — Timeout sweep: periodic; `in_flight` rows whose
///       `dispatched_at + timeout` is in the past go back to `retrying`.
///
/// Coalescing (SPIKE_B §5a) is not yet applied — every frame is single
/// op until we have the wire transport to measure against.
class SyncScheduler {
  final ChatStore store;
  final Transport wsTransport;
  final Transport restTransport;
  final BackoffPolicy backoff;
  final Clock clock;

  /// Soft retry limit — SPIKE_B_SYNC.md §6.
  final int maxAttempts;

  /// Hard retry ceiling — SPIKE_B_SYNC.md §6.
  final Duration maxAge;

  /// In-flight ACK timeout — SPIKE_B_SYNC.md §5 Flow C.
  final Duration inFlightTimeout;

  /// Flow C sweep cadence.
  final Duration sweepInterval;

  StreamSubscription<AckFrame>? _wsAckSub;
  StreamSubscription<AckFrame>? _restAckSub;
  StreamSubscription<void>? _tickSub;
  Timer? _sweepTimer;

  final _tickSoon = StreamController<void>.broadcast();
  bool _running = false;

  /// Paused on AUTH_FAILURE until the auth layer refreshes. Flow A
  /// checks this at the top of each tick.
  bool _authPaused = false;

  /// Fires whenever an outbound op gets an ACK_AUTH_FAILURE. The auth
  /// layer subscribes and triggers a session refresh; on success it
  /// calls [resumeAfterAuthRefresh] which flips [_authPaused] back to
  /// false and re-runs Flow A. The signal is intentionally
  /// "something failed auth" rather than "with this op" — coalescing
  /// is the subscriber's job.
  final StreamController<void> _authFailures =
      StreamController<void>.broadcast();
  Stream<void> get authFailures => _authFailures.stream;

  /// Futures for every async work item kicked off by the flows
  /// (dispatch passes, ack-handler invocations, timeout sweeps). [stop]
  /// awaits them all so a caller that does
  /// `await scheduler.stop(); await store.close();` never races a
  /// dispatch mid-transaction against a closed DB.
  final Set<Future<void>> _inFlight = <Future<void>>{};

  SyncScheduler({
    required this.store,
    required this.wsTransport,
    required this.restTransport,
    required this.backoff,
    this.clock = Clock.system,
    this.maxAttempts = 10,
    this.maxAge = const Duration(hours: 48),
    this.inFlightTimeout = const Duration(seconds: 30),
    this.sweepInterval = const Duration(seconds: 10),
  });

  /// Wire the ACK handlers, start Flow C, and run an initial dispatch.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _wsAckSub = wsTransport.acks.listen(
      (ack) => _track(_onAck(ack)),
      onError: (_) {},
    );
    _restAckSub = restTransport.acks.listen(
      (ack) => _track(_onAck(ack)),
      onError: (_) {},
    );
    _tickSub = _tickSoon.stream.listen((_) => _track(_dispatchOnce()));
    _sweepTimer = Timer.periodic(
      sweepInterval,
      (_) => _track(_sweepTimeouts()),
    );
    await _dispatchOnce();
  }

  /// Stops the scheduler and waits for every work item kicked off by
  /// any flow to finish. After this completes the caller can safely
  /// close the [ChatStore] without racing a mid-transaction dispatch.
  Future<void> stop() async {
    _running = false;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    await _tickSub?.cancel();
    _tickSub = null;
    await _wsAckSub?.cancel();
    await _restAckSub?.cancel();
    _wsAckSub = null;
    _restAckSub = null;
    // Drain whatever was in flight when the flip happened. We snapshot
    // because a completing item removes itself from [_inFlight] via
    // the whenComplete in [_track], so the set mutates as we await.
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList());
    }
    if (!_authFailures.isClosed) await _authFailures.close();
  }

  /// Adds [future] to [_inFlight] and removes it on completion. The
  /// returned Future is the same as the argument — callers usually
  /// ignore the return value (fire-and-forget pattern used by the
  /// tickSoon listener and the sweep timer).
  Future<void> _track(Future<void> future) {
    _inFlight.add(future);
    future.whenComplete(() => _inFlight.remove(future));
    return future;
  }

  /// Debounced signal that the dispatchable set may have changed.
  /// Called on enqueue, on ACK, on timeout sweep.
  void tickSoon() {
    if (!_tickSoon.isClosed) _tickSoon.add(null);
  }

  /// Called by the auth layer after it has refreshed the accesskey.
  /// Unpauses Flow A so paused ops can re-dispatch.
  void resumeAfterAuthRefresh() {
    _authPaused = false;
    tickSoon();
  }

  // ---------------------------------------------------------------------
  // Flow A — Dispatcher
  // ---------------------------------------------------------------------

  Future<void> _dispatchOnce() async {
    if (!_running || _authPaused) return;
    final dispatchable = await store.selectDispatchable(now: clock.nowMs());
    // Re-check after the await — stop() may have fired while we were
    // suspended on the DB read. Hitting the store below with
    // `_running == false` can still succeed if it hasn't been closed
    // yet, but the guard keeps intent crisp: once stopped, do no more
    // work.
    if (!_running) return;
    for (final op in dispatchable) {
      if (!_running) return;
      await _dispatchOne(op);
    }
  }

  Future<void> _dispatchOne(OutboundOpRow op) async {
    final transport =
        op.transport == OpTransport.ws ? wsTransport : restTransport;
    if (transport.currentState != TransportState.connected) {
      // Transport unavailable — wait for state change. Per SPIKE_B
      // §12a, "Transport unavailable is not an attempt": no backoff,
      // no attempt counter increment. The next tickSoon() on transport
      // reconnect will re-select this op.
      return;
    }

    await store.markOpInFlight(
      opId: op.opId,
      messageId: op.targetMessageId,
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
          clientTimestampMs: clock.nowMs(),
          restMethod: op.restMethod,
          restPath: op.restPath,
        ),
      ],
    );
    try {
      await transport.send(frame);
    } catch (e) {
      // Per SPIKE_B_SYNC.md §7: "Scheduler reverts in_flight → pending
      // on throw." The transport couldn't even queue the frame — treat
      // it like a transport outage and re-dispatch on the next tick
      // without counting it against the retry budget.
      await store.markOpRetrying(
        opId: op.opId,
        nextRetryAt: clock.nowMs(),
        reason: 'send_threw:${e.runtimeType}',
      );
      tickSoon();
    }
  }

  // ---------------------------------------------------------------------
  // Flow B — ACK handler
  // ---------------------------------------------------------------------

  Future<void> _onAck(AckFrame ack) async {
    if (!_running) return;
    final op = await store.fetchOutboundOp(ack.opId);
    if (!_running) return;
    if (op == null) return; // Double-ack, or row GC'd. Safe to ignore.

    final outcome = ack.outcome;
    switch (outcome) {
      case AckSuccess():
        await _handleSuccess(op, outcome);
      case AckTransientReject():
        await _handleTransient(op, outcome);
      case AckPermanentReject():
        await _handlePermanent(op, outcome);
      case AckAuthFailure():
        await _handleAuthFailure(op);
    }

    tickSoon();
  }

  Future<void> _handleSuccess(OutboundOpRow op, AckSuccess ack) async {
    final messageId = op.targetMessageId;
    if (messageId == null) {
      // Non-message ACK — REST channel-create / profile-patch / etc.
      // Delete the op row; the local projection (channel row, profile)
      // was already applied optimistically at enqueue time.
      await store.deleteOp(op.opId);
      return;
    }
    await store.applyAckSuccess(
      opId: op.opId,
      messageId: messageId,
      serverTimestampMs: ack.serverTimestampMs ?? clock.nowMs(),
      deliverySequence: ack.deliverySequence ?? 0,
      nowMs: clock.nowMs(),
    );
  }

  Future<void> _handleTransient(
    OutboundOpRow op,
    AckTransientReject ack,
  ) async {
    // Both soft-attempt and hard-age limits apply — whichever hits
    // first. Attempts has already been incremented by Flow A's
    // markOpInFlight; we check against the post-increment value.
    if (_exhausted(op)) {
      await _moveToDeadLetter(op, ack.reason ?? 'retry_limit_exceeded');
      return;
    }
    final delay = ack.serverRetryAfter ?? backoff.delayFor(op.attempts);
    await store.markOpRetrying(
      opId: op.opId,
      nextRetryAt: clock.nowMs() + delay.inMilliseconds,
      reason: ack.reason ?? 'transient',
    );
  }

  Future<void> _handlePermanent(
    OutboundOpRow op,
    AckPermanentReject ack,
  ) async {
    await store.applyPermanentReject(
      opId: op.opId,
      resourceId: op.resourceId,
      rejectedSeq: op.resourceSeq,
      reason: ack.reason,
      messageId: op.targetMessageId,
      nowMs: clock.nowMs(),
    );
  }

  Future<void> _handleAuthFailure(OutboundOpRow op) async {
    // Pause Flow A so we don't burn attempts while the token is bad.
    // The op itself goes back to retrying — no attempt charged — and
    // will re-dispatch once the auth layer calls resumeAfterAuthRefresh().
    _authPaused = true;
    await store.markOpRetrying(
      opId: op.opId,
      nextRetryAt: clock.nowMs(),
      reason: 'auth_failure',
    );
    if (!_authFailures.isClosed) _authFailures.add(null);
  }

  // ---------------------------------------------------------------------
  // Flow C — Timeout sweep
  // ---------------------------------------------------------------------

  Future<void> _sweepTimeouts() async {
    if (!_running) return;
    final now = clock.nowMs();
    final cutoff = now - inFlightTimeout.inMilliseconds;
    final stuck = await store.selectInFlightOlderThan(cutoffMs: cutoff);
    if (!_running) return;
    for (final op in stuck) {
      if (!_running) return;
      if (_exhausted(op)) {
        await _moveToDeadLetter(op, 'ack_timeout');
      } else {
        await store.markOpRetrying(
          opId: op.opId,
          nextRetryAt: now + backoff.delayFor(op.attempts).inMilliseconds,
          reason: 'ack_timeout',
        );
      }
    }
    if (stuck.isNotEmpty) tickSoon();
  }

  // ---------------------------------------------------------------------
  // Retry-limit decision
  // ---------------------------------------------------------------------

  bool _exhausted(OutboundOpRow op) {
    if (op.attempts >= maxAttempts) return true;
    final ageMs = clock.nowMs() - op.createdAt;
    if (ageMs >= maxAge.inMilliseconds) return true;
    return false;
  }

  Future<void> _moveToDeadLetter(OutboundOpRow op, String reason) async {
    await store.markOpDeadLetter(
      opId: op.opId,
      reason: reason,
      messageId: op.targetMessageId,
      nowMs: clock.nowMs(),
    );
  }
}
