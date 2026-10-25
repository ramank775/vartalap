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

/// The peer has no published phone yet (never opened the app since
/// signing up, or signed out everywhere): the op waits and retries.
class E2eeNoKeys implements Exception {
  final String userId;
  const E2eeNoKeys(this.userId);

  @override
  String toString() => 'No published device keys for $userId';
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
    Future<void> Function(Transaction txn, Uint8List sealed)? persist,
  }) =>
      _serial(() async {
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
          final claim = await _claim(
              peer, devices.first.deviceId, devices.first.generation);
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
          final message = await SessionCipher(
                  stores, stores, stores, stores, address)
              .encrypt(context.encodePlaintext(payload));
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
  Future<Uint8List> open(pb.Envelope env) => _serial(() async {
        final staged = await _records.read('inbox', _inboxKey(env));
        if (staged != null) return staged;
        final p = env.payload;
        if (p.length < 4 || p[0] != kSealedMarker || p[1] != _version) {
          throw const FormatException('Not an end-to-end encrypted payload');
        }
        final kind = p[2];
        final body = Uint8List.fromList(p.sublist(3));
        final sender = signalAddress(env.senderUserId, env.senderDeviceId);
        final context = E2eeOperationContext(
          opId: env.opId,
          channelId: env.channelId,
          senderUserId: env.senderUserId,
          senderDeviceId: env.senderDeviceId,
          ephemeral: env.ephemeral,
          peer: env.peer,
          ttlSec: env.ttlSec,
        );
        final (payload, changed) = await _db.transaction((txn) async {
          final records = _records.forTransaction(txn);
          final stores = SignalStores(records);
          final cipher = SessionCipher(stores, stores, stores, stores, sender);
          final plain = switch (kind) {
            _kindPreKey => await cipher.decrypt(PreKeySignalMessage(body)),
            _kindSignal => await cipher
                .decryptFromSignal(SignalMessage.fromSerialized(body)),
            _ => throw FormatException('Unknown sealed payload kind $kind'),
          };
          final payload = context.decodeAuthenticatedPlaintext(plain);
          // A message from a phone proves it is that user's current one.
          await records.write(
              'peer_device', env.senderUserId, utf8.encode(env.senderDeviceId));
          if (!env.ephemeral) {
            await records.write('inbox', _inboxKey(env), payload);
          }
          return (payload, stores.changedIdentities);
        });
        changed.forEach(_identityChanges.add);
        return payload;
      });

  /// The receiver applied [env]: its staged payload can go.
  Future<void> applied(pb.Envelope env) => _db.transaction(
      (txn) => _records.forTransaction(txn).remove('inbox', _inboxKey(env)));
}
