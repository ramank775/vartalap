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
    // WAL pragma applied.
    final journal = await store.db.rawQuery('PRAGMA journal_mode');
    // in-memory DBs report 'memory'; a file DB reports 'wal'. Either is
    // fine here — we're checking the pragma call didn't blow up.
    expect(journal.single.values.first, isNotNull);

    await store.close();
  });
}
