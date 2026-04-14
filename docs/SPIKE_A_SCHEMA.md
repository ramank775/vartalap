# Spike A — Local Store Schema

**Status:** v1.0 (2026-04-14)
**Branch:** `feat/v3-foundation`
**Supersedes:** the "event log" framing in `SPIKE_A_LOCAL_STORE.md` —
see §1 for the reconciliation.

This is the concrete client-side SQLite schema for v3.0. It follows
from:

- `SPIKE_A_LOCAL_STORE.md` (local store decision: single SQLite, WAL,
  projection tables).
- `SPIKE_B_SYNC.md` (outbound queue and scheduler).
- `SYNC_PROTOCOL.md` (wire protocol, §6a opaque-payload model, §6a.4
  recipient-enforcement, §7.2 op_id dedup).
- `proto/v3-envelope.proto`,
  `proto/v3-chat-payload.proto`.
- `V3_ARCHITECTURE.md` decisions 3, 4, 10, 11, 12.

Read those first. This doc specifies the tables, not the rationale.

---

## 1. Reconciliation with SPIKE_A_LOCAL_STORE.md

SPIKE_A_LOCAL_STORE.md was written around an "event-sourced log +
materialized projections" framing. On review, the event-log portion
was protecting only against **outbound-ordering bugs** — the
sync-order bug class the team has been burned by. Inbound events do
not benefit from being logged: the chat-server is a relay
(decision 3), so there is no authoritative server-side history to
replay against, and projection rows carry enough metadata
(`server_timestamp_ms`, `delivery_sequence`, `author_user_id`) to
answer every debugging question on their own.

**The v3.0 model simplifies to:**

- **Projection tables** (`channels`, `messages`, `reactions`,
  `contacts`, `channel_members`) hold **all** state — local and
  inbound, treated uniformly.
- **`outbound_ops`** (the SPIKE_B table, unchanged in concept) holds
  **only the user's own unsynced actions**. Rows exist while an op
  is pending dispatch or awaiting server ACK; rows are deleted on
  success, retained briefly on rejection for user-visible error
  surface (SPIKE_B §10), then garbage-collected.
- **There is no separate event log.** The previous "events" table
  in SPIKE_A is renamed and absorbed into `outbound_ops` — same
  shape, same purpose.

What SPIKE_A_LOCAL_STORE.md's selling points survive under this
reframing:

1. **Sync-order bug class eliminated** — still true. `outbound_ops`
   is the ordered record of what needs to sync, per `(user_id,
   resource_id)`.
2. **Sync layer and local state same shape** — still true, trivially
   (outbound_ops IS the sync layer's state).
3. **Tombstones + 5s undo + rollback fit naturally** — still true.
   The outbound_ops row carries the tombstone during the undo window
   (not dispatched) and through ACK (dispatched); projection is
   optimistically updated; server reject flips projection back.
4. **Audit / debugging / backup** — weakens slightly (no full event
   stream of inbound to `SELECT *`). Mitigated by projection rows
   carrying enough metadata for deterministic reconstruction.

Net: schema is simpler, write amplification drops (inbound messages
do one INSERT instead of two), and disk footprint is bounded by
message count rather than lifetime-event count.

---

## 2. Database-level settings

Open with (per `feedback_sqlite_wal_pragmas`):

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous  = NORMAL;
PRAGMA wal_autocheckpoint = 1000;
PRAGMA foreign_keys = ON;
```

Single database file, path-resolved via `path_provider`. One
`sqflite_common_ffi` connection per isolate; the app isolate owns
writes, read isolates may open read-only clones for heavy scans if
profiling requires.

---

## 3. Table: `channels`

Every channel the local user is a member of (or was a member of and
has not yet tombstoned locally).

```sql
CREATE TABLE channels (
  channel_id               TEXT PRIMARY KEY,         -- UUIDv7, client- or server-generated
  kind                     TEXT NOT NULL,            -- 'one_to_one' | 'group'
  name                     TEXT,                     -- group only; NULL for one_to_one
  avatar_url               TEXT,
  owner_user_id            TEXT NOT NULL,            -- creator for groups; locally-stamped for one_to_one
  created_at               INTEGER NOT NULL,         -- server_timestamp on CHANNEL_CREATED fanout; local clock for fully-local
  last_activity_ms         INTEGER NOT NULL,         -- max(server_timestamp_ms) across messages in channel, or created_at
  last_message_id          TEXT,                     -- id of the most-recent non-tombstoned message (for chat-list preview)
  unread_count             INTEGER NOT NULL DEFAULT 0,
  last_read_message_id     TEXT,                     -- local user's read marker (see §9); NULL until first open
  tombstoned               INTEGER NOT NULL DEFAULT 0 -- 1 = channel deleted/left locally
);

CREATE INDEX idx_channels_last_activity
  ON channels(last_activity_ms DESC)
  WHERE tombstoned = 0;
```

**Counter-party for `one_to_one`.** For a one-to-one channel, the
other party's `user_id` is derivable from `channel_members`
(exactly one row with `user_id != local_user_id`). Denormalizing it
onto `channels` would save a join but would need maintenance on
channel-kind changes. Stay normalized; the join is cheap.

**`unread_count` maintenance.** Incremented on inbound
`TYPE_MESSAGE_CREATE` / `TYPE_MESSAGE_FORWARD` where
`author_user_id != local_user_id`. Reset to 0 (and
`last_read_message_id` advanced) when the user opens the channel —
see §9.

---

## 4. Table: `channel_members`

Membership rows for groups. One_to_one channels also populate this
table with the two members (local user + counterparty) for query
uniformity.

```sql
CREATE TABLE channel_members (
  channel_id   TEXT NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
  user_id      TEXT NOT NULL,
  role         TEXT NOT NULL,                -- 'owner' | 'admin' | 'member'
  joined_at    INTEGER NOT NULL,
  removed_at   INTEGER,                      -- NULL while active; set when member is removed
  PRIMARY KEY (channel_id, user_id)
);

CREATE INDEX idx_channel_members_active
  ON channel_members(channel_id)
  WHERE removed_at IS NULL;

CREATE INDEX idx_channel_members_user
  ON channel_members(user_id, channel_id)
  WHERE removed_at IS NULL;
```

Server is the source of truth (channel-ms). Updated in response to
`ServerEventPayload`s of type `CHANNEL_MEMBER_ADDED` /
`CHANNEL_MEMBER_REMOVED` (SYNC_PROTOCOL §10.2) or local REST writes
with optimistic update pending server ACK.

---

## 5. Table: `messages`

The heart of the local store. Holds every message the client knows
about — messages the user sent (in any state) and messages received
from fanout.

```sql
CREATE TABLE messages (
  message_id               TEXT PRIMARY KEY,     -- UUIDv7, client-generated by author
  channel_id               TEXT NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
  author_user_id           TEXT NOT NULL,        -- original author; never mutates

  body                     TEXT,                 -- current body; NULL if tombstoned
  content_type             TEXT,                 -- MIME-style; NULL if tombstoned
  reply_to_message_id      TEXT,                 -- NULL if not a reply
  attachments              BLOB,                 -- proto-encoded `repeated Attachment` (see v3-chat-payload.proto); NULL if none
  forward_source           BLOB,                 -- proto-encoded `ForwardSource`; NULL if not a forward

  client_timestamp_ms      INTEGER NOT NULL,     -- author's wall-clock at creation
  server_timestamp_ms      INTEGER,              -- NULL until ACK (local-authored) or always present (inbound)
  delivery_sequence        INTEGER,              -- NULL until ACK/fanout; server-stamped; per-channel monotonic

  message_state            TEXT NOT NULL,        -- see §5.1
  state_updated_at         INTEGER NOT NULL,

  is_edited                INTEGER NOT NULL DEFAULT 0,
  last_edit_ms             INTEGER,              -- server_timestamp of last MESSAGE_UPDATE applied

  tombstoned               INTEGER NOT NULL DEFAULT 0,
  tombstone_pending_until  INTEGER               -- 5s undo expiry; NULL outside the undo window
);

-- Primary read path: channel chat view, newest-first, excluding tombstones.
CREATE INDEX idx_messages_channel_order
  ON messages(channel_id, COALESCE(delivery_sequence, 9223372036854775807) DESC, client_timestamp_ms DESC)
  WHERE tombstoned = 0;

-- For the recipient-side §6a.4 enforcement queries (fast authorship lookup).
CREATE INDEX idx_messages_author
  ON messages(author_user_id, message_id);

-- For the 5s undo sweeper (finds pending tombstones to commit).
CREATE INDEX idx_messages_tombstone_pending
  ON messages(tombstone_pending_until)
  WHERE tombstone_pending_until IS NOT NULL;

-- For chat-list preview lookup.
CREATE INDEX idx_messages_channel_latest
  ON messages(channel_id, delivery_sequence DESC)
  WHERE tombstoned = 0 AND delivery_sequence IS NOT NULL;
```

### 5.1 `message_state` — the unified state machine

```
                    ┌───────────────────────────────────────────┐
                    │                                           │
                    ▼                                           │
  [local author]  pending ──dispatch──▶ sending ──ACK─▶ sent ──┼──▶ delivered ──▶ read
                     │                     │                   │      (v3.1)       (v3.1)
                     │                     │                   │
                     └──5s undo expires────┘                   │
                                           │                   │
                                           └──permanent rej─▶ rejected
                                                               │
                                                               │
  [inbound fanout]  (decode + §6a.4 gate) ──apply──▶ sent ─────┘
                                                               │
                                                               ├──user opens chat──▶ read (local)
```

Column values:

| Value | Meaning | Set by |
|---|---|---|
| `pending` | Local author typed/tapped the action; sitting in the 5s undo window OR queued but awaiting transport availability. Not yet on the wire. | Local author flow on initial insert. |
| `sending` | Dispatched on WS (frame written); awaiting server Ack. Visible in UI as "sending…" spinner. | Scheduler Flow A on dispatch. |
| `sent` | Server acked (local author) OR message arrived via fanout (inbound). For the local author this means the server has the op; for the recipient this means the message is in the local store. Single UI state: "delivered to the server." | Scheduler Flow B on `ACK_SUCCESS`; inbound dispatch path on fanout apply. |
| `delivered` | **v3.1 only.** Recipient's client confirmed receipt back to the sender. For the sender's view of their own locally-authored messages only; in groups, this is per-recipient (see §5.2). Not populated in v3.0. | v3.1 delivery-receipt wire (TBD). |
| `read` | Dual use: (a) v3.1 sender-side — recipient confirmed read-at-or-past this message (sender's view of their own messages, per-recipient in groups); (b) any version — local user opened the chat and scrolled past an inbound message. | (a) v3.1 read-receipt wire. (b) Local UI on channel-open. |
| `rejected` | Scheduler Flow B received `ACK_PERMANENT` for the outbound op. Projection is rolled back (body restored if was an edit, tombstone removed if was a delete). Row stays with `message_state='rejected'` so the UI can show a "failed to send" affordance and the user can retry. Retry creates a new op_id. | Scheduler Flow B. |

**v3.1 states are reserved in the enum now** but no code path
populates them in v3.0. Rendering code MAY display them (e.g., a
double-check icon for `delivered`) and the v3.1 upgrade will just
start flipping the column.

### 5.2 Why `delivered` / `read` are single-valued in v3.0

A group message has N recipients and therefore N delivery states.
A single enum column per-message cannot express "delivered to
Alice, not yet to Bob." v3.0 carries the column for forward-compat
but does not use it.

**v3.1 migration plan:** introduce a `message_recipient_state` table:

```sql
CREATE TABLE message_recipient_state (
  message_id   TEXT NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE,
  user_id      TEXT NOT NULL,
  state        TEXT NOT NULL,          -- 'delivered' | 'read'
  state_ms     INTEGER NOT NULL,
  PRIMARY KEY (message_id, user_id)
);
```

`messages.message_state` then represents the aggregated view for
the UI: "at least one recipient has `read`" → show `read`; else "at
least one has `delivered`" → show `delivered`; else `sent`. Exact
aggregation semantics are a v3.1 design decision.

### 5.3 Optimistic send flow (local author)

```
USER TAPS SEND:
  BEGIN TRANSACTION
    INSERT INTO messages (
      message_id,               -- client UUIDv7
      channel_id,
      author_user_id,           -- local_user_id
      body, content_type, ...
      client_timestamp_ms,
      message_state,            -- 'pending'
      state_updated_at
    )
    INSERT INTO outbound_ops (   -- see §8
      op_id, transport, kind, resource_id, resource_seq, payload, status, ...
    )
    UPDATE channels SET last_activity_ms = :now, last_message_id = :message_id
      WHERE channel_id = :channel_id
  COMMIT
  scheduler.tickSoon()

SCHEDULER FLOW A dispatches the outbound_op:
  BEGIN TRANSACTION
    UPDATE outbound_ops SET status='in_flight', dispatched_at=:now
    UPDATE messages SET message_state='sending', state_updated_at=:now WHERE message_id=:mid
  COMMIT
  WsTransport.send(envelope)

ON ACK_SUCCESS:
  BEGIN TRANSACTION
    DELETE FROM outbound_ops WHERE op_id = :op_id
    UPDATE messages
      SET message_state = 'sent',
          state_updated_at = :now,
          server_timestamp_ms = :ack.server_timestamp_ms,
          delivery_sequence = :ack.delivery_sequence
      WHERE message_id = :mid
  COMMIT

ON ACK_PERMANENT (rejected):
  BEGIN TRANSACTION
    UPDATE outbound_ops SET status='rejected', last_error=:reason
    UPDATE messages SET message_state='rejected', state_updated_at=:now WHERE message_id=:mid
  COMMIT
  surface to user via watchFailures() stream (SPIKE_B §10)
```

### 5.4 Inbound fanout flow

```
WS PUSH ENVELOPE ARRIVES:
  IF op_id already in op_id_seen for this channel: drop silently, return
  INSERT INTO op_id_seen (channel_id, op_id, seen_at) VALUES (...)

  inspect payload[0]:
    0x53: decode as ServerEventPayload, route to server-event handler
    otherwise: decode as ChatPayload, run §6a.4 gate

  For TYPE_MESSAGE_CREATE / TYPE_MESSAGE_FORWARD:
    BEGIN TRANSACTION
      INSERT INTO messages (
        message_id = payload.message_id,
        channel_id = envelope.channel_id,
        author_user_id = envelope.sender_user_id,
        body, content_type, attachments, forward_source = from payload,
        reply_to_message_id = payload.reply_to_message_id,
        client_timestamp_ms = envelope.client_timestamp_ms,
        server_timestamp_ms = envelope.server_timestamp_ms,
        delivery_sequence = envelope.delivery_sequence,
        message_state = 'sent',
        state_updated_at = :now
      )
      UPDATE channels
        SET last_activity_ms = :envelope.server_timestamp_ms,
            last_message_id = :payload.message_id,
            unread_count = unread_count + 1
        WHERE channel_id = :envelope.channel_id
    COMMIT

  For TYPE_MESSAGE_UPDATE:
    gate: SELECT author_user_id, tombstoned FROM messages WHERE message_id = :target
    if row missing OR author != sender OR tombstoned: silently drop (already logged in op_id_seen)
    else:
      UPDATE messages
        SET body = payload.body,
            content_type = payload.content_type,
            attachments = payload.attachments,
            is_edited = 1,
            last_edit_ms = envelope.server_timestamp_ms,
            state_updated_at = :now
        WHERE message_id = :target

  For TYPE_MESSAGE_DELETE:
    gate: SELECT author_user_id FROM messages WHERE message_id = :target
    if row missing OR author != sender: silently drop
    else:
      UPDATE messages
        SET tombstoned = 1,
            body = NULL, content_type = NULL, attachments = NULL,
            state_updated_at = :now
        WHERE message_id = :target

  For TYPE_REACTION_ADD:
    gate: SELECT 1 FROM messages WHERE message_id = :target AND tombstoned = 0
    if missing: silently drop
    else:
      INSERT OR IGNORE INTO reactions (message_id, user_id, emoji, added_at) VALUES (...)

  For TYPE_REACTION_REMOVE:
    gate: SELECT 1 FROM messages WHERE message_id = :target
    if missing: silently drop  (message-gone makes the unreact a no-op)
    DELETE FROM reactions WHERE message_id = :target AND user_id = :sender AND emoji = :emoji
```

All inbound writes are in a single SQLite transaction with the
`op_id_seen` INSERT. If the transaction fails mid-way (disk full,
corruption), the `op_id_seen` entry is also rolled back and the
server's next re-fanout will be reconsidered.

---

## 6. Table: `reactions`

```sql
CREATE TABLE reactions (
  message_id   TEXT NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE,
  user_id      TEXT NOT NULL,
  emoji        TEXT NOT NULL,
  added_at     INTEGER NOT NULL,
  PRIMARY KEY (message_id, user_id, emoji)
);

CREATE INDEX idx_reactions_message ON reactions(message_id);
```

Idempotency is enforced by the primary key: a duplicate
`TYPE_REACTION_ADD` inserts via `INSERT OR IGNORE` and is a no-op.
Removes are idempotent by `DELETE WHERE …` matching zero rows.

---

## 7. Table: `contacts`

Cached profiles of other users. One_to_one counterparties AND group
co-members AND phone-discovered contacts all live here, keyed by
`user_id`. Populated from contact lookup (AUTH_CONTRACT §7.2),
`GET /v3.0/users/<user_id>` (§7.5), and inbound
`ServerEventPayload` of type `PROFILE_EDITED` / `USERNAME_CHANGED`.

```sql
CREATE TABLE contacts (
  user_id              TEXT PRIMARY KEY,
  username             TEXT,                -- nullable per AUTH_CONTRACT §2.4
  display_name         TEXT,
  avatar_url           TEXT,
  status_text          TEXT,
  phone_hash           TEXT,                -- SHA-256(E.164); only set for contacts resolved via contact lookup
  contact_book_name    TEXT,                -- local display: name in the user's phone contact book (if any)
  last_refreshed_ms    INTEGER NOT NULL     -- server-profile TTL cache (AUTH_CONTRACT §7.4: 7 days)
);

CREATE INDEX idx_contacts_phone_hash
  ON contacts(phone_hash)
  WHERE phone_hash IS NOT NULL;

-- For username-based lookup (e.g., mentions in v3.1; not v3.0).
CREATE INDEX idx_contacts_username
  ON contacts(username)
  WHERE username IS NOT NULL;
```

**Display-name resolution** per AUTH_CONTRACT §2.4:
`contact_book_name → username → phone-fragment → empty`. The
resolution is client-side; this table provides the data.

**The local user is NOT in `contacts`.** Their profile lives in
session state alongside `user_id` and `accesskey`.

**`contact_book_name`** is populated from the user's device contact
book (Android ContactsContract). Refreshed on permission grant and
periodically. Takes precedence over `username` for display.

---

## 8. Table: `outbound_ops`

Unchanged from SPIKE_B_SYNC §3 (post-rename and transport-
discriminator additions). Repeated here for completeness.

```sql
CREATE TABLE outbound_ops (
  op_id              TEXT PRIMARY KEY,
  transport          TEXT NOT NULL,           -- 'ws' | 'rest'
  kind               TEXT NOT NULL,
  rest_method        TEXT,
  rest_path          TEXT,
  resource_id        TEXT NOT NULL,
  resource_seq       INTEGER NOT NULL,
  payload            BLOB NOT NULL,
  status             TEXT NOT NULL,           -- pending | in_flight | retrying | rejected | dead_letter | cascaded_rejection
  attempts           INTEGER NOT NULL DEFAULT 0,
  next_retry_at      INTEGER NOT NULL,
  dispatched_at      INTEGER,
  last_error         TEXT,
  acknowledged_at    INTEGER,
  created_at         INTEGER NOT NULL,

  -- Projection linkage for UI coordination:
  target_message_id  TEXT,                    -- set for chat_payload ops that produce/mutate a message row
  target_channel_id  TEXT                     -- set for REST channel ops that produce/mutate a channel row
);

CREATE INDEX idx_outbound_ops_pending
  ON outbound_ops(next_retry_at)
  WHERE status IN ('pending', 'retrying');

CREATE INDEX idx_outbound_ops_inflight
  ON outbound_ops(dispatched_at)
  WHERE status = 'in_flight';

CREATE INDEX idx_outbound_ops_resource
  ON outbound_ops(resource_id, resource_seq);

CREATE INDEX idx_outbound_ops_target_message
  ON outbound_ops(target_message_id)
  WHERE target_message_id IS NOT NULL;
```

### 8.1 UI join for in-flight state

The UI does not need to read `outbound_ops` directly. The
`messages.message_state` column (§5.1) captures every state the UI
cares about. When an op's dispatcher state changes, the scheduler
writes through to `messages.message_state` in the same transaction
as the outbound_ops status change. UI watches `messages` only.

For non-message ops (channel CRUD, profile edits), `channels` and
`contacts` similarly carry `state_updated_at` and any UI-visible
pending-edit markers. v3.0 does not surface these prominently — a
pending channel-create just delays the channel row's visibility
until ACK.

---

## 9. Table: `op_id_seen`

Recipient-side dedup per channel, per SYNC_PROTOCOL §7.2.

```sql
CREATE TABLE op_id_seen (
  channel_id   TEXT NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
  op_id        TEXT NOT NULL,
  seen_at      INTEGER NOT NULL,
  PRIMARY KEY (channel_id, op_id)
);

CREATE INDEX idx_op_id_seen_age
  ON op_id_seen(channel_id, seen_at);
```

**Bounded per channel** — oldest entries pruned when the channel
exceeds 5,000 rows OR entries exceed 30 days, whichever hits first
(SYNC_PROTOCOL §7.2). Pruning runs as part of the compaction job
(§11).

**Recording on drop.** When §6a.4 gate rejects an inbound op, the
`op_id_seen` row is still inserted so a re-fanout of the same op
does not re-evaluate.

---

## 10. Read marker and `unread_count`

v3.0 read state is **local-only** (no delivery/read receipts on the
wire — deferred to v3.1).

**On channel open:**
```
UPDATE channels
  SET unread_count = 0,
      last_read_message_id = (
        SELECT message_id FROM messages
        WHERE channel_id = :cid AND tombstoned = 0
        ORDER BY delivery_sequence DESC LIMIT 1
      )
  WHERE channel_id = :cid;
```

**On inbound fanout** (§5.4):
```
UPDATE channels SET unread_count = unread_count + 1 ...
```
Only increments if the author is not the local user (local-author
messages don't count as "unread").

**Rendering "unread" per message:** a message is unread if
`delivery_sequence > (SELECT delivery_sequence FROM messages WHERE
message_id = channels.last_read_message_id)`. Cheap given the
per-channel index.

**v3.1 extension:** when read-receipt wire is added, the local read-
marker advance ALSO triggers an outbound read-receipt op targeting
the relevant recipient(s), which flips their `message_state` to
`read` per §5.2.

---

## 11. Table: `snapshots`

Compaction marker for pruning old data. Per SPIKE_A follow-up #1.

```sql
CREATE TABLE snapshots (
  snapshot_id                    TEXT PRIMARY KEY,
  taken_at                       INTEGER NOT NULL,
  max_delivery_sequence          INTEGER,                  -- up to which cross-channel delivery the snapshot is current
  schema_version                 INTEGER NOT NULL
);
```

**Retention policy (v3.0 default, tunable):** delete `messages` rows
where:
- `tombstoned = 1` AND `state_updated_at < now - 7 days`, OR
- `delivery_sequence < latest_snapshot.max_delivery_sequence - <retention_window>` where retention is 365 days by default, OR
- `message_state = 'rejected'` AND `acknowledged_at < now - 30 days`.

Plus prune `op_id_seen` per §9 bounds, plus prune completed
`outbound_ops` (SPIKE_B §11).

Runs on app launch + every 15 minutes of activity, bounded-time
(early-exit if > 500ms).

`VACUUM` runs on a separate schedule — weekly, or when freelist
pages exceed some threshold. Not in the hot path.

---

## 12. Schema migrations

**v3.0 strategy: `ALTER TABLE` for additive changes, full resync
for incompatible changes.**

- Adding a column → `ALTER TABLE ... ADD COLUMN ... DEFAULT ...`,
  bump `snapshots.schema_version`.
- Adding a table → `CREATE TABLE ...`, bump schema version.
- Renaming a column → create new column, copy data, drop old, bump
  schema version. Within one transaction.
- Incompatible shape change (e.g., reshaping `messages` to support
  v3.1 multi-device) → nuke the projections and do a **full
  network resync from the server's state**. Since chat-server is a
  relay with no history, "full resync" means: re-fetch channel
  memberships, profile cache, contacts, push-topic state — all the
  REST-queryable state. Message history cannot be resynced; users
  lose it. This is the same failure mode as a reinstall
  (V3_ARCHITECTURE release model).

**The event-replay migration path is retired** — it was a selling
point for the original event-sourced framing, but with inbound no
longer in the log, event-replay can only rebuild the outbound view,
which doesn't help on a projection shape change. Full network
resync is the honest answer.

**v3.1 adds a cold-archive resync path** (see SYNC_PROTOCOL §18)
which will enable lossless migration for any user on a good
network. v3.0 ships with the lossy-on-incompatible-migration caveat.

---

## 13. Query cookbook

Reference queries for common UI paths. Use these as the starting
point for reactive streams.

### 13.1 Chat list

```sql
SELECT c.channel_id, c.kind, c.name, c.avatar_url,
       c.last_activity_ms, c.unread_count,
       m.body AS last_message_preview,
       m.author_user_id AS last_message_author,
       m.tombstoned AS last_message_tombstoned
FROM channels c
LEFT JOIN messages m ON m.message_id = c.last_message_id
WHERE c.tombstoned = 0
ORDER BY c.last_activity_ms DESC
LIMIT 100;
```

Hot path. Uses `idx_channels_last_activity` for the ordering.
LEFT JOIN is O(1) per row via `messages` PK.

### 13.2 Channel messages view

```sql
SELECT m.message_id, m.author_user_id, m.body, m.content_type,
       m.attachments, m.forward_source, m.reply_to_message_id,
       m.server_timestamp_ms, m.delivery_sequence,
       m.message_state, m.is_edited, m.last_edit_ms, m.tombstoned
FROM messages m
WHERE m.channel_id = :cid AND m.tombstoned = 0
ORDER BY COALESCE(m.delivery_sequence, 9223372036854775807) DESC,
         m.client_timestamp_ms DESC
LIMIT :page_size OFFSET :page_offset;
```

Local-pending messages (null `delivery_sequence`) sort to the top
(newest-visible), matching WhatsApp/Signal UX.

### 13.3 Reactions for a message

```sql
SELECT user_id, emoji, added_at
FROM reactions
WHERE message_id = :mid
ORDER BY added_at ASC;
```

The app layer groups by emoji and counts.

### 13.4 Recipient-side authorship check (the §6a.4 gate)

```sql
SELECT author_user_id, tombstoned
FROM messages
WHERE message_id = :target_message_id;
```

Single-row lookup via PK. The §6a.4 enforcement decision is
whether `author_user_id == envelope.sender_user_id` and
`tombstoned = 0`.

### 13.5 Display name for a user_id

```sql
SELECT COALESCE(contact_book_name, username, NULL) AS display_primary,
       contacts.phone_hash IS NOT NULL AS has_phone_link,
       username, contact_book_name
FROM contacts
WHERE user_id = :uid;
```

The app layer implements the §2.4 fallback (contact-book name →
username → phone fragment → empty). If the row is missing
entirely, the app shows empty/placeholder and schedules a `GET
/v3.0/users/<uid>` fetch.

---

## 14. What this schema does NOT include

- **Message search** — deferred. FTS5 can be added later with an
  `ALTER TABLE ... ADD COLUMN ... AS ...` virtual column or a
  separate FTS table.
- **Draft messages** — each chat's typed-but-not-sent text. Simple
  `drafts(channel_id, body, updated_at)` table can be added in
  scaffold without migration pain.
- **Media cache state** — where an attachment is in the download/
  upload pipeline. Separate table recommended; not in this schema.
- **Presence / typing** — v3.1+ per V3_ARCHITECTURE out-of-scope.
- **Multi-device sessions** — v3.1+.
- **End-to-end encryption key state** — v4+.

---

## 15. Open items for scaffold

1. **Media attachment storage.** Attachments are proto-encoded in
   `messages.attachments` as URLs + metadata. The actual bytes live
   on disk in a media-cache directory, keyed by
   `sha256(attachment_url)`. That cache is out of SQLite scope.
2. **Migration test harness.** Every `ALTER TABLE` migration needs
   a test that (a) loads a pre-migration DB fixture, (b) runs the
   migration, (c) verifies the queries in §13 still work.
3. **Benchmark against this exact schema.** SPIKE_A_RESULTS used a
   simpler shape; the `WHERE tombstoned = 0` partial indexes and
   the `COALESCE(delivery_sequence, …)` ordering need to be
   re-measured on real-device before launch gate.
4. **Outbound_ops payload encoding.** For WS `chat_payload` ops,
   `outbound_ops.payload` is the `bytes payload` that goes into
   the `Envelope` — already the encoded `ChatPayload` proto. For
   REST ops, it's JSON. Scaffold picks whether to share serializers
   or keep them separate.
