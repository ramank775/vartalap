import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Private Signal records, encrypted with a per-account secure-storage key.
/// Pass the caller's transaction so ratchet writes and the corresponding
/// ciphertext/projection commit together; let every failure roll it back.
/// This store does not implement or enable message encryption.
class E2eeRecordStore {
  final DatabaseExecutor _db;
  final String _accountId;
  final Uint8List _wrappingKey;

  E2eeRecordStore(
    this._db, {
    required String accountId,
    required Uint8List wrappingKey,
  })  : _accountId = accountId,
        _wrappingKey = Uint8List.fromList(wrappingKey) {
    if (accountId.isEmpty || wrappingKey.length != 32) {
      throw ArgumentError('An account and a 32-byte wrapping key are required');
    }
  }

  static String _keyName(String accountId) => 'v3.e2ee.wrappingKey.$accountId';
  static const _android = AndroidOptions(resetOnError: false);
  static const _ios =
      IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device);
  static const _macos = MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device);

  /// The database transaction serializes foreground/background key creation.
  /// A fresh database replaces any keychain item left behind by an uninstall.
  static Future<E2eeRecordStore> openAccount(Database db,
      {required String accountId,
      required FlutterSecureStorage storage}) async {
    if (accountId.isEmpty) throw ArgumentError('An account is required');
    await createSchema(db);
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

  E2eeRecordStore forTransaction(Transaction txn) {
    if (!identical(txn.database, _db.database)) {
      throw ArgumentError('Crypto records must use their account database');
    }
    return E2eeRecordStore(txn,
        accountId: _accountId, wrappingKey: _wrappingKey);
  }

  /// The user chose to start this phone's encryption over. Records go before
  /// the key, so a crash between still leaves a fresh start for [openAccount].
  /// ponytail: a keystore too broken to write a new key stays locked; clearing
  /// the app's storage is the way out then.
  static Future<void> resetAccount(Database db,
      {required String accountId,
      required FlutterSecureStorage storage}) async {
    await createSchema(db);
    await db.delete('e2ee_records');
    await deleteAccountKey(accountId, storage);
  }

  /// Called after account deletion has stopped every writer and erased its DB.
  static Future<void> deleteAccountKey(
          String accountId, FlutterSecureStorage storage) =>
      storage.delete(
          key: _keyName(accountId),
          aOptions: _android,
          iOptions: _ios,
          mOptions: _macos);

  static Future<void> createSchema(DatabaseExecutor db) => db.execute('''
CREATE TABLE IF NOT EXISTS e2ee_records (
  namespace TEXT NOT NULL,
  record_key TEXT NOT NULL,
  value BLOB NOT NULL,
  PRIMARY KEY (namespace, record_key)
)''');

  void _requireTransaction() {
    if (_db is! Transaction) {
      throw StateError('Crypto record mutations require a caller transaction');
    }
  }

  Uint8List _aad(String namespace, String key) {
    if (namespace.isEmpty || key.isEmpty) {
      throw ArgumentError('Record namespace and key must be nonempty');
    }
    return Uint8List.fromList(
        utf8.encode(jsonEncode([1, _accountId, namespace, key])));
  }

  Future<Uint8List?> read(String namespace, String key) async {
    final aad = _aad(namespace, key);
    final rows = await _db.query('e2ee_records',
        columns: ['value'],
        where: 'namespace = ? AND record_key = ?',
        whereArgs: [namespace, key]);
    if (rows.isEmpty) return null;
    final value = Uint8List.fromList(rows.single['value'] as List<int>);
    if (value.length < 29 || value[0] != 1) {
      throw const FormatException('Invalid encrypted crypto record');
    }
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
          false,
          AEADParameters(
              KeyParameter(_wrappingKey), 128, value.sublist(1, 13), aad));
    return cipher.process(value.sublist(13));
  }

  Future<void> write(String namespace, String key, Uint8List record) async {
    _requireTransaction();
    final aad = _aad(namespace, key);
    final random = Random.secure();
    final nonce =
        Uint8List.fromList(List.generate(12, (_) => random.nextInt(256)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(_wrappingKey), 128, nonce, aad));
    await _db.insert(
      'e2ee_records',
      {
        'namespace': namespace,
        'record_key': key,
        'value': Uint8List.fromList([1, ...nonce, ...cipher.process(record)]),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String namespace, String key) async {
    _requireTransaction();
    _aad(namespace, key);
    await _db.delete('e2ee_records',
        where: 'namespace = ? AND record_key = ?', whereArgs: [namespace, key]);
  }

  /// WhatsApp style (decision 184): a contact's new identity is accepted and
  /// replaces the pin, never blocking a send. True when it changed, so the
  /// caller adds a "security code changed" line to that chat; first contact
  /// is false. Keyed by user, never generation or device: a new phone is a
  /// new device id and must still count as a change.
  /// ponytail: one pin per user while each account has one phone (183);
  /// linked devices need a pin per device plus device approval.
  Future<bool> pinIdentity({
    required String userId,
    required Uint8List identityKey,
  }) async {
    _requireTransaction();
    if (userId.isEmpty || identityKey.length != 33 || identityKey[0] != 5) {
      throw ArgumentError('Invalid Signal identity');
    }
    final previous = await read('identity_pin', userId);
    if (previous != null && _equal(previous, identityKey)) return false;
    await write('identity_pin', userId, identityKey);
    return previous != null;
  }
}

bool _equal(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var i = 0; i < first.length; i++) {
    difference |= first[i] ^ second[i];
  }
  return difference == 0;
}

/// Header binding INSIDE Signal's authenticated plaintext, not a wire cipher.
/// Decode only after Signal authentication and inside the ratchet transaction.
/// The server's timestamps are deliberately excluded because it changes them.
class E2eeOperationContext {
  final String opId;
  final String channelId;
  final String senderUserId;
  final String senderDeviceId;
  final String generation;
  final bool ephemeral;
  final String peer;
  final int ttlSec;

  E2eeOperationContext({
    required this.opId,
    required this.channelId,
    required this.senderUserId,
    required this.senderDeviceId,
    required this.generation,
    this.ephemeral = false,
    this.peer = '',
    this.ttlSec = 0,
  }) {
    if ([opId, channelId, senderUserId, senderDeviceId, generation]
            .any((value) => value.isEmpty) ||
        ttlSec < 0 ||
        ttlSec > 0xffffffff) {
      throw ArgumentError('Invalid authenticated operation context');
    }
  }

  List<Object> get _header => [
        1,
        opId,
        channelId,
        senderUserId,
        senderDeviceId,
        generation,
        ephemeral,
        peer,
        ttlSec,
      ];

  Uint8List encodePlaintext(Uint8List payload) => Uint8List.fromList(
      utf8.encode(jsonEncode([..._header, base64.encode(payload)])));

  /// Rejects unknown versions, malformed frames and copied/modified headers.
  /// Authentication/context failures must escape the caller's transaction.
  Uint8List decodeAuthenticatedPlaintext(Uint8List plaintext) {
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! List ||
        decoded.length != 10 ||
        decoded[0] is! int ||
        decoded[6] is! bool ||
        decoded[8] is! int ||
        decoded[9] is! String ||
        [1, 2, 3, 4, 5, 7].any((i) => decoded[i] is! String)) {
      throw const FormatException('Invalid authenticated operation frame');
    }
    final expected = _header;
    for (var i = 0; i < expected.length; i++) {
      if (decoded[i] != expected[i]) {
        throw const FormatException('Authenticated operation context mismatch');
      }
    }
    final payload = base64.decode(decoded[9] as String);
    if (base64.encode(payload) != decoded[9]) {
      throw const FormatException('Noncanonical authenticated payload');
    }
    return payload;
  }
}
