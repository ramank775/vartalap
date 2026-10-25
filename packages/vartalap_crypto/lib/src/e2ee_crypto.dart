import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_transport/vartalap_transport.dart';

import 'e2ee.dart';
import 'signal_store.dart';

/// Decision 188 framing of an encrypted `Envelope.payload`: this marker, a
/// version byte, a kind byte, then the Signal ciphertext. The server only
/// ever sees these bytes; its own events keep their 0x53 marker.
const int kSealedMarker = 0x45;
const int _version = 1;
const int _kindPreKey = 1; // first 1:1 message to a phone (X3DH)
const int _kindSignal = 2; // 1:1 message on an established session
const int _kindGroup = 3; // a group message, one Sender Key ciphertext

/// First byte of a pairwise plaintext that hands over a Sender Key rather
/// than carrying a ChatPayload (whose first byte is always its `version`
/// tag, 0x08): JSON `{"g": group channel id, "k": base64 distribution}`.
const int _groupKeyMarker = 0x4B;

/// The peer has no published phone yet (never opened the app since
/// signing up, or signed out everywhere): the op waits and retries.
class E2eeNoKeys implements Exception {
  final String userId;
  const E2eeNoKeys(this.userId);

  @override
  String toString() => 'No published device keys for $userId';
}

/// A sealed op that will never open here (a broken or missing session, a
/// group key that never came, a forged or moved ciphertext): the receiver
/// shows "Waiting for this message" and asks the sender to re-send it.
class E2eeUndecryptable implements Exception {
  final Object cause;
  const E2eeUndecryptable(this.cause);

  @override
  String toString() => 'Cannot decrypt: $cause';
}

/// The key directory, as `AuthClient` serves it (AUTH_CONTRACT §17) or the
/// mock server answers in process.
typedef DeviceDirectory = Future<List<E2eeDeviceBundle>> Function(
    String userId);
typedef DeviceKeyClaim = Future<E2eeKeyClaim> Function(
    String userId, String deviceId, String generation);

/// Seals this phone's ops and opens what arrives, over [SignalStores] in
/// the account database. Every ratchet step commits in one transaction
/// with what depends on it: the sealed bytes on the outbound row, the
/// opened payload staged for the receiver. Calls run one at a time.
class E2eeCrypto {
  final Database _db;
  final E2eeRecordStore _records;
  final String selfUserId;
  final String selfDeviceId;
  final DeviceDirectory _directory;
  final DeviceKeyClaim _claim;

  final _identityChanges = StreamController<String>.broadcast();

  /// Users whose security code just changed (decision 184): their chats
  /// get a "security code changed" line.
  Stream<String> get identityChanges => _identityChanges.stream;

  Future<void> _tail = Future.value();

  E2eeCrypto({
    required Database db,
    required E2eeRecordStore records,
    required this.selfUserId,
    required this.selfDeviceId,
    required DeviceDirectory directory,
    required DeviceKeyClaim claim,
  })  : _db = db,
        _records = records,
        _directory = directory,
        _claim = claim;

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> close() => _identityChanges.close();

  /// Seal [payload] for the 1:1 [peer]. [persist] runs in the ratchet's
  /// transaction, so the outbound row keeps exactly these bytes for its
  /// retries. With [onlyIfSession] (typing) nothing is fetched or claimed:
  /// null when there is no session yet.
  Future<Uint8List?> sealDm({
    required String opId,
    required String channelId,
    required String peer,
    required Uint8List payload,
    bool ephemeral = false,
    int ttlSec = 0,
    bool onlyIfSession = false,
    String retryOf = '',
    Future<void> Function(Transaction txn, Uint8List sealed)? persist,
  }) =>
      _serial(() => _sealPairwise(
            opId: opId,
            channelId: channelId,
            peer: peer,
            payload: payload,
            ephemeral: ephemeral,
            ttlSec: ttlSec,
            onlyIfSession: onlyIfSession,
            retryOf: retryOf,
            persist: persist,
          ));

  Future<Uint8List?> _sealPairwise({
    required String opId,
    required String channelId,
    required String peer,
    required Uint8List payload,
    bool ephemeral = false,
    int ttlSec = 0,
    bool onlyIfSession = false,
    String retryOf = '',
    Future<void> Function(Transaction txn, Uint8List sealed)? persist,
  }) async {
    final known = await _records.read('peer_device', peer);
    var device = known == null ? null : utf8.decode(known);
    PreKeyBundle? bundle;
    if (device == null ||
        !await SignalStores(_records)
            .containsSession(signalAddress(peer, device))) {
      if (onlyIfSession) return null;
      // ponytail: one phone per account (183), so its first device is
      // the one; linked devices mean a ciphertext per device here.
      final devices = await _directory(peer);
      if (devices.isEmpty) throw E2eeNoKeys(peer);
      final claim =
          await _claim(peer, devices.first.deviceId, devices.first.generation);
      device = claim.bundle.deviceId;
      bundle = _bundleOf(claim);
    }
    final address = signalAddress(peer, device);
    final context = E2eeOperationContext(
      opId: opId,
      channelId: channelId,
      senderUserId: selfUserId,
      senderDeviceId: selfDeviceId,
      ephemeral: ephemeral,
      peer: peer,
      ttlSec: ttlSec,
    );
    final (sealed, changed) = await _db.transaction((txn) async {
      final records = _records.forTransaction(txn);
      final stores = SignalStores(records);
      if (bundle != null) {
        await SessionBuilder(stores, stores, stores, stores, address)
            .processPreKeyBundle(bundle);
        await records.write('peer_device', peer, utf8.encode(device!));
      }
      final message =
          await SessionCipher(stores, stores, stores, stores, address)
              .encrypt(context.encodePlaintext(payload, retryOf: retryOf));
      final sealed = Uint8List.fromList([
        kSealedMarker,
        _version,
        message.getType() == CiphertextMessage.prekeyType
            ? _kindPreKey
            : _kindSignal,
        ...message.serialize(),
      ]);
      await persist?.call(txn, sealed);
      return (sealed, stores.changedIdentities);
    });
    changed.forEach(_identityChanges.add);
    return sealed;
  }

  /// Seal [payload] for the group [channelId]: one Sender Key ciphertext
  /// that every member opens (decision 188), stored once by the server.
  /// A member whose phone lacks this phone's current sender key gets it
  /// first, sealed pairwise as an op on their 1:1 channel ([dmChannel])
  /// and handed to [sendKey] to go out ahead of this one. A member gone
  /// since the last hand-out rotates the key, so they cannot read on.
  /// A member without keys yet is skipped; their phone asks for the key
  /// when a message will not open. With [onlyIfDistributed] (typing)
  /// nothing is handed out: null unless every member already has it.
  Future<Uint8List?> sealGroup({
    required String opId,
    required String channelId,
    required Set<String> members,
    required Uint8List payload,
    required String Function(String member) dmChannel,
    required String Function() newOpId,
    required Future<void> Function(
            String member, String channelId, String opId, Uint8List sealed)
        sendKey,
    bool ephemeral = false,
    int ttlSec = 0,
    bool onlyIfDistributed = false,
    String retryOf = '',
    Future<void> Function(Transaction txn, Uint8List sealed)? persist,
  }) =>
      _serial(() async {
        final self =
            SenderKeyName(channelId, signalAddress(selfUserId, selfDeviceId));
        final held = await _records.read('group_key_holders', channelId);
        var holders = held == null
            ? <String>{}
            : (jsonDecode(utf8.decode(held)) as List).cast<String>().toSet();
        if (holders.difference(members).isNotEmpty) {
          // Someone left: a fresh key only the remaining members get.
          await _db.transaction((txn) =>
              SignalStores(_records.forTransaction(txn))
                  .storeSenderKey(self, SenderKeyRecord()));
          holders = {};
        }
        final missing = members.difference(holders);
        if (onlyIfDistributed && missing.isNotEmpty) return null;
        for (final member in missing) {
          final distribution = await _db.transaction((txn) =>
              GroupSessionBuilder(SignalStores(_records.forTransaction(txn)))
                  .create(self));
          final keyOpId = newOpId();
          final keyChannel = dmChannel(member);
          try {
            final sealed = await _sealPairwise(
              opId: keyOpId,
              channelId: keyChannel,
              peer: member,
              payload: Uint8List.fromList([
                _groupKeyMarker,
                ...utf8.encode(jsonEncode({
                  'g': channelId,
                  'k': base64.encode(distribution.serialize()),
                })),
              ]),
            );
            await sendKey(member, keyChannel, keyOpId, sealed!);
          } on E2eeNoKeys {
            continue;
          }
          holders.add(member);
        }
        final context = E2eeOperationContext(
          opId: opId,
          channelId: channelId,
          senderUserId: selfUserId,
          senderDeviceId: selfDeviceId,
          ephemeral: ephemeral,
          ttlSec: ttlSec,
        );
        return _db.transaction((txn) async {
          final records = _records.forTransaction(txn);
          await records.write('group_key_holders', channelId,
              utf8.encode(jsonEncode(holders.toList()..sort())));
          final ciphertext = await GroupCipher(SignalStores(records), self)
              .encrypt(context.encodePlaintext(payload, retryOf: retryOf));
          final sealed = Uint8List.fromList(
              [kSealedMarker, _version, _kindGroup, ...ciphertext]);
          await persist?.call(txn, sealed);
          return sealed;
        });
      });

  /// A member's phone asked again (it could not open one of ours): hand it
  /// the current key with the next group send.
  Future<void> forgetKeyHolder(String channelId, String member) =>
      _serial(() async {
        final held = await _records.read('group_key_holders', channelId);
        if (held == null) return;
        final holders = (jsonDecode(utf8.decode(held)) as List).cast<String>()
          ..remove(member);
        await _db.transaction((txn) => _records.forTransaction(txn).write(
            'group_key_holders', channelId, utf8.encode(jsonEncode(holders))));
      });

  static PreKeyBundle _bundleOf(E2eeKeyClaim claim) {
    Uint8List bytes(String b64) => base64.decode(b64);
    final b = claim.bundle;
    final preKey = claim.preKey;
    return PreKeyBundle(
      b.registrationId,
      1,
      preKey?.id,
      preKey == null ? null : Curve.decodePoint(bytes(preKey.publicKey), 0),
      b.signedPreKey.id,
      Curve.decodePoint(bytes(b.signedPreKey.publicKey), 0),
      bytes(b.signedPreKey.signature),
      IdentityKey.fromBytes(bytes(b.identityKey), 0),
    );
  }

  static String _inboxKey(pb.Envelope env) =>
      '${env.channelId}/${env.senderUserId}/${env.senderDeviceId}/${env.opId}';

  /// The ChatPayload bytes sealed in [env]. Throws on anything that is not
  /// a sealed payload or does not authenticate against the envelope's own
  /// op, channel and sender; the transaction then rolls back every library
  /// write. A stored op's payload is staged until [applied], so a crash or
  /// a re-delivery never needs a second ratchet step.
  ///
  /// A pairwise op that hands over a group key is processed here and opens
  /// to an empty payload: there is nothing for the receiver to apply, and
  /// a re-delivery opens empty again without touching the ratchet.
  /// Throws [E2eeUndecryptable] for an op that will never open here; any
  /// other failure (the database) may pass, so the op stays unhandled.
  Future<({Uint8List payload, String retryOf})> open(pb.Envelope env) =>
      _serial(() async {
        final context = E2eeOperationContext(
          opId: env.opId,
          channelId: env.channelId,
          senderUserId: env.senderUserId,
          senderDeviceId: env.senderDeviceId,
          ephemeral: env.ephemeral,
          peer: env.peer,
          ttlSec: env.ttlSec,
        );
        if (await _records.read('keys_taken', _inboxKey(env)) != null) {
          return (payload: Uint8List(0), retryOf: '');
        }
        final staged = await _records.read('inbox', _inboxKey(env));
        if (staged != null) return context.decodeAuthenticated(staged);
        try {
          final (opened, changed) = await _open(env, context);
          changed.forEach(_identityChanges.add);
          return opened;
        } on DatabaseException {
          rethrow;
        } catch (e) {
          throw E2eeUndecryptable(e);
        }
      });

  Future<(({Uint8List payload, String retryOf}), Set<String>)> _open(
      pb.Envelope env, E2eeOperationContext context) async {
    final p = env.payload;
    if (p.length < 4 || p[0] != kSealedMarker || p[1] != _version) {
      throw const FormatException('Not an end-to-end encrypted payload');
    }
    final kind = p[2];
    final body = Uint8List.fromList(p.sublist(3));
    final sender = signalAddress(env.senderUserId, env.senderDeviceId);
    return _db.transaction((txn) async {
      final records = _records.forTransaction(txn);
      final stores = SignalStores(records);
      final cipher = SessionCipher(stores, stores, stores, stores, sender);
      final plain = switch (kind) {
        _kindPreKey => await cipher.decrypt(PreKeySignalMessage(body)),
        _kindSignal =>
          await cipher.decryptFromSignal(SignalMessage.fromSerialized(body)),
        _kindGroup =>
          await GroupCipher(stores, SenderKeyName(env.channelId, sender))
              .decrypt(body),
        _ => throw FormatException('Unknown sealed payload kind $kind'),
      };
      final opened = context.decodeAuthenticated(plain);
      final payload = opened.payload;
      if (kind != _kindGroup) {
        // A message from a phone proves it is that user's current one.
        await records.write(
            'peer_device', env.senderUserId, utf8.encode(env.senderDeviceId));
      }
      if (kind != _kindGroup &&
          payload.isNotEmpty &&
          payload[0] == _groupKeyMarker) {
        final key =
            jsonDecode(utf8.decode(payload.sublist(1))) as Map<String, dynamic>;
        await GroupSessionBuilder(stores).process(
            SenderKeyName(key['g'] as String, sender),
            SenderKeyDistributionMessageWrapper.fromSerialized(
                base64.decode(key['k'] as String)));
        await records.write('keys_taken', _inboxKey(env), Uint8List(1));
        return ((payload: Uint8List(0), retryOf: ''), stores.changedIdentities);
      }
      if (!env.ephemeral) {
        await records.write('inbox', _inboxKey(env), plain);
      }
      return (opened, stores.changedIdentities);
    });
  }

  /// Logged with each sealed op, inside its transaction ([txn]), so a
  /// recipient whose phone cannot open it can have it once more (decision
  /// 188) for as long as the server keeps it. Plaintext, so in the
  /// encrypted records.
  Future<void> rememberSent(
          Transaction txn, String opId, Map<String, Object?> op) =>
      _records.forTransaction(txn).write('sent', opId,
          utf8.encode(jsonEncode({...op, 'at': DateTime.now().millisecondsSinceEpoch})));

  /// The logged op to re-send for [opId], at most once: null when unknown
  /// (never logged, or trimmed) or re-sent before.
  Future<Map<String, dynamic>?> takeForResend(String opId) =>
      _serial(() => _db.transaction((txn) async {
            final records = _records.forTransaction(txn);
            final bytes = await records.read('sent', opId);
            if (bytes == null) return null;
            final op = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
            if (op['resent'] == true) return null;
            await records.write(
                'sent', opId, utf8.encode(jsonEncode({...op, 'resent': true})));
            return op;
          }));

  /// Drop logged ops sent before [cutoffMs] (the server's own retention).
  Future<void> forgetSentBefore(int cutoffMs) => _serial(() async {
        final stale = <String>[];
        for (final opId in await _records.keys('sent')) {
          final bytes = await _records.read('sent', opId);
          final at = bytes == null
              ? 0
              : (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['at'];
          if (at is! int || at < cutoffMs) stale.add(opId);
        }
        if (stale.isEmpty) return;
        await _db.transaction((txn) async {
          final records = _records.forTransaction(txn);
          for (final opId in stale) {
            await records.remove('sent', opId);
          }
        });
      });

  /// [userId]'s phone could not open what this one sent: start a fresh
  /// session with [deviceId] (its current phone) on the next send.
  Future<void> resetSession(String userId, String deviceId) =>
      _serial(() => _db.transaction((txn) async {
            final records = _records.forTransaction(txn);
            await SignalStores(records)
                .deleteSession(signalAddress(userId, deviceId));
            await records.write('peer_device', userId, utf8.encode(deviceId));
          }));

  /// The receiver applied [env]: its staged payload can go.
  Future<void> applied(pb.Envelope env) => _db.transaction(
      (txn) => _records.forTransaction(txn).remove('inbox', _inboxKey(env)));
}
