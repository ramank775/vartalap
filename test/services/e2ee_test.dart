import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart';
import 'package:vartalap/services/e2ee_account.dart';

import '../fake_unified_push.dart';

void main() {
  final wrappingKey = Uint8List.fromList(List.generate(32, (i) => i));
  final record = Uint8List.fromList(utf8.encode('private ratchet record'));
  E2eeRecordStore records(DatabaseExecutor db, {String account = 'account'}) =>
      E2eeRecordStore(db, accountId: account, wrappingKey: wrappingKey);

  group('encrypted crypto records', () {
    late Database db;
    Future<void> write(String namespace, String key, Uint8List value) =>
        db.transaction((txn) => records(txn).write(namespace, key, value));

    setUpAll(sqfliteFfiInit);
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false));
      await E2eeRecordStore.createSchema(db);
    });
    tearDown(() => db.close());

    group('account key lifecycle', () {
      late _KeyStorage storage;
      const keyName = 'v3.e2ee.wrappingKey.account';
      Future<E2eeRecordStore> open({String account = 'account'}) =>
          openAccountRecords(db, accountId: account, storage: storage);

      setUp(() => storage = _KeyStorage());

      test('reopen and concurrent initialization preserve the same key',
          () async {
        final stores = await Future.wait([open(), open()]);
        expect(storage.writes, 1);
        await db.transaction((txn) =>
            stores.first.forTransaction(txn).write('session', 'peer', record));
        expect(await stores.last.read('session', 'peer'), record);
        expect(await (await open()).read('session', 'peer'), record);
        expect(storage.writes, 1);
        expect(storage.android!['resetOnError'], 'false');
        expect(storage.ios!['accessibility'], 'first_unlock_this_device');
        expect(storage.ios!['synchronizable'], 'false');
      });

      test('a fresh database replaces a key left in the keychain', () async {
        final stale = base64Encode(Uint8List(32));
        await storage.write(key: keyName, value: stale);
        await open();
        expect(await storage.read(key: keyName), isNot(stale));
        expect(await db.query('e2ee_records'), hasLength(1));
      });

      test('missing, corrupt and wrong keys never replace existing state',
          () async {
        final first = await open();
        await db.transaction((txn) =>
            first.forTransaction(txn).write('session', 'peer', record));
        final correct = await storage.read(key: keyName);
        for (final invalid in [
          null,
          'not-base64',
          base64Encode(Uint8List(31)),
          base64Encode(Uint8List(32))
        ]) {
          await storage.write(key: keyName, value: invalid);
          final count = storage.writes;
          await expectLater(open(), throwsA(anything));
          expect(storage.writes, count);
          expect(await db.query('e2ee_records'), hasLength(2));
        }
        await storage.write(key: keyName, value: correct);
        expect(await (await open()).read('session', 'peer'), record);
      });

      test('secure-storage failure leaves no initialized crypto state',
          () async {
        storage.failWrite = true;
        await expectLater(open(), throwsStateError);
        expect(await db.query('e2ee_records'), isEmpty);
        storage.failWrite = false;
        await open();
        expect(await db.query('e2ee_records'), hasLength(1));
      });

      test('account isolation, deletion and foreign transaction rejection',
          () async {
        final first = await open();
        final other = await databaseFactoryFfi.openDatabase(
            inMemoryDatabasePath,
            options: OpenDatabaseOptions(singleInstance: false));
        try {
          final second = await openAccountRecords(other,
              accountId: 'other', storage: storage);
          await other.transaction((txn) async {
            expect(() => first.forTransaction(txn), throwsArgumentError);
            await second.forTransaction(txn).write('session', 'peer', record);
          });
          expect(await first.read('session', 'peer'), isNull);
          await deleteAccountRecordsKey('account', storage);
          expect(await storage.read(key: keyName), isNull);
          expect(await second.read('session', 'peer'), record);
          await expectLater(open(), throwsStateError);
        } finally {
          await other.close();
        }
      });
    });

    test('reads an independently generated Node ChaCha20-Poly1305 fixture',
        () async {
      const hex = '02000000000000000000000000ec6e80d0343d1508fdd9f80e174d8c0b'
          'd14400e23e783dec0fb50792b0';
      final fixture = Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
      await db.insert('e2ee_records', {
        'namespace': 'session',
        'record_key': 'peer',
        'value': fixture,
      });
      final store = E2eeRecordStore(db,
          accountId: 'account-a', wrappingKey: Uint8List(32));
      expect(await store.read('session', 'peer'), utf8.encode('signal-record'));
    });

    test('still reads a version 1 Node AES-256-GCM fixture', () async {
      const hex = '01000000000000000000000000bdce27532c0c461c622daaa1de78843c'
          'ef3831262406af9deed3f4f322';
      final fixture = Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
      await db.insert('e2ee_records', {
        'namespace': 'session',
        'record_key': 'peer',
        'value': fixture,
      });
      final store = E2eeRecordStore(db,
          accountId: 'account-a', wrappingKey: Uint8List(32));
      expect(await store.read('session', 'peer'), utf8.encode('signal-record'));
    });

    test('rejects missing account and malformed wrapping key', () {
      expect(() => E2eeRecordStore(db, accountId: '', wrappingKey: wrappingKey),
          throwsArgumentError);
      expect(
          () => E2eeRecordStore(db,
              accountId: 'account', wrappingKey: Uint8List(31)),
          throwsArgumentError);
    });

    test('reopens encrypted records, uses fresh nonces and deletes', () async {
      await db
          .transaction((txn) => records(txn).write('session', 'peer', record));
      final first =
          (await db.query('e2ee_records')).single['value'] as List<int>;
      expect(first, isNot(containsAllInOrder(record)));
      expect(await records(db).read('session', 'peer'), record);
      await write('session', 'peer', record);
      final second =
          (await db.query('e2ee_records')).single['value'] as List<int>;
      expect(second, isNot(first));
      await db.transaction((txn) => records(txn).remove('session', 'peer'));
      expect(await records(db).read('session', 'peer'), isNull);
    });

    test('empty serialized records still authenticate', () async {
      await write('sender_key', 'empty', Uint8List(0));
      expect(await records(db).read('sender_key', 'empty'), isEmpty);
    });

    test('rejects modified ciphertext and wrong wrapping keys', () async {
      await write('prekey', '1', record);
      final wrongKey =
          E2eeRecordStore(db, accountId: 'account', wrappingKey: Uint8List(32));
      await expectLater(wrongKey.read('prekey', '1'),
          throwsA(isA<InvalidCipherTextException>()));
      final ciphertext = Uint8List.fromList(
          (await db.query('e2ee_records')).single['value'] as List<int>);
      ciphertext.last ^= 1;
      await db.update('e2ee_records', {'value': ciphertext});
      await expectLater(records(db).read('prekey', '1'),
          throwsA(isA<InvalidCipherTextException>()));
    });

    test('AAD binds account, namespace and record key', () async {
      await write('session', 'peer1', record);
      await expectLater(records(db, account: 'other').read('session', 'peer1'),
          throwsA(isA<InvalidCipherTextException>()));
      await db.update('e2ee_records', {'record_key': 'peer2'});
      await expectLater(records(db).read('session', 'peer2'),
          throwsA(isA<InvalidCipherTextException>()));
      await db.update('e2ee_records', {'namespace': 'prekey'});
      await expectLater(records(db).read('prekey', 'peer2'),
          throwsA(isA<InvalidCipherTextException>()));
    });

    test('rejects truncated and unknown record formats', () async {
      await write('session', 'peer', record);
      for (final invalid in [Uint8List(28), Uint8List(29)..[0] = 3]) {
        await db.update('e2ee_records', {'value': invalid});
        await expectLater(records(db).read('session', 'peer'),
            throwsA(isA<FormatException>()));
      }
    });

    test('caller transaction rolls record and ciphertext back together',
        () async {
      await db.execute('CREATE TABLE outbound_ciphertext (value BLOB)');
      await expectLater(db.transaction((txn) async {
        await records(txn).write('session', 'peer', record);
        await txn.insert('outbound_ciphertext', {
          'value': Uint8List.fromList([9])
        });
        throw StateError('crash before commit');
      }), throwsStateError);
      expect(await records(db).read('session', 'peer'), isNull);
      expect(await db.query('outbound_ciphertext'), isEmpty);
      await db.transaction((txn) async {
        await records(txn).write('session', 'peer', record);
        await txn.insert('outbound_ciphertext', {
          'value': Uint8List.fromList([9])
        });
      });
      expect(await records(db).read('session', 'peer'), record);
      expect(await db.query('outbound_ciphertext'), hasLength(1));
    });

    test(
        'mutations cannot create, replace or remove pins outside a transaction',
        () async {
      final original = Uint8List(33)..[0] = 5;
      final changed = Uint8List.fromList(original)..[32] = 1;
      const key = 'peer';
      final store = records(db);
      await expectLater(
          store.write('session', 'peer', record), throwsStateError);
      await expectLater(
          store.pinIdentity(userId: 'peer', identityKey: original),
          throwsStateError);
      expect(await db.query('e2ee_records'), isEmpty);
      await db.transaction((txn) =>
          records(txn).pinIdentity(userId: 'peer', identityKey: original));
      await expectLater(
          store.pinIdentity(userId: 'peer', identityKey: changed),
          throwsStateError);
      await expectLater(
          store.write('identity_pin', key, changed), throwsStateError);
      await expectLater(store.remove('identity_pin', key), throwsStateError);
      expect(await store.read('identity_pin', key), original);
    });

    test(
        'a contact\'s new identity replaces the pin and reports the change, '
        'WhatsApp style (184)', () async {
      final original = Uint8List(33)..[0] = 5;
      final changed = Uint8List.fromList(original)..[32] = 1;
      Future<bool> pin(Uint8List key) => db.transaction(
          (txn) => records(txn).pinIdentity(userId: 'peer', identityKey: key));
      expect(await pin(original), isFalse, reason: 'first contact: no notice');
      expect(await pin(original), isFalse);
      expect(await pin(changed), isTrue, reason: 'security code changed');
      expect(await records(db).read('identity_pin', 'peer'), changed);
      expect(await pin(changed), isFalse);
      await expectLater(pin(Uint8List(33)), throwsArgumentError);
    });
  });

  group('authenticated operation framing (sealed v2, decision 218)', () {
    E2eeOperationContext ctx({
      String opId = '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0001',
      String channelId = 'dfb52701fdba81ed569700bb933fc0eb',
      String senderUserId = '0a11ce001',
      String senderDeviceId = '0190aaaa-bbbb-4ccc-8ddd-eeeeffff00aa',
      bool ephemeral = false,
      String peer = '0b0b00002',
      int ttlSec = 30,
    }) =>
        E2eeOperationContext(
            opId: opId,
            channelId: channelId,
            senderUserId: senderUserId,
            senderDeviceId: senderDeviceId,
            ephemeral: ephemeral,
            peer: peer,
            ttlSec: ttlSec);
    final context = ctx();
    final payload = Uint8List.fromList([0, 8, 255, 240]);
    const retryOf = '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0000';

    test('round-trips binary payload without timestamps, in 18 bytes of '
        'header', () {
      final sealed = context.encodePlaintext(payload);
      expect(sealed.length, 18 + payload.length);
      expect(sealed[0], 2, reason: 'the version byte');
      expect(sealed.sublist(18), payload, reason: 'the payload raw');
      expect(context.decodeAuthenticatedPlaintext(sealed), payload);
    });

    test('carries the op a re-send replaces, authenticated with the rest', () {
      final framed = context.encodePlaintext(payload, retryOf: retryOf);
      expect(framed.length, 18 + 16 + payload.length);
      final opened = context.decodeAuthenticated(framed);
      expect([opened.payload, opened.retryOf], [payload, retryOf]);
      expect(
          context.decodeAuthenticated(context.encodePlaintext(payload)).retryOf,
          '');
    });

    test('rejects each mismatched context field and version', () {
      final sealed = context.encodePlaintext(payload, retryOf: retryOf);
      for (final other in [
        ctx(opId: '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0009'),
        ctx(channelId: '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0002'),
        ctx(senderUserId: '0c0ffee03'),
        ctx(senderDeviceId: '0190aaaa-bbbb-4ccc-8ddd-eeeeffff00bb'),
        ctx(ephemeral: true),
        ctx(peer: '0c0ffee03'),
        ctx(ttlSec: 31),
      ]) {
        expect(() => other.decodeAuthenticatedPlaintext(sealed),
            throwsA(isA<FormatException>()));
      }
      // Moving bytes between adjacent fields changes the tag too: each
      // is length-prefixed.
      expect(
          () => ctx(senderUserId: '0a11ce00', senderDeviceId: '1-')
              .decodeAuthenticatedPlaintext(
                  ctx(senderUserId: '0a11ce001', senderDeviceId: '-')
                      .encodePlaintext(payload)),
          throwsA(isA<FormatException>()));
      expect(
          () => context.decodeAuthenticatedPlaintext(
              Uint8List.fromList(sealed)..[0] = 1),
          throwsA(isA<FormatException>()),
          reason: 'v1 is not read');
    });

    test('rejects malformed frames', () {
      final sealed = context.encodePlaintext(payload, retryOf: retryOf);
      for (final bad in [
        Uint8List.fromList([255]),
        sealed.sublist(0, 17),
        Uint8List.fromList(sealed)..[17] = 5, // a retry length of 5
        sealed.sublist(0, 30), // shorter than the retry it names
        Uint8List.fromList(sealed)..[3] ^= 1, // the tag
      ]) {
        expect(() => context.decodeAuthenticatedPlaintext(bad),
            throwsA(isA<FormatException>()));
      }
    });

    test('invalid key and required context fail before persistence', () {
      expect(() => ctx(opId: ''), throwsArgumentError);
      expect(() => ctx(ttlSec: 0x100000000), throwsArgumentError);
    });
  });
}

class _KeyStorage extends InMemorySecureStorage {
  int writes = 0;
  bool failWrite = false;
  Map<String, String>? android;
  Map<String, String>? ios;

  @override
  Future<void> write(
      {required String key,
      required String? value,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) {
    if (failWrite) throw StateError('Secure storage is unavailable');
    writes++;
    android = aOptions?.toMap();
    ios = iOptions?.toMap();
    return super.write(key: key, value: value);
  }
}
