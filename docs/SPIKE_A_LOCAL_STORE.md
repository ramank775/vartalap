# Spike A — Local Store Decision

**Status:** Decided, 2026-04-14
**Branch:** `feat/v3-foundation`
**Winner:** Event-sourced log on a single SQLite database
**Runner-up:** Raw `sqflite` with hand-rolled repositories

## Decision

v3 local store is an **event-sourced log with materialized projections**,
persisted in a **single SQLite database** via `sqflite_common_ffi`.

Structure:
- `events` — append-only log, one row per user-observable action
- `channel_projection`, `message_projection`, `op_id_seen` — current-state
  views, maintained synchronously in the same transaction as the event insert
- `snapshots` (to be added in scaffold) — "events below this id have been
  applied and can be pruned" marker

Pragmas applied on open (both in spike and the future scaffold):
- `journal_mode = WAL`
- `synchronous = NORMAL`
- `wal_autocheckpoint = 1000`

## Why event-sourced

Perf is not the deciding factor — all three candidates (drift, sqflite,
event-sourced) pass the v3 gate (reads p95 < 10ms, writes p95 < 50ms) on
emulator in profile build, some with large margin.

The deciding factors are architectural:

1. **Sync-order bug class is eliminated by construction.** Past experience
   in this project: with plain sqlite, keeping track of what has been sent
   to the server and in what order produced unseen, non-reproducible bugs
   driven by race conditions in the write-and-enqueue sequence. Event logs
   serialize this: the log *is* the order record; replay is deterministic;
   bug reports can ship the events table and be reproduced locally.
2. **The sync layer (decision 4 + 10) and the event log are the same
   shape.** Per-resource sequence, op-id dedup, retry/dead-letter — all
   natural as projections/extensions of the event log rather than a
   parallel state machine that has to be kept consistent with local state.
3. **Decision 11 (tombstones + 5s undo + rollback on server reject) is a
   first-class fit.** Delete = append a delete event. Undo = append a
   restore event. Server reject = append a rollback event. No separate
   "in-flight undo state" to track.
4. **Audit / debugging / backup.** "Why does this row look like that?"
   becomes `SELECT * FROM events WHERE channel_id = ?`. Backup is a dump
   of the events table, which is replayable on any schema version.

## Why single SQLite (Option C), not two databases

Considered:
- **A.** Same DB, no explicit pruning — rejected for long-term disk growth
  without a story.
- **B.** Separate events DB and projections DB — rejected because
  cross-database ACID requires `ATTACH DATABASE` with awkward journal-mode
  constraints, and without it a mid-flight projection update can orphan an
  event (or vice versa), re-introducing exactly the bug class event-
  sourcing was picked to eliminate.
- **C.** Single DB with explicit event retention protocol — **picked.**

Option C properties:
- Event insert + projection update in one transaction — never divergent.
- Events pruned in-place via `DELETE FROM events WHERE event_id <= :snapshot_max`
  in WAL mode (non-blocking to readers).
- Disk reclaimed periodically via `VACUUM` on a maintenance cycle, or
  left to SQLite's freelist reuse for steady-state messengers.
- Export (for ship-to-server or user-requested backup) = `SELECT ... FROM events`
  + dump to compressed file.

The thing Option B would have bought — physical file separation for easy
file-copy handoff to analysts — is addressable with SQLite's online-backup
API if ever needed. Not a reason to give up single-transaction safety.

## Why sqflite (runner-up) is not picked

- Simpler, shorter, every-Flutter-dev-knows-it.
- Slightly faster on perf (7.5ms batch-insert p95 vs 14ms on ES in
  profile build) but both are well under gate.
- **Does not eliminate the sync-order bug class**, which is the specific
  thing this project has been burned by. Sqflite gives you state, never
  history; reproducing a bug from a user report requires reconstructing
  the write sequence, which is the problem we are trying to design around.

If event-sourced ever proves too heavy to maintain, sqflite is the
fallback. It is not harder to migrate to event-sourced → sqflite than the
reverse — projections are already sqlite tables.

## Why drift is rejected

- Performance-competitive on writes.
- **Watch amplification:** `.watch()` re-runs on any write to the watched
  table, regardless of whether the write affected the watched rows. Measured
  result: 100 wasted re-emits per 100 writes into an *unrelated* channel.
  In production this manifests as every push-delivered message triggering a
  full re-query for every open chat stream, scaling with `(active_groups ×
  open_streams)`. Mitigations exist (`.distinct()`, narrow stream lifetime)
  but are discipline-dependent: every new reactive query has to remember
  them, and the failure mode is silent UI over-rendering, not a loud crash.
- Compile-time SQL safety + typed codegen are nice, but not worth the
  amplification cost on the one hot path that matters for a messenger.

## Why isar and objectbox were dropped pre-benchmark

- **Isar:** upstream `isar` has not had a stable release since 3.1.0 in
  2023; `4.0.0-dev.14` has been dormant for ~2 years; community forks
  (`isar_community`, `isar_plus`) exist but fork-of-a-fork is exactly the
  maintenance-risk red flag called out in Spike A criterion 11. A 5+ year
  project does not pick a dependency with this trajectory.
- **ObjectBox:** Dart binding is Apache-2.0, but the native C core is
  source-available under a license with commercial gating, which is
  incompatible with the F-Droid release target (Spike A criterion 7).

## Measured numbers

Emulator: `sdk gphone64 x86 64`, Android 16 / API 36, profile build,
`flutter drive`. Dataset: 1k channels, 100k messages, Pareto distribution.
All three candidates use WAL + `synchronous=NORMAL` pragmas.

| Scenario                    | drift  | sqflite | **event-sourced** |
|-----------------------------|-------:|--------:|------------------:|
| chat_list_cold (ms)         | 1.23   | 5.45    | **2.14**          |
| chat_list_warm p95          | 1.71   | 5.09    | **2.89**          |
| messages_read p95           | 0.38   | 1.10    | **5.63**          |
| batch_insert_100 p95        | **2.92** | 5.86  | 13.97             |
| single_send p95             | **0.16** | 1.29  | 1.33              |
| watch_amplification p95     | 3.16   | 1.87    | 5.03              |
| **watch amplification emits** | **100/100 (fail)** | 0/100 | 0/100     |

**Gate: reads p95 < 10ms, writes p95 < 50ms.** All three candidates pass
on emulator with margin. Gate-compliant measurement on a real mid-range
device (Snapdragon 6xx class) is still required before shipping — current
measurements are on an SD855+-class emulator in profile build and should
be re-validated against hardware.

The event-sourced batch-insert gap (13.97ms vs sqflite's 5.86ms) is
absolute, not tail-latency, and reflects the 2x-writes-per-op cost of
event + projection. Well under the 50ms write gate.

## Follow-ups carried into scaffold

1. **Snapshot + compaction protocol.** Add `snapshots` table and write the
   retention policy. Recommendation: prune events older than 30 days that
   are below the latest snapshot. Runs on app launch as a bounded-time
   background task. Not a v3.0 blocker; retention cutoff can be set
   conservatively at launch and tuned from user data.
2. **Real-device gate verification.** Re-run the harness on Realme X2 Pro
   (SD855+) for upper-bound confirmation, and note the gap to a
   mid-range SD6xx device as an outstanding verification task. The
   emulator numbers are directional.
3. **Inbound-rate scenario.** The `watch_amplification` scenario measures
   per-write cost and wasted-emit count but does not yet measure sustained
   inbound throughput (e.g., 20 msgs/sec into one channel with 3 open
   channel streams across the app). Worth adding during v3 sync layer
   work.
4. **Schema-evolution plan.** Event payload is JSON for forward-
   compatibility. Projections are rebuilt on schema version bump.
   Protocol for "replay is slow, show progress" first-launch-after-upgrade
   UX is a scaffold concern.
5. **Sync-queue-as-events.** Per decision 4 + 10, outgoing sync ops should
   live as events tagged pending-server-ack, transitioning to
   server-ack / server-rejected by subsequent events. This collapses the
   "local store + outbound queue" into one log and removes a whole class
   of inconsistency. Design out in Spike B.

## Artifacts

- `packages/spike_store/` — `ChatStore` interface, three implementations,
  `SeedGenerator`, `Uuid7`. Kept in-tree as reference; not shipped.
- `packages/spike_bench/` — `flutter drive` benchmark app.
- `docs/SPIKE_A_RESULTS_emulator_2026-04-14.md` — raw numbers from the
  profile-build emulator run.
- This file — decision.
