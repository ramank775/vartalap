import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Private Signal records, encrypted with a per-account secure-storage key
/// (its lifecycle is in `e2ee_account.dart`; this file stays plain Dart so
/// the mock server's simulated peers run the same crypto).
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

  E2eeRecordStore forTransaction(Transaction txn) {
    if (!identical(txn.database, _db.database)) {
      throw ArgumentError('Crypto records must use their account database');
    }
    return E2eeRecordStore(txn,
        accountId: _accountId, wrappingKey: _wrappingKey);
  }

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
    if (value.length < 29 || (value[0] != 1 && value[0] != 2)) {
      throw const FormatException('Invalid encrypted crypto record');
    }
    return _cipher(value[0], false, value.sublist(1, 13), aad)(
        value.sublist(13));
  }

  /// Version 2: ChaCha20-Poly1305 (RFC 8439). Pure-Dart AES-GCM, version
  /// 1, cost 5-15 ms a record, and every message touches several; 1 still
  /// opens. Both take a 12-byte nonce and a 16-byte tag.
  Uint8List Function(Uint8List) _cipher(
      int version, bool encrypt, Uint8List nonce, Uint8List aad) {
    final params =
        AEADParameters(KeyParameter(_wrappingKey), 128, nonce, aad);
    if (version == 1) {
      return (GCMBlockCipher(AESEngine())..init(encrypt, params)).process;
    }
    final cipher = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())
      ..init(encrypt, params);
    // Its inherited process() skips doFinal: no tag written or checked.
    return (input) {
      final out = Uint8List(cipher.getOutputSize(input.length));
      try {
        var length = cipher.processBytes(input, 0, input.length, out, 0);
        length += cipher.doFinal(out, length);
        return out.sublist(0, length);
      } on ArgumentError catch (e) {
        // A failed tag check is an ArgumentError here, GCM's own exception
        // everywhere else: one failure type for callers.
        throw InvalidCipherTextException('$e');
      }
    };
  }

  /// The record keys stored under [namespace].
  Future<List<String>> keys(String namespace) async => [
        for (final row in await _db.query('e2ee_records',
            columns: ['record_key'],
            where: 'namespace = ?',
            whereArgs: [namespace]))
          row['record_key'] as String
      ];

  Future<void> write(String namespace, String key, Uint8List record) async {
    _requireTransaction();
    final aad = _aad(namespace, key);
    final random = Random.secure();
    final nonce =
        Uint8List.fromList(List.generate(12, (_) => random.nextInt(256)));
    await _db.insert(
      'e2ee_records',
      {
        'namespace': namespace,
        'record_key': key,
        'value': Uint8List.fromList(
            [2, ...nonce, ..._cipher(2, true, nonce, aad)(record)]),
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
  final bool ephemeral;
  final String peer;
  final int ttlSec;

  E2eeOperationContext({
    required this.opId,
    required this.channelId,
    required this.senderUserId,
    required this.senderDeviceId,
    this.ephemeral = false,
    this.peer = '',
    this.ttlSec = 0,
  }) {
    if ([opId, channelId, senderUserId, senderDeviceId]
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
        decoded.length != 9 ||
        decoded[0] is! int ||
        decoded[5] is! bool ||
        decoded[7] is! int ||
        decoded[8] is! String ||
        [1, 2, 3, 4, 6].any((i) => decoded[i] is! String)) {
      throw const FormatException('Invalid authenticated operation frame');
    }
    final expected = _header;
    for (var i = 0; i < expected.length; i++) {
      if (decoded[i] != expected[i]) {
        throw const FormatException('Authenticated operation context mismatch');
      }
    }
    final payload = base64.decode(decoded[8] as String);
    if (base64.encode(payload) != decoded[8]) {
      throw const FormatException('Noncanonical authenticated payload');
    }
    return payload;
  }
}
