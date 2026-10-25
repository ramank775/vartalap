/// The mock server's key directory (AUTH_CONTRACT §17) and its simulated
/// users — the seed peer, and anyone a test makes who never signs in — as
/// Signal participants. They run the app's own crypto over in-memory
/// databases and publish into the same directory a phone does, so the
/// strict mock relays only ciphertext, exactly like the real server, and a
/// test still reads what the other side got.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// user_id -> deviceId -> the published record (`generation`, the public
/// bundle, unclaimed `preKeys`, `lastPreKeyId`).
typedef KeyDirectory = Map<String, Map<String, Map<String, dynamic>>>;

/// `PUT /v3.0/keys/me`, the server's semantics in short: a same-identity
/// upload keeps its generation and adds only prekey ids above the greatest
/// seen; a new identity starts over. Returns the response body.
Map<String, dynamic> publishKeys(KeyDirectory directory, String userId,
    String deviceId, Map<String, dynamic> body, String Function() newId) {
  final devices = directory.putIfAbsent(userId, () => {});
  final current = devices[deviceId];
  final same = current != null && current['identityKey'] == body['identityKey'];
  final last = same ? current['lastPreKeyId'] as int : -1;
  final added = [
    for (final key in (body['preKeys'] as List).cast<Map<String, dynamic>>())
      if ((key['id'] as int) > last) key
  ];
  final record = <String, dynamic>{
    'generation': same ? current['generation'] : newId(),
    'identityKey': body['identityKey'],
    'registrationId': body['registrationId'],
    'signedPreKey': body['signedPreKey'],
    'preKeys': [if (same) ...current['preKeys'] as List, ...added],
    'lastPreKeyId': [last, for (final key in added) key['id'] as int]
        .reduce((a, b) => a > b ? a : b),
  };
  devices[deviceId] = record;
  return {
    ...publicBundle(deviceId, record),
    'preKeyCount': (record['preKeys'] as List).length,
  };
}

Map<String, dynamic> publicBundle(String deviceId, Map<String, dynamic> r) => {
      'deviceId': deviceId,
      'generation': r['generation'],
      'identityKey': r['identityKey'],
      'registrationId': r['registrationId'],
      'signedPreKey': r['signedPreKey'],
    };

/// `POST /v3.0/keys/{userId}/claim`: the bundle plus one prekey, removed;
/// null for an unknown device or a stale generation.
Map<String, dynamic>? claimKeys(KeyDirectory directory, String userId,
    String deviceId, String generation) {
  final record = directory[userId]?[deviceId];
  if (record == null || record['generation'] != generation) return null;
  final preKeys = record['preKeys'] as List;
  return {
    ...publicBundle(deviceId, record),
    'preKey': preKeys.isEmpty ? null : preKeys.removeAt(0),
  };
}

class MockPeers {
  /// Every simulated user's one device.
  static const deviceId = 'mock-peer';

  final KeyDirectory directory;
  final String Function() newId;
  final _peers = <String, Future<E2eeCrypto>>{};

  MockPeers(this.directory, this.newId) {
    sqfliteFfiInit();
  }

  bool isPeer(String userId) => _peers.containsKey(userId);

  /// [userId]'s crypto, enrolled and published on first use.
  Future<E2eeCrypto> forUser(String userId) =>
      _peers[userId] ??= _enroll(userId);

  Future<E2eeCrypto> _enroll(String userId) async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await E2eeRecordStore.createSchema(db);
    final records =
        E2eeRecordStore(db, accountId: userId, wrappingKey: Uint8List(32));
    final upload = await db.transaction((txn) async {
      final stores = SignalStores(records.forTransaction(txn));
      await stores.createIdentity();
      await stores.addPreKeys(100);
      return stores.upload();
    });
    publishKeys(directory, userId, deviceId,
        jsonDecode(jsonEncode(upload.toJson())) as Map<String, dynamic>, newId);
    return E2eeCrypto(
      db: db,
      records: records,
      selfUserId: userId,
      selfDeviceId: deviceId,
      directory: (user) async => [
        for (final MapEntry(:key, :value) in (directory[user] ?? {}).entries)
          E2eeDeviceBundle.fromJson(publicBundle(key, value))
      ],
      claim: (user, device, generation) async {
        final claimed = claimKeys(directory, user, device, generation);
        if (claimed == null) throw StateError('no keys $user/$device');
        return E2eeKeyClaim.fromJson(claimed);
      },
    );
  }
}
