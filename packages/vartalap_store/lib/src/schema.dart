/// v3.0 SQLite schema — SPIKE_A_SCHEMA.md §2–§11.
///
/// Projections are authoritative. `outbound_ops` holds unsynced local
/// actions only. `op_id_seen` is recipient-side inbound dedup.
library vartalap_store.schema;

const int schemaVersion = 1;

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
    tombstoned              INTEGER NOT NULL DEFAULT 0
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
    server_timestamp_ms     INTEGER,
    delivery_sequence       INTEGER,

    message_state           TEXT NOT NULL,
    state_updated_at        INTEGER NOT NULL,

    is_edited               INTEGER NOT NULL DEFAULT 0,
    last_edit_ms            INTEGER,

    tombstoned              INTEGER NOT NULL DEFAULT 0,
    tombstone_pending_until INTEGER
  )
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_messages_channel_order
    ON messages(channel_id, COALESCE(delivery_sequence, 9223372036854775807) DESC, client_timestamp_ms DESC)
    WHERE tombstoned = 0
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
  CREATE INDEX IF NOT EXISTS idx_messages_channel_latest
    ON messages(channel_id, delivery_sequence DESC)
    WHERE tombstoned = 0 AND delivery_sequence IS NOT NULL
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
    resource_seq       INTEGER NOT NULL,
    payload            BLOB NOT NULL,
    status             TEXT NOT NULL,
    attempts           INTEGER NOT NULL DEFAULT 0,
    next_retry_at      INTEGER NOT NULL,
    dispatched_at      INTEGER,
    last_error         TEXT,
    acknowledged_at    INTEGER,
    created_at         INTEGER NOT NULL,
    target_message_id  TEXT,
    target_channel_id  TEXT
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
    ON outbound_ops(resource_id, resource_seq)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_outbound_ops_target_message
    ON outbound_ops(target_message_id)
    WHERE target_message_id IS NOT NULL
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

  // §11 snapshots
  '''
  CREATE TABLE IF NOT EXISTS snapshots (
    snapshot_id              TEXT PRIMARY KEY,
    taken_at                 INTEGER NOT NULL,
    max_delivery_sequence    INTEGER,
    schema_version           INTEGER NOT NULL
  )
  ''',
];
