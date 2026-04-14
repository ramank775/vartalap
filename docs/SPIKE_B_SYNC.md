# Spike B — Sync Package Design

**Status:** Draft, 2026-04-14
**Branch:** `feat/v3-foundation`
**Supersedes:** `packages/taskq/` (to be deleted when v3 scaffold lands)

## 1. Why replace, not harden

`packages/taskq/lib/task_scheduler.dart:184` silently marks exception-throwing
tasks as `TaskStatus.completed` in its catch block (the bug is at line 184;
V3_ARCHITECTURE.md's citation of line 192 points one line past the end of
`schedule()` and should be updated). Its test file is `void main() {}`.
Beyond the bug, taskq's design (generic task-runner with a task dependency
graph) does not match v3's actual need (per-resource-ordered sync ops on a
closed set of operation kinds).

There are **zero call sites of taskq** outside the package itself in the
current `feat/v3-foundation` branch. Replacement is free.

## 2. Responsibility split

Three data sinks, three jobs:

| Table | Purpose | Mutability |
|---|---|---|
| `events` | Domain history | Append-only; retention-pruned |
| `*_projection` | Current state for UI | Recomputable from events |
| `outbound_ops` | Operational sync queue | Mutable; rows deleted on ACK |

**`events`** captures the *domain fact* ("message M sent in channel C").
Immutable. Auditable. Replayable. Stays forever (until retention-pruned).

**Projections** are the UI-readable current state. Recomputable from events.

**`outbound_ops`** is transient operational state — "what ops still need to
reach the server, how many attempts, when to retry next." Lives alongside
events in the same SQLite DB (see docs/SPIKE_A_LOCAL_STORE.md, Option C).
Every
`outbound_ops` row references an `event_id`; both rows are written in the
same transaction as the originating user action.

## 3. Schema

`outbound_ops` holds **both WS chat-content envelopes AND mutating
REST writes** (per `SYNC_PROTOCOL.md` §4). The `transport`
discriminator tells the dispatcher which transport adapter to use;
`kind` distinguishes the operation within the transport.

```sql
CREATE TABLE outbound_ops (
  op_id          TEXT PRIMARY KEY,           -- UUIDv7, client-generated
  event_id       TEXT NOT NULL,              -- references events.event_id
  transport      TEXT NOT NULL,              -- 'ws' | 'rest'
  kind           TEXT NOT NULL,              -- ws: 'chat_payload' (sole kind)
                                             -- rest: 'create_channel', 'add_members',
                                             --       'remove_member', 'edit_channel',
                                             --       'delete_channel', 'edit_profile',
                                             --       'register_push_topic'
  rest_method    TEXT,                       -- ws: NULL; rest: 'POST'|'PATCH'|'DELETE'
  rest_path      TEXT,                       -- ws: NULL; rest: '/v3.0/channels/<id>/members' etc.
  resource_id    TEXT NOT NULL,              -- ws: channel_id; rest: targeted entity id
  resource_seq   INTEGER NOT NULL,           -- monotonic per-(user_id, resource_id)
  payload        BLOB NOT NULL,              -- ws: serialized Envelope.payload bytes
                                             --     (the opaque chat-content bytes the server forwards)
                                             -- rest: serialized JSON request body
  status         TEXT NOT NULL,              -- pending | in_flight | retrying | rejected | dead_letter | cascaded_rejection
  attempts       INTEGER NOT NULL DEFAULT 0,
  next_retry_at  INTEGER NOT NULL,           -- ms since epoch; earliest dispatchable time
  dispatched_at  INTEGER,                    -- ms since epoch; set when status → in_flight
  last_error     TEXT,                       -- server reason or classified transport error
  acknowledged_at INTEGER,                   -- ms since epoch; user dismissed the error toast
  created_at     INTEGER NOT NULL
);

CREATE INDEX idx_outbound_ops_pending
  ON outbound_ops(next_retry_at)
  WHERE status IN ('pending', 'retrying');

CREATE INDEX idx_outbound_ops_inflight
  ON outbound_ops(dispatched_at)
  WHERE status = 'in_flight';

CREATE INDEX idx_outbound_ops_resource
  ON outbound_ops(resource_id, resource_seq);
```

**`transport` discriminator semantics:**

| `transport` | `kind` values | Adapter | Wire shape |
|---|---|---|---|
| `'ws'` | `'chat_payload'` | `WsTransport` | Wrapped in `Envelope` proto, sent on WS_OP frame |
| `'rest'` | `'create_channel'`, `'add_members'`, `'remove_member'`, `'edit_channel'`, `'delete_channel'`, `'edit_profile'`, `'register_push_topic'` | `RestTransport` | One HTTP request per op, body is `payload` JSON augmented with `op_id`, `resource_seq` |

The scheduler is transport-agnostic above the adapter layer (see
§7); it queries the same `outbound_ops` table, picks dispatchable
ops by `next_retry_at` and per-resource ordering, and hands off to
the adapter selected by `transport`.

**Per-resource ordering crosses transports.** A WS chat envelope
and a REST `add_members` for the same `channel_id` share the
`resource_id` and serialize against each other through the same
per-resource counter. The §5 dispatcher query treats `resource_id`
as opaque — it doesn't care which transport the next op uses.

**Status lifecycle:**
```
pending ──dispatch──▶ in_flight ──ACK success──────▶ (row deleted)
                           │
                           ├──ACK permanent reject──▶ rejected
                           ├──ACK transient reject──▶ retrying (next_retry_at set)
                           └──timeout sweep─────────▶ retrying (next_retry_at set)

retrying ──next_retry_at <= now──▶ dispatch (→ in_flight)
```

**On ACK:** row is deleted. Event remains in `events`.
**On terminal failure:** status set to `rejected`, `dead_letter`, or
`cascaded_rejection`. Row stays until user acknowledges the error, then is
garbage-collected after N minutes.

## 4. UUIDv7 layout with user + device id

```
 48 bits ms | 4 bits ver | 12 bits counter | 2 bits variant | 36 bits user_id | 4 bits device | 18 bits random
```

- **36-bit user_id** — assigned by server at first OTP signup; stored
  in `flutter_secure_storage` alongside access token. Returned on every
  login (same id for the same account). Supports ~68 billion users; random
  assignment + server-side duplication check at signup eliminates collision
  ceiling. Encoded on the wire as 9 lowercase hex chars
  (see `AUTH_CONTRACT.md` §2).
- **4-bit device** — slot for device linking in v3.1 (multi-device). For
  v3.0 single-device launch, always `0x0`. Supports up to 16 concurrent
  devices per user, comfortably above realistic messaging power-user limit
  (~6-8 devices).
- **18 random bits + 48 ms + 12 counter** — within-device uniqueness.
  Effective collision space for a single user-device: ~78 bits.
  `~10^-12` collision probability at 1M IDs generated per device.

**Server-side validation:** every inbound op's embedded `user_id` bits
must match the authenticated session's `user_id`. Mismatch → reject as
tampering (error kind: `prefix_mismatch` — the wire reason name is
preserved for backwards compat with the error-code catalogue, even
though the bit field is now called `user_id`).

**Client generation:** single-threaded, one `Uuid7Gen` instance holding
`user_id` + device slot + monotonic counter. Generate at op-creation time.

## 5. Scheduler architecture — three decoupled flows

The scheduler has **no awaits on per-op ACKs**. Waiting for an ACK in a
Dart Future would hang the whole pipeline if the ACK is lost, and would
fan out to N hung futures under load. Instead, the scheduler is three
independent flows that communicate **only through the database**. The DB
is the single source of truth; in-memory state is disposable and
reconstructible from the DB on every tick.

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│  Flow A: Dispatcher │    │  Flow B: Ack handler│    │  Flow C: Timeout     │
│  (wake on tickSoon)│    │  (listen to ws.acks)│    │  (periodic, 10s)     │
└──────────┬──────────┘    └──────────┬──────────┘    └──────────┬──────────┘
           │                           │                           │
           │ query dispatchable ops    │ transition op row         │ find timed-out in_flight
           │ set status=in_flight      │ by op_id                  │ transition to retrying
           │ transport.send(frame)     │ call tickSoon()           │ call tickSoon()
           │ (fire-and-forget)         │                           │
           └───────────────────────────┴───────────────────────────┘
                                       │
                              outbound_ops table
                              (single source of truth)
```

**Serial-per-resource-ACK-wait** is enforced by the Flow A query, not by
awaiting anything in memory. The query excludes op N+1 while op N is
still unfinished on the same resource. When Flow B marks op N as done
(row deleted) or Flow C transitions op N to retrying with a later
`next_retry_at`, Flow A's next tick sees op N+1 as dispatchable.

### Flow A — Dispatcher

Triggered by:
- `tickSoon()` — called by Flow B on ACK, Flow C on timeout, or on user
  action that enqueues a new op.
- Periodic safety-net timer (e.g., every 30s) — catches any missed wake.
- App foreground / WS reconnect.

Query for dispatchable ops:
```sql
SELECT * FROM outbound_ops o1
WHERE o1.status IN ('pending', 'retrying')
  AND o1.next_retry_at <= :now
  AND NOT EXISTS (
    SELECT 1 FROM outbound_ops o2
    WHERE o2.resource_id = o1.resource_id
      AND o2.resource_seq < o1.resource_seq
      AND o2.status IN ('pending', 'in_flight', 'retrying')
  )
ORDER BY o1.resource_id, o1.resource_seq;
```

This yields at most one op per resource (the earliest unfinished one),
across all resources — naturally gives cross-resource parallelism with
serial within-resource semantics.

Per op:
```
in one transaction:
  coalesce same-resource same-kind consecutive ops into one frame (§5a)
  UPDATE outbound_ops
    SET status='in_flight', dispatched_at=:now, attempts=attempts+1
    WHERE op_id IN (frame.op_ids)
transport.send(frame)  # fire-and-forget, returns immediately
```

No await. Dispatcher moves on to the next resource.

### Flow B — ACK handler

Subscribes to `transport.acks` — a `Stream<AckFrame>` surfaced by the
transport. Each ACK carries `{op_id, outcome, reason?}`.

Per ACK, in one transaction:
```
switch outcome:
  SUCCESS:
    DELETE FROM outbound_ops WHERE op_id = :op_id
  TRANSIENT_REJECT:
    UPDATE outbound_ops 
      SET status='retrying', 
          next_retry_at=:backoff(attempts), 
          last_error=:reason
      WHERE op_id = :op_id
  PERMANENT_REJECT:
    INSERT INTO events (... compensating event ...)
    projector applies rejection to projections
    UPDATE outbound_ops SET status='rejected', last_error=:reason WHERE op_id=:op_id
    cascade to later ops on same resource (§8)
```

After the transaction: `scheduler.tickSoon()`. The next Flow A tick sees
the resource unblocked and dispatches op N+1.

### Flow C — Timeout sweep

Runs on a periodic timer (e.g., every 10 seconds). Query:
```sql
UPDATE outbound_ops
  SET status='retrying', 
      next_retry_at=:backoff(attempts),
      last_error='ack_timeout'
  WHERE status='in_flight'
    AND dispatched_at + :timeout_ms < :now;
```

Timeout is per-op (e.g., 30s). If a frame's ACK never arrives
(connection died, server swallowed it), it comes back into the
dispatchable pool with incremented attempt count.

After the sweep, `tickSoon()`.

### Why the DB, not in-memory, is the coordination point

1. **Crash-safe.** App killed between dispatch and ACK → on restart, Flow
   C finds `in_flight` rows with old `dispatched_at`, transitions them
   to retrying.
2. **No hung futures.** No Completer map, no per-resource await state.
3. **Missed-signal safety.** If `tickSoon()` is lost (race condition),
   the next periodic Flow A wake catches up within 30s.
4. **One reasoning model.** "What's the state of op X?" is answered by a
   SELECT, not by inspecting Dart-side object graphs.

### The `tickSoon()` signal

Implementation: a debounced single-broadcast `StreamController<void>` or
a `Completer<void>` that's replaced after each completion. Flow A
listens for it. Calling `tickSoon()` completes the current completer;
Flow A runs one pass and re-arms.

Under burst load (many ACKs arriving fast), the debounce collapses them
into a single re-query — only one dispatcher pass runs, covering all
newly-dispatchable ops.

### 5a. Transport-level batching

Consecutive same-resource same-kind ops are coalesced into one wire frame
at dispatch time. Domain model (`events` table) stays one-row-per-op;
operational queue (`outbound_ops`) stays one-row-per-op; only the wire
frame collapses.

**Coalesceable kinds (initial set):**
- `send_message` → `send_messages` (list of message payloads)
- `react` → `reactions` (list of reaction payloads)
- `add_members` already takes a list — no coalescing needed at scheduler

**Not coalesceable:**
- `create_channel`, `edit_profile`, `delete_message`, `edit_message` —
  one-off ops; never batched.

**Algorithm** (at Flow A dispatch time, for the op just picked):
```
coalesce(first_op):
  if first_op.kind not in COALESCEABLE: return single(first_op)
  batch := [first_op]
  while true:
    peek := query next dispatchable op for first_op.resource_id
    if peek exists
        and peek.kind == first_op.kind
        and peek.resource_seq == batch.last.resource_seq + 1
        and batch.size < MAX_BATCH_SIZE (e.g., 20):
      batch.append(peek)
    else:
      break
  return multi(batch)
```

All ops in the batch transition to `in_flight` in the same transaction
as dispatch. Each op still gets its own ACK (matched by op_id via Flow B);
partial success is allowed — message 3 of 5 may be rejected while the
rest succeed. The next dispatcher tick picks up the resource's next op
only after all earlier ops on the resource are either acked-and-deleted
or rolled back.

**Why transport-level, not repository-level.** Keeps domain events
(`events` table) one-per-action; batching is a network optimization, not
a domain concept.

## 6. Retry with exponential backoff + jitter

**Backoff schedule (per op):**
```
base = 1 second
max  = 5 minutes
delay(n) = min(base * 2^(n-1), max) * (1 + random(0, 0.3))  // ±30% jitter
```

| Attempt | Nominal delay | With jitter range |
|---|---|---|
| 1 | 1s  | 1.0–1.3s |
| 2 | 2s  | 2.0–2.6s |
| 3 | 4s  | 4.0–5.2s |
| 4 | 8s  | 8.0–10.4s |
| 5 | 16s | 16–20.8s |
| 6 | 32s | 32–41.6s |
| 7 | 64s | 64–83.2s |
| 8 | 128s | 128–166s |
| 9 | 256s | 256–300s (capped) |
| 10+ | 300s | 300–390s (capped) |

**Retry limits:**
- Soft limit: **10 attempts** across connectivity gaps. Configurable.
- Hard limit: **48 hours since first attempt.** After that, move to
  dead-letter regardless of attempt count. Keeps retries from living
  forever for long-offline users.

Dead-letter is status change, not row deletion. The event stays. The user
can retry manually from the error UI or the dead-letter row is aged out
when the user acknowledges.

## 7. Transport contract

The scheduler is **transport-agnostic**. It speaks to an abstract
`Transport` that exposes three surfaces; neither returns a per-op Future
tied to server ACK.

```dart
abstract class Transport {
  /// Write the frame to the underlying channel. The returned Future
  /// completes when the frame is handed off to the wire — NOT when the
  /// server ACKs. Flow A does not track this Future per-op; ACK arrival
  /// is a separate event on [acks]. Throws only on "frame could not be
  /// queued at all" (malformed payload, send buffer full, no network).
  /// Scheduler reverts in_flight → pending on throw.
  Future<void> send(OutboundFrame frame);

  /// Inbound ACK stream. One event per server-produced ACK. Multiplexed
  /// across all pending ops; scheduler matches by op_id.
  Stream<AckFrame> get acks;

  /// Availability state — scheduler uses this to pause Flow A when the
  /// channel is unavailable.
  Stream<TransportState> get state;
}

class AckFrame {
  final String opId;
  final AckOutcome outcome;
  final String? reason;         // populated for reject variants; server-defined code
                                // like 'prefix_mismatch' or 'resource_id_taken'
}

sealed class AckOutcome {}
class AckSuccess extends AckOutcome {
  final Map<String, dynamic>? payload;  // server-returned fields
}
class AckTransientReject extends AckOutcome {
  // Server is temporarily unable to process. Scheduler retries with backoff.
  final Duration? serverRetryAfter;
}
class AckPermanentReject extends AckOutcome {
  // Server authoritatively rejects. Scheduler rolls back.
  // Examples: prefix_mismatch, resource_id_taken, forbidden, not_found,
  // validation_failed, gone.
}
class AckAuthFailure extends AckOutcome {
  // Token invalid. Scheduler pauses, triggers refresh, resumes.
}

enum TransportState { connected, connecting, disconnected }
```

**Transport NEVER retries. NEVER rolls back. NEVER dedupes.** All of that
lives in the scheduler. Transport is stateless framing + classification.

**Timeout is the scheduler's concern, not the transport's.** If an ACK
never arrives, Flow C's sweep transitions the op back to retrying. The
transport has no opinion on "how long is too long to wait" because it
doesn't wait.

**Unavailability is a transport state change, not a per-op failure.** When
`state` flips to `disconnected`, pending `in_flight` ops stay in_flight
(they may yet get ACKed on reconnect if the server processed them) until
Flow C times them out. New dispatches from Flow A wait for
`connected` — Flow A checks transport state at the top of each tick.

### 7a. Two transports, two jobs

Per `SYNC_PROTOCOL.md` §4 and `V3_ARCHITECTURE.md` decision 12, the
two transports are not interchangeable — they serve different op
classes. The scheduler dispatches each `outbound_ops` row via the
adapter selected by `transport`.

**`WsTransport`** — chat-content payloads only.
- Op kinds: `chat_payload` (the sole WS kind).
- Persistent WebSocket to chat-server (`wss://<host>/wss`).
- Wraps `outbound_ops.payload` (already opaque bytes per
  `SYNC_PROTOCOL.md` §6a) in an `Envelope` proto, batches up to 20
  envelopes per WS_OP frame (§5a coalescing applies).
- `send()` writes a WS frame; `acks` stream emits decoded `Ack`
  frames. `state` tracks WS lifecycle.
- Server fans out to other channel members immediately on accept.
- Available only when WS is connected (foreground or background-
  active). When unavailable, chat_payload ops stay `pending`; they
  do NOT fall back to REST (chat-content is WS-only).

**`RestTransport`** — server-state mutations.
- Op kinds: `create_channel`, `add_members`, `remove_member`,
  `edit_channel`, `delete_channel`, `edit_profile`,
  `register_push_topic` (and any future server-mutating REST
  endpoint added to `outbound_ops`).
- One HTTPS request per op (no batching — see `SYNC_PROTOCOL.md`
  §11.5).
- `send()` issues the request to `outbound_ops.rest_path` with
  `outbound_ops.rest_method`; body is `outbound_ops.payload` JSON
  augmented with `op_id`, `resource_seq`, `client_timestamp_ms`.
- `acks` stream emits `Ack` translated from the HTTP response per
  the §8.1 mapping in `SYNC_PROTOCOL.md` (2xx → SUCCESS,
  401 → AUTH_FAILURE, 4xx → PERMANENT, 5xx → TRANSIENT).
- `state` reflects basic network reachability — no persistent
  connection.
- Available whenever the network is reachable. Independent of WS
  state.

**Selection logic.** Trivial — pick by `outbound_ops.transport`:
```
if op.transport == 'ws':
  use WsTransport (must wait for WS connected)
else:  # 'rest'
  use RestTransport (proceeds whenever network is reachable)
```

There is no transport "fallback." A `chat_payload` op cannot be
dispatched over REST (the server's REST endpoints don't accept
opaque chat envelopes — chat content is WS-only by design). A REST
op cannot be dispatched over WS (the WS wire only routes opaque
chat payloads to channel members; it does not handle channel
mutations).

**Read-style REST calls are not in the queue.** `GET /v3.0/users/me`,
`GET /v3.0/users/<id>`, `POST /v3.0/contacts/lookup`, and the auth
endpoints (`/v3.0/auth/...`) do NOT go through `outbound_ops`. They
are synchronous calls the UI makes directly via a separate HTTP
client. They block on network and surface failure to the user. See
`SYNC_PROTOCOL.md` §4.2.

**Why this split, not a unified transport.**
- Server stays opaque to chat content (decision 13). WS wire is
  pure routing; REST wire is server-state mutation.
- Adding a new chat-content type does not touch the server, the
  WS proto, or this scheduler. Adding a new server-state mutation
  adds a REST endpoint and a new `kind` value in `outbound_ops`,
  but the scheduler is otherwise unchanged.
- WS keep-alive cost only matters when the user is actively using
  the app; at v3.0 single-device scale, foreground WS is the
  common case and background WS is rare.

**REST writes still produce WS fanout.** When a REST write completes
server-side, the server emits a `ServerEventPayload` envelope to all
affected members on their active WS connections (`SYNC_PROTOCOL.md`
§10.2). The originating client receives the HTTP response directly;
other channel members observe the change as an inbound WS push.

**No mid-dispatch transport switching.** A `chat_payload` op
dispatched on WS that hits a network partition stays `in_flight`
until Flow C times it out, then re-dispatches on WS once
reconnected. A REST op stays `in_flight` until the HTTP timeout,
then re-dispatches.

## 8. Rejection → compensating event cascade

When Flow B receives `AckPermanentReject` for an op:

```sql
BEGIN TRANSACTION;

-- 1. Append rejection as a domain event
INSERT INTO events (event_id, event_type, channel_id, payload, created_at)
VALUES (
  uuid7_gen(),
  'op_rejected',                -- or kind-specific: 'channel_creation_rejected'
  :resource_id,
  json_object(
    'rejected_op_id', :op_id,
    'rejected_kind',  :kind,
    'server_reason',  :reason,
    'http_status',    :status
  ),
  :now
);

-- 2. Projector handles the rejection event (delete optimistic projection rows).
--    Handler depends on kind — for 'channel_created' rejection: delete channel
--    and message projections for that channel.

-- 3. Mark originating op as rejected
UPDATE outbound_ops 
SET status = 'rejected', last_error = :reason
WHERE op_id = :op_id;

-- 4. Cascade-reject any subsequent pending ops on the same resource
UPDATE outbound_ops
SET status = 'cascaded_rejection',
    last_error = 'parent ' || :kind || ' rejected: ' || :reason
WHERE resource_id = :resource_id
  AND resource_seq > :rejected_seq
  AND status IN ('pending', 'retrying');

COMMIT;
```

**Why cascade.** If `create_group(G)` is rejected, the subsequent
`add_members(G)` and `send_message(G)` are guaranteed to fail server-side
(resource doesn't exist). Cascading saves the round trips and lets the UI
show one coherent error rather than three in sequence.

**Cross-resource ops stay unaffected.** A rejection on `resource_id=G` does
not touch ops for other resources.

## 9. Idempotency / dedup (decision 10)

Every outbound op carries its `op_id` (UUIDv7, client-generated). Transport
includes it in the request (header or body). Server-side: **receivers dedup
by op_id**. A retry of an already-applied op gets the same success response,
not a duplicate side-effect.

This means the scheduler can safely retry on unknown ACK state (e.g., timeout
after the request reached the server but the response was lost) without
coordinating with the server about in-flight retries.

Server dedup window is server's concern, not client's. Client assumes "any
op_id I've sent will be dedup'd if I send it again."

## 10. User-visible error surface

A reactive query:
```dart
Stream<List<FailedOp>> watchFailures() {
  return db.rawQuery('''
    SELECT * FROM outbound_ops
    WHERE status IN ('rejected', 'dead_letter', 'cascaded_rejection')
      AND acknowledged_at IS NULL
    ORDER BY created_at DESC
  ''').watch();
}
```

UI subscribes. Each entry shows up as a toast / inline error on the
relevant surface (chat header, group member list, profile screen).
Per-kind UX is a UI-layer decision.

Acknowledgment (user taps dismiss or "retry manually") sets
`acknowledged_at` and a GC job removes old rows after 24 hours.

## 11. Garbage collection

Background task on app launch + every 15 minutes of activity:
- Safety-net delete for any row with a terminal-success marker (in this
  design successful ops are already deleted at ACK time, so this is a
  no-op unless a code bug leaves a stale row).
- Delete `outbound_ops` where status in (rejected, dead_letter,
  cascaded_rejection) AND acknowledged_at IS NOT NULL AND
  acknowledged_at < now - 24h.
- Trigger `events` retention pruning (docs/SPIKE_A_LOCAL_STORE.md
  follow-up #1) in the same job.

## 12. Pass/fail gate (V3_ARCHITECTURE.md decision 5)

> Replacement must demonstrate an end-to-end test: an op throws three
> times, is retried with backoff, is moved to dead-letter on fourth
> attempt, and surfaces a user-visible error. No silent completion.

Realized as `test/e2e_retry_dead_letter_test.dart`:
1. Scaffold store + scheduler with a mock transport scripted to emit
   `AckTransientReject` for the first 3 ACKs matching an op_id, then
   `AckPermanentReject` (or silent-drop to force Flow C timeout path).
2. Enqueue a `send_message` op.
3. Advance injected clock to drain retry backoff across all attempts.
4. Assert: attempt count hits the configured retry limit, op row
   transitions to `dead_letter` (not silently `completed`).
5. Assert: failure stream emits the op with reason.
6. Assert: projection for the message reflects the compensating event
   (message tombstoned or removed, depending on kind).

For the test, retry limit lowered to 3 and backoff base to 10ms via
injected `BackoffPolicy` + `Clock` so the test runs in <1s deterministically.

## 12a. Transport picked by op kind

Per §7a, the transport for a queued op is determined by
`outbound_ops.transport`, set at enqueue time:

- `transport='ws'` (kind=`chat_payload`) → `WsTransport`. Available
  only when WS is connected.
- `transport='rest'` (other kinds) → `RestTransport`. Available
  whenever the network is reachable.

Note that `register_push_topic` IS in the queue (REST write that
mutates server-owned state in notification-ms), unlike the read-only
calls below.

The following calls are NOT in the queue — they are synchronous
HTTP calls the UI makes directly via a separate HTTP client:
- OTP send / verify / resend
- Session refresh / revoke (logout)
- Account delete (one-shot terminal op)
- Phone rebind start / verify
- Contact discovery (`POST /v3.0/contacts/lookup`)
- Profile read (`GET /v3.0/users/me`, `GET /v3.0/users/<id>`)

These either have no offline semantics (lookups, reads) or are
session-management operations whose timing matters to the user
(login, logout, account changes the user is actively waiting on).

When the relevant transport is unavailable (WS down for chat
payloads, network down for REST writes), `outbound_ops` rows stay
`pending`. On transport recovery, the scheduler drains them.
"Transport unavailable" is not an attempt — backoff applies only to
per-op server errors, not to waiting-for-transport.

## 13. What this package is not

- **Not a general task-runner.** Only outbound sync ops. Future
  non-sync background work uses a separate mechanism (Workmanager
  periodic tasks, timers, or its own queue).
- **Not a dependency-graph manager.** Per-resource ordering via
  `(resource_id, resource_seq)` replaces explicit deps.
- **Not a transport.** HTTP/WS requests live in the transport package.
  Scheduler hands payloads to transport, receives classified outcomes.
- **Not a store.** Reuses the event-sourced SQLite DB from Spike A.
  `outbound_ops` lives in the same file for cross-table transactions.

## 14. Package surface

```
package:spike_sync
  ├── SyncScheduler      // main entry; start(), stop(), enqueue(op), tickSoon()
  ├── OutboundOp         // value type, mirrors outbound_ops row shape
  ├── AckFrame           // transport → scheduler ACK message
  ├── AckOutcome         // AckSuccess | AckTransientReject | AckPermanentReject | AckAuthFailure
  ├── Transport          // abstract: send(frame), acks stream, state stream
  ├── BackoffPolicy      // exp + jitter, configurable, injectable for tests
  ├── Clock              // injectable for tests; used by backoff and Flow C sweep
  └── watchFailures()    // Stream<List<FailedOp>> for UI error surface
```

## 15. Open items for scaffold

1. **Per-kind projection rollback handlers.** Each op kind needs a
   rejection-event handler that undoes the optimistic projection state.
   Enumerate kinds in scaffold; `channel_created`, `members_added`,
   `message_sent`, `message_edited`, `message_deleted`, `profile_edited`,
   `reaction_added`, `reaction_removed`.
2. **Workmanager integration.** Outgoing-sync drain scheduled to run on
   connectivity change + periodic wake (per architecture doc
   "Workmanager is outgoing-only" rule). Not in Spike B scope; hooks
   exposed via `SyncScheduler.start()`.
3. **`user_id` provisioning via AUTH_CONTRACT.** OTP verify response
   carries `user_id` (36 bits, 9 hex chars). Storage via
   `flutter_secure_storage`. Refresh on every successful login and
   session refresh.
4. **Contact-discovery and other server-gated actions.** Not routed
   through the sync scheduler — they block on network and return synchronous
   results. Different mechanism (direct transport call).
5. **Outbox drain on auth refresh.** When token refresh completes, resume
   paused scheduler; ops paused on `AckAuthFailure` become dispatchable
   again via the normal Flow A tick after resume.

## 16. Artifacts

- `packages/spike_sync/` (to be created) — skeleton + tests
- `test/e2e_retry_dead_letter_test.dart` — gate-compliant e2e
- This file — design
