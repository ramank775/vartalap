import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/e2ee.dart';

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

    test('reads an independently generated Node AES-256-GCM fixture', () async {
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
      for (final invalid in [Uint8List(28), Uint8List(29)..[0] = 2]) {
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
      final key = jsonEncode(['peer', 'phone']);
      final store = records(db);
      await expectLater(
          store.write('session', 'peer', record), throwsStateError);
      await expectLater(
          store.pinIdentity(
              userId: 'peer', deviceId: 'phone', identityKey: original),
          throwsStateError);
      expect(await db.query('e2ee_records'), isEmpty);
      await db.transaction((txn) => records(txn).pinIdentity(
          userId: 'peer', deviceId: 'phone', identityKey: original));
      await expectLater(
          store.pinIdentity(
              userId: 'peer', deviceId: 'phone', identityKey: changed),
          throwsStateError);
      await expectLater(
          store.write('identity_pin', key, changed), throwsStateError);
      await expectLater(store.remove('identity_pin', key), throwsStateError);
      expect(await store.read('identity_pin', key), original);
    });

    test('stable user/device pin rejects identity change across generations',
        () async {
      final original = Uint8List(33)..[0] = 5;
      final changed = Uint8List.fromList(original)..[32] = 1;
      Future<void> pin(Uint8List key, {String device = 'phone'}) =>
          db.transaction((txn) => records(txn)
              .pinIdentity(userId: 'peer', deviceId: device, identityKey: key));
      await pin(original);
      await pin(original);
      // Generation is intentionally absent from the pin's storage key.
      await expectLater(pin(changed), throwsA(isA<E2eeIdentityChanged>()));
      expect(
          await records(db).read('identity_pin', jsonEncode(['peer', 'phone'])),
          original);
      await pin(changed, device: 'second-phone');
      await expectLater(pin(Uint8List(33)), throwsArgumentError);
    });
  });

  group('authenticated operation framing', () {
    final context = E2eeOperationContext(
        opId: 'op',
        channelId: 'channel',
        senderUserId: 'alice',
        senderDeviceId: 'phone',
        generation: 'generation',
        peer: 'bob',
        ttlSec: 30);
    final payload = Uint8List.fromList([0, 8, 255, 240]);

    test('round-trips binary payload without timestamps', () {
      expect(
          context
              .decodeAuthenticatedPlaintext(context.encodePlaintext(payload)),
          payload);
    });

    test('rejects each mismatched context field and version', () {
      final original =
          jsonDecode(utf8.decode(context.encodePlaintext(payload))) as List;
      for (var i = 0; i < 9; i++) {
        final modified = [...original];
        modified[i] = switch (original[i]) {
          int value => value + 1,
          bool value => !value,
          _ => 'changed',
        };
        expect(
            () => context.decodeAuthenticatedPlaintext(
                Uint8List.fromList(utf8.encode(jsonEncode(modified)))),
            throwsA(isA<FormatException>()),
            reason: 'field $i');
      }
    });

    test('rejects malformed shapes, types and noncanonical payloads', () {
      final original =
          jsonDecode(utf8.decode(context.encodePlaintext(payload))) as List;
      final malformed = [
        {},
        [...original, 'extra'],
        original.sublist(1),
        [...original]..[0] = 1.0,
        [...original]..[6] = 0,
        [...original]..[8] = 30.0,
        [...original]..[9] = 'AAj_8A==',
        [...original]..[9] = 1,
      ];
      for (final value in malformed) {
        expect(
            () => context.decodeAuthenticatedPlaintext(
                Uint8List.fromList(utf8.encode(jsonEncode(value)))),
            throwsA(isA<FormatException>()));
      }
      expect(
          () => context.decodeAuthenticatedPlaintext(Uint8List.fromList([255])),
          throwsA(isA<FormatException>()));
    });

    test('invalid key and required context fail before persistence', () {
      expect(
          () => E2eeOperationContext(
              opId: '',
              channelId: 'channel',
              senderUserId: 'alice',
              senderDeviceId: 'phone',
              generation: 'gen'),
          throwsArgumentError);
      expect(
          () => E2eeOperationContext(
              opId: 'op',
              channelId: 'channel',
              senderUserId: 'alice',
              senderDeviceId: 'phone',
              generation: 'gen',
              ttlSec: 0x100000000),
          throwsArgumentError);
    });
  });
}
