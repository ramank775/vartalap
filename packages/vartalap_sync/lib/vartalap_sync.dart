/// Vartalap v3 sync layer — outbound op scheduler, idempotency, retry.
///
/// Per `docs/SPIKE_B_SYNC.md`:
/// - [SyncScheduler] runs the three decoupled flows (dispatch, ACK,
///   timeout) against the `outbound_ops` table.
/// - [BackoffPolicy] is injectable; [FixedBackoff] drives the §12 e2e
///   test at deterministic speed.
/// - [Uuid7Gen] produces client-side op_ids with the embedded user_id
///   bits the server validates (SYNC_PROTOCOL.md §3).
library vartalap_sync;

export 'src/backoff.dart'
    show BackoffPolicy, ExponentialJitterBackoff, FixedBackoff;
export 'src/clock.dart' show Clock, FakeClock;
export 'src/failure_watch.dart' show watchFailures;
export 'src/sync_scheduler.dart' show SyncScheduler;
export 'src/uuid7.dart' show Uuid7Gen;
