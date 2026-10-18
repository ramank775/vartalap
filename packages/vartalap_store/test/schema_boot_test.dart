import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';

void main() {
  test('schema boots on an in-memory sqlite db', () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    // Every expected table must be addressable.
    for (final tbl in [
      'channels',
      'channel_members',
      'messages',
      'reactions',
      'contacts',
      'outbound_ops',
      'op_id_seen',
      'pending_ops',
    ]) {
      final count = await store.db.rawQuery('SELECT COUNT(*) c FROM $tbl');
      expect(count.single['c'], 0, reason: tbl);
    }
    // in-memory DBs can only report 'memory'; the real WAL assertion is
    // the file-backed test below.
    final journal = await store.db.rawQuery('PRAGMA journal_mode');
    expect(journal.single.values.first, 'memory');

    await store.close();
  });

  // Every other test in the tree opens `:memory:`, which silently
  // ignores `PRAGMA journal_mode = WAL`. This is the one store that
  // touches the disk, purely so the WAL pragma has an assertion behind
  // it — the golden-path harness used to provide that incidentally by
  // running on a temp file.
  test('the WAL pragma takes on a file-backed db', () async {
    final dir = await Directory.systemTemp.createTemp('vartalap_wal');
    try {
      final store = await ChatStore.open(path: '${dir.path}/wal_probe.db');
      final journal = await store.db.rawQuery('PRAGMA journal_mode');
      expect(journal.single.values.first, 'wal');
      await store.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('a v1 database migrates to v2 and keeps its rows', () async {
    final dir = await Directory.systemTemp.createTemp('vartalap_v1');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v1.db';
    sqfliteFfiInit();
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          for (final stmt in _v1Ddl) {
            await db.execute(stmt);
          }
        },
      ),
    );
    await v1.insert('channels', {
      'channel_id': 'g-1',
      'kind': 'group',
      'owner_user_id': 'u-1',
      'created_at': 1,
      'last_activity_ms': 1,
    });
    await v1.insert('messages', {
      'message_id': 'm-1',
      'channel_id': 'g-1',
      'author_user_id': 'u-2',
      'body': 'kept',
      'client_timestamp_ms': 490,
      'server_timestamp_ms': 500,
      'delivery_sequence': 7,
      'message_state': 'sent',
      'state_updated_at': 500,
    });
    await v1.insert('outbound_ops', {
      'op_id': 'op-1',
      'transport': 'ws',
      'kind': 'chat_payload',
      'resource_id': 'g-1',
      'resource_seq': 3,
      'payload': Uint8List.fromList([1]),
      'status': 'pending',
      'next_retry_at': 0,
      'created_at': 1,
    });
    await v1.insert('resource_seq', {'resource_id': 'g-1', 'next_seq': 4});
    await v1.close();

    final store = await ChatStore.open(path: path);
    addTearDown(store.close);
    Future<List<Object?>> columns(String table) async =>
        (await store.db.rawQuery('PRAGMA table_info($table)'))
            .map((r) => r['name'])
            .toList();
    expect(await columns('messages'), isNot(contains('delivery_sequence')));
    expect(await columns('outbound_ops'), isNot(contains('resource_seq')));
    final tables = (await store.db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name']);
    expect(tables, isNot(contains('resource_seq')));
    expect(tables, isNot(contains('snapshots')));
    expect(tables, containsAll(['reactions', 'pending_ops', 'sync_state']),
        reason: 'the current DDL runs after the migration');

    final msgs = await store.fetchChannelMessages('g-1');
    expect(msgs.single.body, 'kept');
    expect(msgs.single.serverTimestampMs, 500);
    expect((await store.selectDispatchable(now: 1)).single.opId, 'op-1',
        reason: 'a queued op survives the migration and still dispatches');
  });

  test('the sync pointer starts where it is first put, never moves back, '
      'and lives with the database file', () async {
    final dir = await Directory.systemTemp.createTemp('vartalap_pointer');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/account.db';
    var store = await ChatStore.open(path: path);
    expect(await store.syncPointer(), 0);
    await store.initSyncPointer(30);
    expect(await store.syncPointer(), 30);
    await store.setSyncPointer(42);
    await store.setSyncPointer(7);
    expect(await store.syncPointer(), 42, reason: 'a late, smaller write');
    await store.close();

    store = await ChatStore.open(path: path);
    await store.initSyncPointer(99);
    expect(await store.syncPointer(), 42,
        reason: 'logout, then login: the stored pointer is kept');
    await store.close();
  });

  test('two in-memory stores do not share a database', () async {
    final a = await ChatStore.open(path: inMemoryDatabasePath);
    final b = await ChatStore.open(path: inMemoryDatabasePath);
    await a.insertChannel(
      channelId: 'c-only-in-a',
      kind: 'one_to_one',
      ownerUserId: 'u-1',
      createdAt: 1,
    );
    expect(await b.db.query('channels'), isEmpty,
        reason: 'sqflite caches open helpers by path, so without '
            'singleInstance:false both opens hand back one Database and '
            'every test in a file leaks into the next.');
    await a.close();
    expect(b.db.isOpen, isTrue,
        reason: 'closing one in-memory store must not close the other.');
    await b.close();
  });

  test('op_id_seen is not recorded for a channel we no longer hold',
      () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    // No channels row: a late fanout for a group we already left.
    await store.markOpIdSeen('c-gone', 'op-1', 42);
    expect(await store.hasSeenOpId('c-gone', 'op-1'), isFalse);

    await store.insertChannel(
      channelId: 'c-here',
      kind: 'group',
      ownerUserId: 'u-1',
      createdAt: 1,
    );
    await store.markOpIdSeen('c-here', 'op-2', 42);
    expect(await store.hasSeenOpId('c-here', 'op-2'), isTrue);
    // Idempotent — a re-fanout racing the hasSeenOpId probe.
    await store.markOpIdSeen('c-here', 'op-2', 99);

    await store.close();
  });
}

/// The v1 shape of the tables the v2 migration rewrites.
const _v1Ddl = [
  '''
  CREATE TABLE channels (
    channel_id TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT,
    avatar_url TEXT, owner_user_id TEXT NOT NULL,
    created_at INTEGER NOT NULL, last_activity_ms INTEGER NOT NULL,
    last_message_id TEXT, unread_count INTEGER NOT NULL DEFAULT 0,
    last_read_message_id TEXT, tombstoned INTEGER NOT NULL DEFAULT 0,
    pinned INTEGER NOT NULL DEFAULT 0, muted_until_ms INTEGER,
    deleted_locally INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE messages (
    message_id TEXT PRIMARY KEY,
    channel_id TEXT NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    author_user_id TEXT NOT NULL, body TEXT, content_type TEXT,
    reply_to_message_id TEXT, attachments BLOB, forward_source BLOB,
    client_timestamp_ms INTEGER NOT NULL, server_timestamp_ms INTEGER,
    delivery_sequence INTEGER,
    message_state TEXT NOT NULL, state_updated_at INTEGER NOT NULL,
    is_edited INTEGER NOT NULL DEFAULT 0, last_edit_ms INTEGER,
    tombstoned INTEGER NOT NULL DEFAULT 0, tombstone_pending_until INTEGER,
    rollback_body TEXT
  )
  ''',
  '''
  CREATE INDEX idx_messages_channel_order ON messages(channel_id,
    COALESCE(delivery_sequence, 9223372036854775807) DESC,
    client_timestamp_ms DESC)
  ''',
  '''
  CREATE INDEX idx_messages_channel_latest
    ON messages(channel_id, delivery_sequence DESC)
    WHERE tombstoned = 0 AND delivery_sequence IS NOT NULL
  ''',
  '''
  CREATE TABLE outbound_ops (
    op_id TEXT PRIMARY KEY, transport TEXT NOT NULL, kind TEXT NOT NULL,
    rest_method TEXT, rest_path TEXT, resource_id TEXT NOT NULL,
    resource_seq INTEGER NOT NULL, payload BLOB NOT NULL,
    status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
    next_retry_at INTEGER NOT NULL, dispatched_at INTEGER,
    last_error TEXT, acknowledged_at INTEGER, created_at INTEGER NOT NULL,
    target_message_id TEXT, target_channel_id TEXT
  )
  ''',
  '''
  CREATE INDEX idx_outbound_ops_resource
    ON outbound_ops(resource_id, resource_seq)
  ''',
  '''
  CREATE TABLE resource_seq (
    resource_id TEXT PRIMARY KEY, next_seq INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE snapshots (
    snapshot_id TEXT PRIMARY KEY, taken_at INTEGER NOT NULL,
    max_delivery_sequence INTEGER, schema_version INTEGER NOT NULL
  )
  ''',
];
