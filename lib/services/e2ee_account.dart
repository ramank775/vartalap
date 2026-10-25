import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'e2ee.dart';

/// The per-account wrapping key of [E2eeRecordStore], kept in secure
/// storage: created with the first record, checked on every open,
/// removed with the account.

String _keyName(String accountId) => 'v3.e2ee.wrappingKey.$accountId';
const _android = AndroidOptions(resetOnError: false);
const _ios =
    IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device);
const _macos = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device);

/// The database transaction serializes foreground/background key creation.
/// A fresh database replaces any keychain item left behind by an uninstall.
Future<E2eeRecordStore> openAccountRecords(Database db,
    {required String accountId,
    required FlutterSecureStorage storage}) async {
  if (accountId.isEmpty) throw ArgumentError('An account is required');
  await E2eeRecordStore.createSchema(db);
  return db.transaction((txn) async {
    final existing = await txn.query('e2ee_records', limit: 1);
    Uint8List wrappingKey;
    if (existing.isEmpty) {
      final random = Random.secure();
      wrappingKey =
          Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
      // Save the key before DB state; secure-storage failures abort init.
      await storage.write(
          key: _keyName(accountId),
          value: base64Encode(wrappingKey),
          aOptions: _android,
          iOptions: _ios,
          mOptions: _macos);
      await E2eeRecordStore(txn,
              accountId: accountId, wrappingKey: wrappingKey)
          .write('account', 'key_check', Uint8List.fromList([1]));
    } else {
      final encoded = await storage.read(
          key: _keyName(accountId),
          aOptions: _android,
          iOptions: _ios,
          mOptions: _macos);
      if (encoded == null) {
        throw StateError('The account crypto wrapping key is missing');
      }
      wrappingKey = base64Decode(encoded);
      if (wrappingKey.length != 32 || base64Encode(wrappingKey) != encoded) {
        throw const FormatException('Invalid account crypto wrapping key');
      }
      final check = await E2eeRecordStore(txn,
              accountId: accountId, wrappingKey: wrappingKey)
          .read('account', 'key_check');
      if (check == null || check.length != 1 || check.single != 1) {
        throw StateError(
            'The account crypto key check is missing or invalid');
      }
    }
    return E2eeRecordStore(db,
        accountId: accountId, wrappingKey: wrappingKey);
  });
}

/// The user chose to start this phone's encryption over. Records go before
/// the key, so a crash between still leaves a fresh start for [openAccountRecords].
/// ponytail: a keystore too broken to write a new key stays locked; clearing
/// the app's storage is the way out then.
Future<void> resetAccountRecords(Database db,
    {required String accountId,
    required FlutterSecureStorage storage}) async {
  await E2eeRecordStore.createSchema(db);
  await db.delete('e2ee_records');
  await deleteAccountRecordsKey(accountId, storage);
}

/// Called after account deletion has stopped every writer and erased its DB.
Future<void> deleteAccountRecordsKey(
        String accountId, FlutterSecureStorage storage) =>
    storage.delete(
        key: _keyName(accountId),
        aOptions: _android,
        iOptions: _ios,
        mOptions: _macos);
