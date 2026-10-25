import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_transport/vartalap_transport.dart';

/// The key directory, in process: what each phone published.
class _Directory {
  final published = <String, ({String deviceId, Map<String, dynamic> json})>{};

  Future<void> publish(String userId, String deviceId, SignalStores s) async {
    final upload = (await s.upload()).toJson();
    published[userId] = (deviceId: deviceId, json: upload);
  }

  Map<String, dynamic> _bundle(String userId) {
    final p = published[userId]!;
    return {
      'deviceId': p.deviceId,
      'generation': '7f1c2b3a-0000-4000-8000-00000000000${userId.length % 10}',
      'identityKey': p.json['identityKey'],
      'registrationId': p.json['registrationId'],
      'signedPreKey': p.json['signedPreKey'],
    };
  }

  Future<List<E2eeDeviceBundle>> devices(String userId) async =>
      published.containsKey(userId)
          ? [E2eeDeviceBundle.fromJson(_bundle(userId))]
          : [];

  Future<E2eeKeyClaim> claim(String userId, String deviceId, String g) async {
    final preKeys = published[userId]!.json['preKeys'] as List;
    return E2eeKeyClaim.fromJson(
        {..._bundle(userId), 'preKey': preKeys.isEmpty ? null : preKeys.removeAt(0)});
  }
}

class _Phone {
  final String userId;
  final String deviceId;
  final Database db;
  final E2eeCrypto crypto;

  _Phone._(this.userId, this.deviceId, this.db, this.crypto);

  static Future<_Phone> enrolled(
      String userId, String deviceId, _Directory directory) async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await E2eeRecordStore.createSchema(db);
    final records =
        E2eeRecordStore(db, accountId: userId, wrappingKey: Uint8List(32));
    await db.transaction((t) async {
      final s = SignalStores(records.forTransaction(t));
      await s.createIdentity();
      await s.addPreKeys(5);
    });
    await directory.publish(userId, deviceId, SignalStores(records));
    return _Phone._(
        userId,
        deviceId,
        db,
        E2eeCrypto(
          db: db,
          records: records,
          selfUserId: userId,
          selfDeviceId: deviceId,
          directory: directory.devices,
          claim: directory.claim,
        ));
  }

  /// Seal [text] for [to] and hand back the envelope the server would push.
  Future<pb.Envelope> send(_Phone to, String text, {String opId = 'op-1'}) async {
    final sealed = await crypto.sealDm(
      opId: opId,
      channelId: 'dm-channel',
      peer: to.userId,
      payload: Uint8List.fromList(utf8.encode(text)),
    );
    return pb.Envelope(
      opId: opId,
      channelId: 'dm-channel',
      payload: sealed,
      senderUserId: userId,
      senderDeviceId: deviceId,
      peer: to.userId,
      serverTimestampMs: fixnum.Int64(1),
    );
  }

  Future<String> open(pb.Envelope env) async =>
      utf8.decode((await crypto.open(env)).payload);
}

void main() {
  setUpAll(sqfliteFfiInit);
  late _Directory directory;
  late _Phone alice;
  late _Phone bob;

  setUp(() async {
    directory = _Directory();
    alice = await _Phone.enrolled('a11ce0001', 'phone-a', directory);
    bob = await _Phone.enrolled('b0b000002', 'phone-b', directory);
  });

  test('first message claims a prekey; replies ride the session', () async {
    final first = await alice.send(bob, 'hi bob');
    expect(first.payload.sublist(0, 3), [kSealedMarker, 1, 1]);
    expect(await bob.open(first), 'hi bob');
    final reply = await bob.send(alice, 'hi alice', opId: 'op-2');
    expect(reply.payload[2], 2, reason: 'bob learned the session from alice');
    expect(await alice.open(reply), 'hi alice');
    expect(utf8.decode(first.payload, allowMalformed: true),
        isNot(contains('hi bob')));
  });

  test('a ciphertext moved onto another op, channel or sender is refused and '
      'leaves the ratchet where it was', () async {
    final env = await alice.send(bob, 'hi');
    for (final moved in [
      pb.Envelope.fromBuffer(env.writeToBuffer())..channelId = 'other-channel',
      pb.Envelope.fromBuffer(env.writeToBuffer())..opId = 'op-9',
      pb.Envelope.fromBuffer(env.writeToBuffer())..peer = 'c0ffee003',
      pb.Envelope.fromBuffer(env.writeToBuffer())..ephemeral = true,
    ]) {
      await expectLater(bob.open(moved), throwsA(isA<E2eeUndecryptable>()));
    }
    expect(await bob.open(env), 'hi');
  });

  test('a stored op opens again from staging until applied', () async {
    final env = await alice.send(bob, 'once');
    expect(await bob.open(env), 'once');
    expect(await bob.open(env), 'once', reason: 'no second ratchet step');
    await bob.crypto.applied(env);
    await expectLater(bob.open(env), throwsA(anything),
        reason: 'applied: a replay is a duplicate now');
  });

  test('plaintext is refused; a peer without keys waits; typing needs a '
      'session', () async {
    final plain = pb.Envelope(
      opId: 'op-1',
      channelId: 'dm-channel',
      payload: pb.ChatPayload(version: 1, body: 'hi').writeToBuffer(),
      senderUserId: alice.userId,
      senderDeviceId: alice.deviceId,
    );
    await expectLater(bob.open(plain), throwsA(isA<E2eeUndecryptable>()));
    await expectLater(
        alice.crypto.sealDm(
            opId: 'op-2',
            channelId: 'dm',
            peer: 'c0ffee003',
            payload: Uint8List(1)),
        throwsA(isA<E2eeNoKeys>()));
    expect(
        await alice.crypto.sealDm(
            opId: 'op-3',
            channelId: 'dm',
            peer: bob.userId,
            payload: Uint8List(1),
            ephemeral: true,
            onlyIfSession: true),
        isNull);
  });

  group('groups (Sender Keys, decision 188)', () {
    late _Phone carol;
    setUp(() async {
      carol = await _Phone.enrolled('c0ffee003', 'phone-c', directory);
    });

    /// Alice seals for [members]; the key hand-outs come back as the
    /// envelopes the server would push on each member's 1:1 channel.
    Future<(pb.Envelope, Map<String, pb.Envelope>)> groupSend(
        String text, Set<String> members,
        {String opId = 'g-op', bool onlyIfDistributed = false}) async {
      final keys = <String, pb.Envelope>{};
      var n = 0;
      final sealed = await alice.crypto.sealGroup(
        opId: opId,
        channelId: 'g-1',
        members: members,
        payload: Uint8List.fromList(utf8.encode(text)),
        dmChannel: (m) => 'dm-$m',
        newOpId: () => '$opId-key-${n++}',
        onlyIfDistributed: onlyIfDistributed,
        sendKey: (member, channel, keyOpId, bytes) async {
          keys[member] = pb.Envelope(
            opId: keyOpId,
            channelId: channel,
            payload: bytes,
            senderUserId: alice.userId,
            senderDeviceId: alice.deviceId,
            peer: member,
          );
        },
      );
      return (
        pb.Envelope(
          opId: opId,
          channelId: 'g-1',
          payload: sealed,
          senderUserId: alice.userId,
          senderDeviceId: alice.deviceId,
        ),
        keys
      );
    }

    test('one ciphertext opens for every member; a key re-delivered is '
        'harmless', () async {
      final (message, keys) = await groupSend('hello all', {bob.userId, carol.userId});
      expect(keys.keys, unorderedEquals([bob.userId, carol.userId]));
      expect(message.payload.sublist(0, 3), [kSealedMarker, 1, 3]);
      for (final p in [bob, carol]) {
        expect((await p.crypto.open(keys[p.userId]!)).payload, isEmpty,
            reason: 'a key hand-out has nothing to apply');
        expect((await p.crypto.open(keys[p.userId]!)).payload, isEmpty,
            reason: 'and opens empty again, without a ratchet step');
        expect(await p.open(message), 'hello all');
      }
      final (second, more) = await groupSend('again', {bob.userId, carol.userId},
          opId: 'g-op-2');
      expect(more, isEmpty, reason: 'every member already holds the key');
      expect(await carol.open(second), 'again');
    });

    test('a member who left cannot read on; the rest get a fresh key',
        () async {
      final (first, keys) = await groupSend('before', {bob.userId, carol.userId});
      for (final p in [bob, carol]) {
        await p.crypto.open(keys[p.userId]!);
        await p.open(first);
      }
      final (after, rotated) =
          await groupSend('after carol left', {bob.userId}, opId: 'g-op-2');
      expect(rotated.keys, [bob.userId]);
      await bob.crypto.open(rotated[bob.userId]!);
      expect(await bob.open(after), 'after carol left');
      await expectLater(carol.open(after), throwsA(anything));
    });

    test('typing never hands out a key', () async {
      final (typing, keys) = await groupSend('typing', {bob.userId},
          onlyIfDistributed: true);
      expect([typing.payload, keys], [isEmpty, isEmpty]);
    });
  });

  test('a contact on a new phone is reached there and reported once (184)',
      () async {
    await bob.open(await alice.send(bob, 'old phone'));
    final changes = <String>[];
    final sub = bob.crypto.identityChanges.listen(changes.add);
    final newPhone = await _Phone.enrolled('a11ce0001', 'phone-a2', directory);
    expect(await bob.open(await newPhone.send(bob, 'new phone', opId: 'op-4')),
        'new phone');
    // Bob now writes to the new phone, not the old one.
    expect(await newPhone.open(await bob.send(newPhone, 'got it', opId: 'op-5')),
        'got it');
    await Future<void>.delayed(Duration.zero);
    expect(changes, ['a11ce0001']);
    await sub.cancel();
  });
}
