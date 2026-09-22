import 'dart:io';

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
      'snapshots',
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
