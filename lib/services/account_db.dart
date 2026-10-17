/// One local database per account (AUTH_CONTRACT §8.4): each user_id
/// gets its own SQLite file, kept across logout so the account finds
/// its history again on the next sign-in, and deleted with the account.
library vartalap.services.account_db;

import 'dart:io';

/// A database file and the companions SQLite may keep next to it.
const _siblings = ['', '-wal', '-shm', '-journal'];

/// `vartalap_v3_<user_id>.db` in [dir]. Server user_ids are hex; anything
/// else is replaced so the id can never step outside [dir].
String accountDbPath(String dir, String userId) =>
    '$dir/vartalap_v3_${userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.db';

/// Builds before per-account files kept one `vartalap_v3.db`, wiped at
/// logout, so whatever it holds belongs to the session restored at boot:
/// it becomes [userId]'s file. With no one signed in, that logout would
/// have emptied it, so it is deleted.
Future<void> migrateLegacyDb(String dir, String? userId) async {
  for (final s in _siblings) {
    final legacy = File('$dir/vartalap_v3.db$s');
    try {
      if (userId == null) {
        await legacy.delete();
      } else {
        await legacy.rename('${accountDbPath(dir, userId)}$s');
      }
    } on PathNotFoundException {
      // Nothing to move, or a push wake's engine moved it first.
    }
  }
}

/// Account deleted (AUTH_CONTRACT §8.2): its database goes with it.
/// The store must be closed first.
Future<void> deleteAccountDb(String dir, String userId) async {
  for (final s in _siblings) {
    try {
      await File('${accountDbPath(dir, userId)}$s').delete();
    } on PathNotFoundException {
      // SQLite never wrote this one.
    }
  }
}
