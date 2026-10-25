import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/e2ee.dart';
import 'package:vartalap/services/signal_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// One phone: its own in-memory account database and crypto records.
class _Phone {
  final String userId;
  final String deviceId;
  final Database db;
  final E2eeRecordStore records;

  _Phone(this.userId, this.deviceId, this.db)
      : records = E2eeRecordStore(db,
            accountId: userId,
            wrappingKey: Uint8List.fromList(List.filled(32, userId.length)));

  static Future<_Phone> enrolled(String userId, String deviceId) async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await E2eeRecordStore.createSchema(db);
    final phone = _Phone(userId, deviceId, db);
    await phone.txn((stores) async {
      await stores.createIdentity();
      await stores.addPreKeys(5);
    });
    return phone;
  }

  SignalProtocolAddress get address => signalAddress(userId, deviceId);

  /// Run [body] with stores bound to one transaction, as the app must.
  Future<T> txn<T>(Future<T> Function(SignalStores stores) body) =>
      db.transaction((t) => body(SignalStores(records.forTransaction(t))));

  SessionCipher cipher(SignalStores s, SignalProtocolAddress to) =>
      SessionCipher(s, s, s, s, to);

  /// What a claim of this phone's keys returns, as a library bundle.
  Future<PreKeyBundle> bundle() => txn((s) async {
        final upload = await s.upload();
        final preKey = upload.preKeys.first;
        Uint8List bytes(String b64) => base64.decode(b64);
        return PreKeyBundle(
          upload.registrationId,
          1,
          preKey.id,
          Curve.decodePoint(bytes(preKey.publicKey), 0),
          upload.signedPreKey.id,
          Curve.decodePoint(bytes(upload.signedPreKey.publicKey), 0),
          bytes(upload.signedPreKey.signature),
          IdentityKey.fromBytes(bytes(upload.identityKey), 0),
        );
      });

  Future<CiphertextMessage> send(_Phone to, String text) async {
    final bundle = await to.bundle();
    return txn((s) async {
      if (!await s.containsSession(to.address)) {
        await SessionBuilder(s, s, s, s, to.address).processPreKeyBundle(bundle);
      }
      return cipher(s, to.address).encrypt(utf8.encode(text));
    });
  }

  Future<String> receive(_Phone from, CiphertextMessage message) =>
      txn((s) async {
        final c = cipher(s, from.address);
        final plain = message is PreKeySignalMessage
            ? await c.decrypt(message)
            : await c.decryptFromSignal(
                SignalMessage.fromSerialized(message.serialize()));
        return utf8.decode(plain);
      });
}

class _Publishing extends AuthClient {
  final uploads = <E2eeKeyUpload>[];
  int serverCount;

  _Publishing(this.serverCount) : super(baseUrl: Uri.parse('http://127.0.0.1:9'));

  @override
  Future<E2eeKeyPublication> publishDeviceKeys(E2eeKeyUpload upload) async {
    uploads.add(upload);
    serverCount += upload.preKeys.length;
    return E2eeKeyPublication.fromJson({
      'deviceId': 'phone-a',
      'generation': '7f1c2b3a-0000-4000-8000-000000000001',
      'identityKey': upload.identityKey,
      'registrationId': upload.registrationId,
      'signedPreKey': upload.signedPreKey.toJson(),
      'preKeyCount': serverCount,
    });
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('a 1:1 exchange survives reopening the stores between every step',
      () async {
    final alice = await _Phone.enrolled('a11ce0001', 'phone-a');
    final bob = await _Phone.enrolled('b0b000002', 'phone-b');

    final first = await alice.send(bob, 'hi bob');
    expect(first, isA<PreKeySignalMessage>());
    expect(await bob.receive(alice, first), 'hi bob');
    expect(await bob.txn((s) => s.containsPreKey(1)), isFalse,
        reason: 'the one-time prekey is used up');

    // Every call above built fresh stores over the database: the ratchet
    // lives in SQLite, not in memory.
    final reply = await bob.txn(
        (s) => bob.cipher(s, alice.address).encrypt(utf8.encode('hi alice')));
    expect(await alice.receive(bob, reply), 'hi alice');
    final again = await alice.send(bob, 'second');
    expect(again, isA<SignalMessage>());
    expect(await bob.receive(alice, again), 'second');
  });

  test('a forged first message rolls back every write, the identity included',
      () async {
    final alice = await _Phone.enrolled('a11ce0001', 'phone-a');
    final bob = await _Phone.enrolled('b0b000002', 'phone-b');
    final genuine = await alice.send(bob, 'hi') as PreKeySignalMessage;
    final inner = genuine.getWhisperMessage().serialize();
    final raw = genuine.serialize();
    final at = _indexOf(raw, inner);
    final forged = Uint8List.fromList(raw)..[at + inner.length - 1] ^= 1;

    await expectLater(
        bob.receive(alice, PreKeySignalMessage(forged)), throwsA(anything));
    expect(await bob.records.read('identity_pin', 'a11ce0001'), isNull,
        reason: 'the library saved it before the MAC failed; rolled back');
    expect(await bob.txn((s) => s.containsPreKey(1)), isTrue);
    expect(await bob.receive(alice, genuine), 'hi');
  });

  test('a contact\'s new phone is accepted and reported as a changed '
      'security code (184)', () async {
    final bob = await _Phone.enrolled('b0b000002', 'phone-b');
    final alice = await _Phone.enrolled('a11ce0001', 'phone-a');
    await bob.receive(alice, await alice.send(bob, 'old phone'));

    final newPhone = await _Phone.enrolled('a11ce0001', 'phone-a2');
    final message = await newPhone.send(bob, 'new phone') as PreKeySignalMessage;
    final changed = await bob.txn((s) async {
      final plain = await bob.cipher(s, newPhone.address).decrypt(message);
      expect(utf8.decode(plain), 'new phone');
      return s.changedIdentities;
    });
    expect(changed, {'a11ce0001'});
  });

  test('publishing creates the identity once and tops up a low server',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await E2eeRecordStore.createSchema(db);
    final records = E2eeRecordStore(db,
        accountId: 'a11ce0001', wrappingKey: Uint8List(32));

    final client = _Publishing(0);
    await ensureKeysPublished(db, records, client, batch: 10, low: 15);
    expect(client.uploads, hasLength(2), reason: '10 < 15, so a second batch');
    expect(client.uploads[0].preKeys.map((k) => k.id), [for (var i = 1; i <= 10; i++) i]);
    expect(client.uploads[1].preKeys.map((k) => k.id), [for (var i = 11; i <= 20; i++) i]);

    await ensureKeysPublished(db, records, client, batch: 10, low: 15);
    expect(client.uploads, hasLength(3), reason: 'plenty left: one publish');
    expect(client.uploads[2].identityKey, client.uploads[0].identityKey,
        reason: 'the identity is created once');
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var same = true;
    for (var j = 0; j < needle.length && same; j++) {
      same = haystack[i + j] == needle[j];
    }
    if (same) return i;
  }
  throw StateError('not found');
}
