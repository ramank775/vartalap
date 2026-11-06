/// Decision 222: a secure message's secret, sealed on its own.
library vartalap.services.secure_message_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart';

void main() {
  test('screen lock: a fresh random key travels beside the box', () {
    final a = sealSecret('OTP 424242');
    final b = sealSecret('OTP 424242');
    expect(a.key, hasLength(32));
    expect(a.box.sublist(0, 2), [1, 1], reason: 'version 1, screen lock');
    expect(a.box, hasLength(2 + 12 + 'OTP 424242'.length + 16));
    expect(a.box, isNot(b.box), reason: 'a fresh key and nonce each time');
    expect(secureUnlockOf(a.box), SecureUnlock.screenLock);
    expect(openSecret(a.box, key: a.key), 'OTP 424242');
  });

  test('password: the key is never sent; only the password opens it', () {
    final s = sealSecret('wifi: hunter2', password: 'blue door');
    expect(s.key, isNull);
    expect(s.box.sublist(0, 2), [1, 2], reason: 'version 1, password');
    expect(s.box, hasLength(2 + 16 + 12 + 'wifi: hunter2'.length + 16),
        reason: 'a 16-byte salt after the header');
    expect(secureUnlockOf(s.box), SecureUnlock.password);
    expect(openSecret(s.box, password: 'blue door'), 'wifi: hunter2');
    expect(() => openSecret(s.box, password: 'red door'),
        throwsA(isA<SecretLocked>()));
  });

  test('a changed box, header or key does not open', () {
    final s = sealSecret('1234');
    for (final i in [1, 5, s.box.length - 1]) {
      final changed = [...s.box]..[i] ^= 1;
      expect(
          () => openSecret(changed, key: s.key),
          i == 1
              ? throwsA(anything) // the header names another unlock
              : throwsA(isA<SecretLocked>()));
    }
    final wrongKey = [...s.key!]..[0] ^= 1;
    expect(() => openSecret(s.box, key: wrongKey),
        throwsA(isA<SecretLocked>()));
    expect(() => secureUnlockOf([2, 1]), throwsFormatException,
        reason: 'a version this build cannot read');
  });
}
