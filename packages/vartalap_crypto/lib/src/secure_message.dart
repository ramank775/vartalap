import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'e2ee.dart' show chaCha20Poly1305;

/// Decision 222: how a secure message's secret is opened.
///
/// [screenLock]: a fresh random key travels beside the box, inside the
/// end-to-end encrypted payload (`ChatPayload.secure_key`); the app shows
/// the secret only after the phone's own screen lock. [password]: the key
/// is Argon2id of a password the sender tells the receiver another way,
/// never sent; a forgotten password cannot be helped.
enum SecureUnlock { screenLock, password }

/// Thrown by [openSecret] for a wrong password (or a box or key that was
/// changed): the AEAD tag does not verify.
class SecretLocked implements Exception {
  const SecretLocked();
}

const int _version = 1;
const int _saltLength = 16;
const int _nonceLength = 12;

/// Argon2id with the box's version 1 parameters: 16 MiB, 3 passes, one
/// lane, a 32-byte key. Slow on purpose (about a second on a phone); call
/// it off the UI isolate.
Uint8List _passwordKey(String password, Uint8List salt) {
  final out = Uint8List(32);
  (Argon2BytesGenerator()
        ..init(Argon2Parameters(Argon2Parameters.ARGON2_id, salt,
            desiredKeyLength: 32, iterations: 3, memoryPowerOf2: 14)))
      .deriveKey(Uint8List.fromList(utf8.encode(password)), 0, out, 0);
  return out;
}

Uint8List _random(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

/// Seal [secret] for a secure message: with a [password] (the
/// [SecureUnlock.password] way), else a fresh random key, returned as
/// [key] to travel with the box (the [SecureUnlock.screenLock] way).
///
/// The box is one unit, so a forward can copy it unchanged and a
/// traceability hash can be taken over it: version (1), unlock (1 screen
/// lock, 2 password), the password's 16-byte salt, a 12-byte nonce, then
/// the ChaCha20-Poly1305 ciphertext and tag, the bytes before the nonce
/// authenticated with it.
({Uint8List box, Uint8List? key}) sealSecret(String secret,
    {String? password}) {
  final salt = password == null ? null : _random(_saltLength);
  final key =
      password == null ? _random(32) : _passwordKey(password, salt!);
  final header =
      Uint8List.fromList([_version, password == null ? 1 : 2, ...?salt]);
  final nonce = _random(_nonceLength);
  final sealed = chaCha20Poly1305(
      true, key, nonce, header, Uint8List.fromList(utf8.encode(secret)));
  return (
    box: Uint8List.fromList([...header, ...nonce, ...sealed]),
    key: password == null ? key : null,
  );
}

/// How [box] opens. Throws [FormatException] for one this build cannot
/// read.
SecureUnlock secureUnlockOf(List<int> box) {
  if (box.length < 2 || box[0] != _version || box[1] < 1 || box[1] > 2) {
    throw const FormatException('Not a secure message this app can open');
  }
  return box[1] == 1 ? SecureUnlock.screenLock : SecureUnlock.password;
}

/// The secret in [box], with its [key] (screen lock) or the [password].
/// Throws [SecretLocked] for a wrong password or a changed box, and
/// [FormatException] for a malformed one. A password box runs Argon2id:
/// call it off the UI isolate.
String openSecret(List<int> box, {List<int>? key, String? password}) {
  final unlock = secureUnlockOf(box);
  final bytes = Uint8List.fromList(box);
  final headerLength = unlock == SecureUnlock.password ? 2 + _saltLength : 2;
  if (bytes.length < headerLength + _nonceLength + 16) {
    throw const FormatException('Secure message too short');
  }
  final header = bytes.sublist(0, headerLength);
  final Uint8List k;
  if (unlock == SecureUnlock.password) {
    if (password == null) throw ArgumentError('A password box needs one');
    k = _passwordKey(password, bytes.sublist(2, headerLength));
  } else {
    if (key == null || key.length != 32) throw ArgumentError('No key');
    k = Uint8List.fromList(key);
  }
  try {
    return utf8.decode(chaCha20Poly1305(
        false,
        k,
        bytes.sublist(headerLength, headerLength + _nonceLength),
        header,
        bytes.sublist(headerLength + _nonceLength)));
  } on InvalidCipherTextException {
    throw const SecretLocked();
  }
}
