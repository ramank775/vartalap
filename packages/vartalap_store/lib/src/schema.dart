/// v3.0 SQLite schema — SPIKE_A_SCHEMA.md §2–§11.
///
/// Projections are authoritative. `outbound_ops` holds unsynced local
/// actions only. `op_id_seen` is recipient-side inbound dedup.
library vartalap_store.schema;

const int schemaVersion = 5;

const List<String> pragmas = [
  'PRAGMA journal_mode = WAL',
  'PRAGMA synchronous = NORMAL',
  'PRAGMA wal_autocheckpoint = 1000',
  'PRAGMA foreign_keys = ON',
];

const List<String> ddl = [
  // §3 channels
  '''
  CREATE TABLE IF NOT EXISTS channels (
    channel_id              TEXT PRIMARY KEY,
    kind                    TEXT NOT NULL,
    name                    TEXT,
    avatar_url              TEXT,
    owner_user_id           TEXT NOT NULL,
    created_at              INTEGER NOT NULL,
    last_activity_ms        INTEGER NOT NULL,
    last_message_id         TEXT,
    unread_count            INTEGER NOT NULL DEFAULT 0,
    last_read_message_id    TEXT,
    tombstoned              INTEGER NOT NULL DEFAULT 0,

    -- Local-only chat metadata (V3_ARCHITECTURE decision 3 offline
    -- matrix: archive / mute / pin never leave the device). Kept as
    -- columns on `channels` rather than a `channel_settings` side
    -- table — one row per channel either way, and the chat-list query
    -- reads them without a join.
    pinned                  INTEGER NOT NULL DEFAULT 0,
    muted_until_ms          INTEGER,

    -- "Delete chat" tombstone. Local-only and distinct from
    -- `tombstoned` (a server-side ChannelDeleted): membership and the
    -- Groups listing are untouched, and the next message clears it.
    deleted_locally         INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_channels_last_activity
    ON channels(last_activity_ms DESC)
    WHERE tombstoned = 0
  ''',

  // §4 channel_members
  '''
  CREATE TABLE IF NOT EXISTS channel_members (
    channel_id   TEXT NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    user_id      TEXT NOT NULL,
    role         TEXT NOT NULL,
    joined_at    INTEGER NOT NULL,
    removed_at   INTEGER,
    PRIMARY KEY (channel_id, user_id)
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_channel_members_active
    ON channel_members(channel_id)
    WHERE removed_at IS NULL
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_channel_members_user
    ON channel_members(user_id, channel_id)
    WHERE removed_at IS NULL
  ''',

  // §5 messages
  '''
  CREATE TABLE IF NOT EXISTS messages (
    message_id              TEXT PRIMARY KEY,
    channel_id              TEXT NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    author_user_id          TEXT NOT NULL,

    body                    TEXT,
    content_type            TEXT,
    reply_to_message_id     TEXT,
    attachments             BLOB,
    forward_source          BLOB,

    client_timestamp_ms     INTEGER NOT NULL,
    -- SYNC_PROTOCOL §6: the channel is ordered by (server_timestamp_ms,
    -- message_id). NULL until our own op is ACKed.
    server_timestamp_ms     INTEGER,

    message_state           TEXT NOT NULL,
    state_updated_at        INTEGER NOT NULL,

    is_edited               INTEGER NOT NULL DEFAULT 0,
    last_edit_ms            INTEGER,

    tombstoned              INTEGER NOT NULL DEFAULT 0,
    tombstone_pending_until INTEGER,

    -- Pre-edit body, snapshotted while a MESSAGE_UPDATE op is in
    -- flight so a permanent reject can restore it (V3_ARCHITECTURE
    -- decision 11). Cleared on ACK.
    rollback_body           TEXT,

    -- Starred messages: when the user starred it, NULL when not.
    -- Local-only, like pin and mute; never leaves the device.
    starred_at              INTEGER
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_messages_channel_order
    ON messages(channel_id, COALESCE(server_timestamp_ms, 9223372036854775807) DESC,
                (CASE WHEN server_timestamp_ms IS NULL THEN client_timestamp_ms END) DESC,
                message_id DESC)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_messages_author
    ON messages(author_user_id, message_id)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_messages_tombstone_pending
    ON messages(tombstone_pending_until)
    WHERE tombstone_pending_until IS NOT NULL
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_messages_starred
    ON messages(starred_at DESC)
    WHERE starred_at IS NOT NULL
  ''',

  // §6 reactions
  '''
  CREATE TABLE IF NOT EXISTS reactions (
    message_id  TEXT NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE,
    user_id     TEXT NOT NULL,
    emoji       TEXT NOT NULL,
    added_at    INTEGER NOT NULL,
    PRIMARY KEY (message_id, user_id, emoji)
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_reactions_message ON reactions(message_id)
  ''',

  // §7 contacts
  '''
  CREATE TABLE IF NOT EXISTS contacts (
    user_id             TEXT PRIMARY KEY,
    username            TEXT,
    display_name        TEXT,
    avatar_url          TEXT,
    status_text         TEXT,
    phone_hash          TEXT,
    contact_book_name   TEXT,
    last_refreshed_ms   INTEGER NOT NULL
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_contacts_phone_hash
    ON contacts(phone_hash)
    WHERE phone_hash IS NOT NULL
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_contacts_username
    ON contacts(username)
    WHERE username IS NOT NULL
  ''',

  // §8 outbound_ops
  '''
  CREATE TABLE IF NOT EXISTS outbound_ops (
    op_id              TEXT PRIMARY KEY,
    transport          TEXT NOT NULL,
    kind               TEXT NOT NULL,
    rest_method        TEXT,
    rest_path          TEXT,
    resource_id        TEXT NOT NULL,
    payload            BLOB NOT NULL,
    status             TEXT NOT NULL,
    attempts           INTEGER NOT NULL DEFAULT 0,
    next_retry_at      INTEGER NOT NULL,
    dispatched_at      INTEGER,
    last_error         TEXT,
    acknowledged_at    INTEGER,
    created_at         INTEGER NOT NULL,
    target_message_id  TEXT,
    target_channel_id  TEXT,
    sealed_payload     BLOB
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_outbound_ops_pending
    ON outbound_ops(next_retry_at)
    WHERE status IN ('pending', 'retrying')
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_outbound_ops_inflight
    ON outbound_ops(dispatched_at)
    WHERE status = 'in_flight'
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_outbound_ops_resource
    ON outbound_ops(resource_id)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_outbound_ops_target_message
    ON outbound_ops(target_message_id)
    WHERE target_message_id IS NOT NULL
  ''',

  // SYNC_PROTOCOL §6b — inbound ops that target a message we don't
  // hold yet (an edit, delete or reaction that beat its create here).
  // Applied, in server order, the moment the message lands; bounded by
  // ChatStore. Columns are the decoded op, since the store doesn't
  // parse ChatPayload.
  '''
  CREATE TABLE IF NOT EXISTS pending_ops (
    op_id                TEXT PRIMARY KEY,
    channel_id           TEXT NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    target_message_id    TEXT NOT NULL,
    kind                 TEXT NOT NULL,
    sender_user_id       TEXT NOT NULL,
    server_timestamp_ms  INTEGER NOT NULL,
    body                 TEXT,
    content_type         TEXT,
    attachments          BLOB,
    emoji                TEXT,
    received_at          INTEGER NOT NULL
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_pending_ops_target
    ON pending_ops(target_message_id)
  ''',

  // §9 op_id_seen
  '''
  CREATE TABLE IF NOT EXISTS op_id_seen (
    channel_id  TEXT NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    op_id       TEXT NOT NULL,
    seen_at     INTEGER NOT NULL,
    PRIMARY KEY (channel_id, op_id)
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_op_id_seen_age
    ON op_id_seen(channel_id, seen_at)
  ''',

  // SYNC_PROTOCOL §10.6 — the pull pointer: the newest
  // server_timestamp_ms among the pushes this account has handled, the
  // next pull's `since`. One row; none reads as 0. v3 adds it through
  // [ddl] alone, which onUpgrade re-runs.
  '''
  CREATE TABLE IF NOT EXISTS sync_state (
    id                INTEGER PRIMARY KEY CHECK (id = 1),
    newest_handled_ms INTEGER NOT NULL
  )
  ''',
];

/// v1 → v2: the server stopped sequencing (SYNC_PROTOCOL §6), so the
/// client-assigned `resource_seq` and the server-stamped
/// `delivery_sequence` go, and so does the never-used `snapshots`
/// table. Run before [ddl], which then creates the new indexes.
const List<String> migrateV1ToV2 = [
  'DROP TABLE IF EXISTS resource_seq',
  'DROP TABLE IF EXISTS snapshots',
  'DROP INDEX IF EXISTS idx_outbound_ops_resource',
  'ALTER TABLE outbound_ops DROP COLUMN resource_seq',
  'DROP INDEX IF EXISTS idx_messages_channel_order',
  'DROP INDEX IF EXISTS idx_messages_channel_latest',
  'ALTER TABLE messages DROP COLUMN delivery_sequence',
];

/// v3 → v4: `messages.starred_at` (Starred messages). Run before [ddl],
/// which then creates its index.
const List<String> migrateV3ToV4 = [
  'ALTER TABLE messages ADD COLUMN starred_at INTEGER',
];

/// v4 → v5: `outbound_ops.sealed_payload`, the end-to-end encrypted bytes
/// of a WS op (decision 188), kept so a retry resends the same ciphertext.
const List<String> migrateV4ToV5 = [
  'ALTER TABLE outbound_ops ADD COLUMN sealed_payload BLOB',
];
