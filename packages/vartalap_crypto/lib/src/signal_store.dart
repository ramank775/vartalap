import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

import 'e2ee.dart';

/// A device's Signal address. Vartalap device ids are strings and the
/// library's are ints, so the device goes in the name (user ids are 9 hex
/// characters, never a dot) and every device is slot 1.
SignalProtocolAddress signalAddress(String userId, String deviceId) =>
    SignalProtocolAddress('$userId.$deviceId', 1);

String _userOf(SignalProtocolAddress address) {
  final name = address.getName();
  final dot = name.indexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

/// The library's stores over [E2eeRecordStore]. Build one per database
/// transaction: every write the library makes, including the identity it
/// saves before a forged first message fails its MAC, then commits or
/// rolls back with that transaction.
class SignalStores
    implements
        IdentityKeyStore,
        PreKeyStore,
        SignedPreKeyStore,
        SessionStore,
        SenderKeyStore {
  final E2eeRecordStore _records;

  /// Users whose security code changed in this transaction (decision 184):
  /// the caller adds a "security code changed" line to each one's chat.
  final changedIdentities = <String>{};

  SignalStores(this._records);

  static Uint8List _int(int value) =>
      (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
  static int _readInt(Uint8List bytes) =>
      ByteData.sublistView(bytes).getUint32(0);

  // ---- this phone's identity and enrollment --------------------------

  Future<bool> hasIdentity() async =>
      await _records.read('self', 'identity') != null;

  /// A fresh identity: key pair, registration id and signed prekey 1.
  /// One-time prekeys come from [addPreKeys].
  Future<void> createIdentity({int? nowMs}) async {
    final identity = generateIdentityKeyPair();
    await _records.write('self', 'identity', identity.serialize());
    await _records.write(
        'self', 'registration', _int(generateRegistrationId(false)));
    await _newSignedPreKey(identity, 1, nowMs);
    await _records.write('self', 'next_prekey', _int(1));
  }

  Future<void> _newSignedPreKey(
      IdentityKeyPair identity, int id, int? nowMs) async {
    await storeSignedPreKey(id, generateSignedPreKey(identity, id));
    await _records.write('self', 'signed_prekey', _int(id));
    await _records.write('self', 'signed_prekey_at',
        _int((nowMs ?? DateTime.now().millisecondsSinceEpoch) ~/ 1000));
  }

  Future<int> _currentSignedPreKey() async =>
      _readInt((await _records.read('self', 'signed_prekey')) ?? _int(1));

  /// Signal's habit: a new signed prekey once the current one is [maxAge]
  /// old, the previous kept for sessions a sender started on it, older
  /// ones gone. The server takes a higher id and never rolls back.
  Future<bool> rotateSignedPreKey(
      {Duration maxAge = const Duration(days: 30), int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final at = await _records.read('self', 'signed_prekey_at');
    if (at != null &&
        now - _readInt(at) * 1000 < maxAge.inMilliseconds) {
      return false;
    }
    final current = await _currentSignedPreKey();
    await _newSignedPreKey(await getIdentityKeyPair(), current + 1, now);
    for (final key in await _records.keys('signed_prekey')) {
      if (int.parse(key) < current) await removeSignedPreKey(int.parse(key));
    }
    return true;
  }

  /// [count] new one-time prekeys with ids above every earlier one: the
  /// server ignores an id at or below the greatest it has seen.
  /// ponytail: ids never wrap; 16.7M of them last forever at 100 a batch.
  Future<void> addPreKeys(int count) async {
    final next = _readInt((await _records.read('self', 'next_prekey'))!);
    for (var id = next; id < next + count; id++) {
      await storePreKey(id, PreKeyRecord(id, Curve.generateKeyPair()));
    }
    await _records.write('self', 'next_prekey', _int(next + count));
  }

  /// What `PUT /v3.0/keys/me` takes: the public half of the identity, the
  /// signed prekey and the [newest] one-time prekeys. Only ids above what
  /// the server has seen count, and those are always the newest; older
  /// ones claimed by a sender who never wrote stay here, so never send all.
  Future<E2eeKeyUpload> upload({int newest = 100}) async {
    final identity = await getIdentityKeyPair();
    final signed = await loadSignedPreKey(await _currentSignedPreKey());
    final preKeys = [
      for (final key in await _records.keys('prekey'))
        await loadPreKey(int.parse(key))
    ]..sort((a, b) => a.id.compareTo(b.id));
    final recent = preKeys.skip(preKeys.length > newest ? preKeys.length - newest : 0);
    return E2eeKeyUpload(
      identityKey: base64.encode(identity.getPublicKey().serialize()),
      registrationId: await getLocalRegistrationId(),
      signedPreKey: E2eeSignedPreKey(
        id: signed.id,
        publicKey: base64.encode(signed.getKeyPair().publicKey.serialize()),
        signature: base64.encode(signed.signature),
      ),
      preKeys: [
        for (final key in recent)
          E2eePreKey(
            id: key.id,
            publicKey: base64.encode(key.getKeyPair().publicKey.serialize()),
          )
      ],
    );
  }

  // ---- IdentityKeyStore -----------------------------------------------

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    final bytes = await _records.read('self', 'identity');
    if (bytes == null) throw StateError('No Signal identity on this phone');
    return IdentityKeyPair.fromSerialized(bytes);
  }

  @override
  Future<int> getLocalRegistrationId() async =>
      _readInt((await _records.read('self', 'registration'))!);

  @override
  Future<bool> saveIdentity(
      SignalProtocolAddress address, IdentityKey? identityKey) async {
    if (identityKey == null) return false;
    final userId = _userOf(address);
    final changed = await _records.pinIdentity(
        userId: userId, identityKey: identityKey.serialize());
    if (changed) changedIdentities.add(userId);
    return changed;
  }

  /// WhatsApp style (decision 184): every identity is trusted; a change is
  /// accepted and reported through [saveIdentity].
  @override
  Future<bool> isTrustedIdentity(SignalProtocolAddress address,
          IdentityKey? identityKey, Direction direction) async =>
      true;

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final bytes = await _records.read('identity_pin', _userOf(address));
    return bytes == null ? null : IdentityKey.fromBytes(bytes, 0);
  }

  // ---- PreKeyStore -----------------------------------------------------

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final bytes = await _records.read('prekey', '$preKeyId');
    if (bytes == null) throw InvalidKeyIdException('No prekey $preKeyId');
    return PreKeyRecord.fromBuffer(bytes);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      _records.write('prekey', '$preKeyId', record.serialize());

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      await _records.read('prekey', '$preKeyId') != null;

  @override
  Future<void> removePreKey(int preKeyId) =>
      _records.remove('prekey', '$preKeyId');

  // ---- SignedPreKeyStore ----------------------------------------------

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final bytes = await _records.read('signed_prekey', '$signedPreKeyId');
    if (bytes == null) {
      throw InvalidKeyIdException('No signed prekey $signedPreKeyId');
    }
    return SignedPreKeyRecord.fromSerialized(bytes);
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async => [
        for (final key in await _records.keys('signed_prekey'))
          await loadSignedPreKey(int.parse(key))
      ];

  @override
  Future<void> storeSignedPreKey(
          int signedPreKeyId, SignedPreKeyRecord record) =>
      _records.write('signed_prekey', '$signedPreKeyId', record.serialize());

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async =>
      await _records.read('signed_prekey', '$signedPreKeyId') != null;

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) =>
      _records.remove('signed_prekey', '$signedPreKeyId');

  // ---- SessionStore -----------------------------------------------------

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final bytes = await _records.read('session', '$address');
    return bytes == null ? SessionRecord() : SessionRecord.fromSerialized(bytes);
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async => [
        for (final key in await _records.keys('session'))
          if (key.startsWith('$name:') && !key.endsWith(':1'))
            int.parse(key.substring(name.length + 1))
      ];

  @override
  Future<void> storeSession(
          SignalProtocolAddress address, SessionRecord record) =>
      _records.write('session', '$address', record.serialize());

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      await _records.read('session', '$address') != null;

  @override
  Future<void> deleteSession(SignalProtocolAddress address) =>
      _records.remove('session', '$address');

  @override
  Future<void> deleteAllSessions(String name) async {
    for (final key in await _records.keys('session')) {
      if (key.startsWith('$name:')) await _records.remove('session', key);
    }
  }

  // ---- SenderKeyStore ---------------------------------------------------

  @override
  Future<void> storeSenderKey(
          SenderKeyName senderKeyName, SenderKeyRecord record) =>
      _records.write('sender_key', senderKeyName.serialize(), record.serialize());

  @override
  Future<SenderKeyRecord> loadSenderKey(SenderKeyName senderKeyName) async {
    final bytes = await _records.read('sender_key', senderKeyName.serialize());
    return bytes == null
        ? SenderKeyRecord()
        : SenderKeyRecord.fromSerialized(bytes);
  }
}

/// Creates this phone's Signal identity on first use, publishes it with
/// its unused one-time prekeys (AUTH_CONTRACT §17.1) and tops the server
/// up when it runs low. Idempotent; run at account open and once the
/// username lands (the key routes sit behind the §2.4 username gate).
Future<void> ensureKeysPublished(
  Database db,
  E2eeRecordStore records,
  AuthClient client, {
  int batch = 100,
  int low = 20,
}) async {
  final upload = await db.transaction((txn) async {
    final stores = SignalStores(records.forTransaction(txn));
    if (!await stores.hasIdentity()) {
      await stores.createIdentity();
      await stores.addPreKeys(batch);
    } else {
      await stores.rotateSignedPreKey();
    }
    return stores.upload(newest: batch);
  });
  final published = await client.publishDeviceKeys(upload);
  if (published.preKeyCount >= low) return;
  final more = await db.transaction((txn) async {
    final stores = SignalStores(records.forTransaction(txn));
    await stores.addPreKeys(batch);
    return stores.upload(newest: batch);
  });
  await client.publishDeviceKeys(more);
}
