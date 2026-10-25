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
  test('missing account DB discards an orphan session before restoring it',
      () async {
    final storage = _InMemoryStorage(initial: {
      'v3.accesskey': 'old-access',
      'v3.refreshToken': 'old-refresh',
      'v3.user_id': 'a11ce0001',
      'v3.username': 'old_name',
      'v3.otpSessionId': 'old-otp',
      'v3.e2ee.wrappingKey.a11ce0001': 'old-key',
    });
    final client = _FakeAuthClient();
    final auth = AuthService(client: client, storage: storage);
    await auth.init(hasAccountDatabase: (id) async {
      expect(id, 'a11ce0001');
      return false;
    });
    expect(auth.isLoggedIn, isFalse);
    expect(auth.username, isNull);
    expect(client.currentRefreshToken, isNull);
    expect(await storage.read(key: 'v3.otpSessionId'), isNull);
    expect(client.revokeCallCount, 0,
        reason: 'startup must not need a network');
    await auth.dispose();
  });

  test('an existing account DB keeps its restored session', () async {
    final auth = AuthService(
        client: _FakeAuthClient(),
        storage: _InMemoryStorage(initial: {
          'v3.accesskey': 'old-access',
          'v3.user_id': 'a11ce0001'
        }));
    await auth.init(hasAccountDatabase: (_) async => true);
    expect(auth.currentUserId, 'a11ce0001');
    expect(auth.isLoggedIn, isTrue);
    await auth.dispose();
  });
  group('AuthService', () {
    test('failed account startup never publishes or retains a login', () async {
      final storage = _InMemoryStorage(initial: {'v3.otpSessionId': 'otp'});
      final client = _FakeAuthClient()
        ..verifyResult = const OtpVerifyResult(
          accesskey: 'fresh-access',
          refreshToken: 'fresh-refresh',
          userId: 'a11ce0001',
          accesskeyTtl: Duration(days: 30),
          refreshTokenTtl: Duration(days: 90),
          isNewUser: false,
        );
      final auth = AuthService(client: client, storage: storage);
      await auth.init();
      var closed = false;
      auth.onLogin = (_) async => throw StateError('crypto key unavailable');
      auth.onLogout = ({bool erase = false}) async => closed = true;
      await expectLater(
          auth.verifyOtp('+911234567890', '123456'), throwsStateError);
      expect(auth.isLoggedIn, isFalse);
      expect(await storage.read(key: 'v3.accesskey'), isNull);
      expect(await storage.read(key: 'v3.user_id'), isNull);
      expect(closed, isTrue);
      await auth.dispose();
    });
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

    test('resendOtp keeps the session; a gone one starts over', () async {
      final client = _FakeAuthClient();
      final auth = AuthService(client: client, storage: _InMemoryStorage());
      await auth.init();
      await auth.sendOtp('+911234567890');
      expect(client.calls, ['send']);

      await auth.resendOtp('+911234567890');
      expect(client.calls, ['send', 'resend otp-1']);

      client.resendStatus = 410;
      final again = await auth.resendOtp('+911234567890');
      expect(client.calls, ['send', 'resend otp-1', 'resend otp-1', 'send']);
      expect(again.sessionId, 'otp-2');
      await auth.dispose();
    });

    test('logout clears secure storage, AuthClient, and emits false', () async {
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

    test('login opens the account store, logout keeps it, delete erases it',
        () async {
      final client = _FakeAuthClient()
        ..verifyResult = const OtpVerifyResult(
          accesskey: 'sk_fresh_xyz',
          refreshToken: 'rt_xyz',
          userId: 'b7c1d2e3f',
          accesskeyTtl: Duration(days: 30),
          refreshTokenTtl: Duration(days: 90),
          isNewUser: false,
        );
      const keyName = 'v3.e2ee.wrappingKey.b7c1d2e3f';
      final storage = _InMemoryStorage(initial: {
        'v3.otpSessionId': 'otp',
        keyName: 'account wrapping key',
        'v3.e2ee.wrappingKey.other': 'another account key',
      });
      final auth = AuthService(
        client: client,
        storage: storage,
      );
      await auth.init();
      final calls = <String>[];
      auth.onLogin = (userId) async {
        expect(await storage.read(key: 'v3.accesskey'), isNull,
            reason:
                'a background engine must not restore before the DB exists');
        calls.add('open $userId');
      };
      auth.onLogout = ({bool erase = false}) async =>
          calls.add(erase ? 'close+erase' : 'close');

      await auth.verifyOtp('+911234567890', '123456');
      await auth.logout();
      expect(await storage.read(key: keyName), 'account wrapping key');
      client.restoreSession(accesskey: 'sk_live', userId: 'b7c1d2e3f');
      await auth.deleteAccount('DELETE alice_k');

      expect(calls, ['open b7c1d2e3f', 'close', 'close+erase']);
      expect(await storage.read(key: keyName), isNull);
      expect(await storage.read(key: 'v3.e2ee.wrappingKey.other'),
          'another account key');
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

  _InMemoryStorage({Map<String, String>? initial}) : _data = {...?initial};

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
  final List<String> calls = [];
  int? resendStatus;
  int _sessions = 0;

  _FakeAuthClient() : super(baseUrl: Uri.parse('https://example.invalid'));

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
  Future<OtpSendResult> sendOtp({required String phone}) async {
    calls.add('send');
    _sessions += 1;
    return OtpSendResult(
      sessionId: 'otp-$_sessions',
      retryAfter: const Duration(seconds: 30),
      expiresIn: const Duration(minutes: 10),
    );
  }

  @override
  Future<OtpSendResult> resendOtp({required String sessionId}) async {
    calls.add('resend $sessionId');
    final status = resendStatus;
    if (status != null) {
      throw AuthClientException('resendOtp', status, 'SESSION_EXPIRED', null);
    }
    return OtpSendResult(
      sessionId: sessionId,
      retryAfter: const Duration(seconds: 30),
      expiresIn: const Duration(minutes: 9),
    );
  }

  @override
  Future<void> revokeSession() async {
    revokeCallCount += 1;
    if (revokeThrows) {
      throw StateError('simulated revoke network error');
    }
  }

  @override
  Future<void> deleteAccount({required String confirmation}) async {}
}
