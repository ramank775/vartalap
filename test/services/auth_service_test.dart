/// AuthService is a thin wrapper: it persists OTP-verify output to
/// secure storage, restores it on boot, and drives the
/// authStateChange stream on login/logout. These tests exercise
/// exactly those behaviors against in-memory fakes.
library vartalap.services.auth_service_test;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  group('AuthService', () {
    test('init rehydrates a persisted session via AuthClient.restoreSession',
        () async {
      final storage = _InMemoryStorage(
        initial: {
          'v3.accesskey': 'sk_persisted_abc',
          'v3.user_id': 'a3f2e8c5d',
        },
      );
      final client = _FakeAuthClient();
      final auth = AuthService(client: client, storage: storage);

      expect(auth.isLoggedIn, isFalse); // pre-init
      await auth.init();
      expect(auth.isLoggedIn, isTrue);
      expect(client.currentAccesskey, 'sk_persisted_abc');
      expect(client.currentUserId, 'a3f2e8c5d');

      await auth.dispose();
    });

    test('init is a no-op when no session is persisted', () async {
      final storage = _InMemoryStorage();
      final client = _FakeAuthClient();
      final auth = AuthService(client: client, storage: storage);

      await auth.init();
      expect(auth.isLoggedIn, isFalse);
      expect(client.currentAccesskey, isNull);

      await auth.dispose();
    });

    test('verifyOtp persists the session and emits true on authStateChange',
        () async {
      // Seed an in-flight OTP session so verifyOtp has a sessionId to
      // forward (AuthService restores this from storage during init).
      final storage = _InMemoryStorage(
        initial: {
          'v3.otpSessionId': 'otp_session_abc',
          'v3.otpPhone': '+911234567890',
        },
      );
      final client = _FakeAuthClient()
        ..verifyResult = const OtpVerifyResult(
          accesskey: 'sk_fresh_xyz',
          refreshToken: 'rt_xyz',
          userId: 'b7c1d2e3f',
          accesskeyTtl: Duration(days: 30),
          refreshTokenTtl: Duration(days: 90),
          isNewUser: false,
        );
      final auth = AuthService(client: client, storage: storage);
      await auth.init();

      final emissions = <bool>[];
      final sub = auth.authStateChange.listen(emissions.add);

      final result = await auth.verifyOtp('+911234567890', '123456');
      expect(result.userId, 'b7c1d2e3f');
      expect(auth.isLoggedIn, isTrue);

      // Session hit secure storage.
      expect(await storage.read(key: 'v3.accesskey'), 'sk_fresh_xyz');
      expect(await storage.read(key: 'v3.user_id'), 'b7c1d2e3f');

      // AuthClient session restored in-memory (transport adapters read
      // this immediately — no app restart needed).
      expect(client.currentAccesskey, 'sk_fresh_xyz');
      expect(client.currentUserId, 'b7c1d2e3f');

      // authStateChange fired with true.
      await _pumpEventQueue();
      expect(emissions, [true]);

      await sub.cancel();
      await auth.dispose();
    });

    test('logout clears secure storage, AuthClient, and emits false',
        () async {
      final storage = _InMemoryStorage(
        initial: {
          'v3.accesskey': 'sk_live',
          'v3.user_id': 'c9d8e7f65',
        },
      );
      final client = _FakeAuthClient();
      final auth = AuthService(client: client, storage: storage);
      await auth.init();
      expect(auth.isLoggedIn, isTrue);

      final emissions = <bool>[];
      final sub = auth.authStateChange.listen(emissions.add);

      await auth.logout();

      expect(client.revokeCallCount, 1);
      expect(auth.isLoggedIn, isFalse);
      expect(client.currentAccesskey, isNull);
      expect(await storage.read(key: 'v3.accesskey'), isNull);
      expect(await storage.read(key: 'v3.user_id'), isNull);

      await _pumpEventQueue();
      expect(emissions, [false]);

      await sub.cancel();
      await auth.dispose();
    });

    test('logout proceeds locally even if revokeSession throws', () async {
      final storage = _InMemoryStorage(
        initial: {
          'v3.accesskey': 'sk_live',
          'v3.user_id': 'deadbeef1',
        },
      );
      final client = _FakeAuthClient()..revokeThrows = true;
      final auth = AuthService(client: client, storage: storage);
      await auth.init();
      expect(auth.isLoggedIn, isTrue);

      // Must not throw — offline logout is still a valid user intent.
      await auth.logout();

      expect(auth.isLoggedIn, isFalse);
      expect(await storage.read(key: 'v3.accesskey'), isNull);

      await auth.dispose();
    });
  });
}

Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

/// In-memory FlutterSecureStorage stand-in. Implements just the
/// methods AuthService touches; everything else throws.
class _InMemoryStorage implements FlutterSecureStorage {
  final Map<String, String> _data;

  _InMemoryStorage({Map<String, String>? initial})
      : _data = {...?initial};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      '_InMemoryStorage.${invocation.memberName} — not implemented for tests',
    );
  }
}

/// Subclass of the real [AuthClient] that overrides the method bodies
/// AuthService actually calls (`verifyOtp`, `revokeSession`) with
/// in-memory fakes. The genuine `AuthClient.restoreSession` /
/// `clearSession` / `currentAccesskey` / `currentUserId` paths remain
/// live so we're exercising the real in-memory session state machine.
class _FakeAuthClient extends AuthClient {
  OtpVerifyResult? verifyResult;
  bool revokeThrows = false;
  int revokeCallCount = 0;

  _FakeAuthClient()
      : super(baseUrl: Uri.parse('https://example.invalid'));

  @override
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String code,
    required String sessionId,
  }) async {
    final r = verifyResult;
    if (r == null) {
      throw StateError('verifyResult not configured');
    }
    // Mirror the production behaviour: a successful verifyOtp seeds
    // the in-memory session so transports can read it immediately.
    restoreSession(
      accesskey: r.accesskey,
      userId: r.userId,
      refreshToken: r.refreshToken,
    );
    return r;
  }

  @override
  Future<void> revokeSession() async {
    revokeCallCount += 1;
    if (revokeThrows) {
      throw StateError('simulated revoke network error');
    }
  }
}
