/// v3 auth adapter — wraps [AuthClient] and persists the session
/// (accesskey + user_id) in flutter_secure_storage.
///
/// Surface per V3_ARCHITECTURE.md decision 7 and AUTH_CONTRACT.md
/// §3 (OTP), §4 (sessions), §8 (logout). The [AuthClient] method
/// bodies currently throw `UnimplementedError` pending step 7 of the
/// v3 roadmap; the UI therefore sees OTP flow throws as "network
/// failure" and shows the error dialog. Once step 7 lands, the same
/// UI lights up with no changes here.
library vartalap.services.auth_service;

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// Secure-storage keys — AUTH_CONTRACT §3.2 persists the returned
/// accesskey and user_id; the refreshToken rides the 90-day rotation
/// flow (§4.3). v3.0 does not persist the refreshToken in
/// secure-storage separately because session refresh is a step-7
/// concern; once it lands we add a `_keyRefreshToken` constant here.
const String _keyAccesskey = 'v3.accesskey';
const String _keyUserId = 'v3.user_id';

class AuthService {
  final AuthClient _client;
  final FlutterSecureStorage _storage;

  /// Emits [true] after a successful [verifyOtp]; emits [false] after
  /// [logout]. Consumed by `main.dart` to route between login and the
  /// chat list.
  final StreamController<bool> _authState =
      StreamController<bool>.broadcast();

  String? _phoneNumber;

  AuthService({
    required AuthClient client,
    FlutterSecureStorage? storage,
  })  : _client = client,
        _storage = storage ?? const FlutterSecureStorage();

  /// Observable auth state. True after login, false after logout.
  /// Does NOT emit the current value on subscribe — callers read
  /// [isLoggedIn] synchronously before subscribing.
  Stream<bool> get authStateChange => _authState.stream;

  /// Rehydrates the in-memory session from secure storage. Call once
  /// at app boot, BEFORE wiring transports (they read
  /// `AuthClient.currentAccesskey` on their first frame).
  Future<void> init() async {
    final accesskey = await _storage.read(key: _keyAccesskey);
    final userId = await _storage.read(key: _keyUserId);
    if (accesskey != null && userId != null) {
      _client.restoreSession(accesskey: accesskey, userId: userId);
    }
  }

  /// True iff the [AuthClient] has an in-memory session. Synchronous —
  /// post-[init] state.
  bool get isLoggedIn => _client.currentAccesskey != null;

  /// The logged-in user's `user_id`, if any. Display names resolve to
  /// contact rows (AUTH_CONTRACT §2.4) — this is the wire identifier.
  String? get currentUserId => _client.currentUserId;

  /// Last phone number we attempted OTP against. Used by the
  /// verify-OTP screen so it can show "6-digit code sent to +91…".
  String? get phoneNumber => _phoneNumber;

  /// `POST /v3.0/auth/otp/send` — AUTH_CONTRACT §3.1.
  ///
  /// Throws `UnimplementedError` until step 7 lands. The login screen
  /// treats the throw as a transient network failure and surfaces it
  /// via the standard error dialog.
  Future<OtpSendResult> sendOtp(String phone) async {
    _phoneNumber = phone;
    return _client.sendOtp(phone: phone);
  }

  /// `POST /v3.0/auth/otp/verify` — AUTH_CONTRACT §3.2.
  ///
  /// On success:
  /// 1. Persist accesskey + user_id to secure storage.
  /// 2. [AuthClient.restoreSession] puts them in memory so transport
  ///    adapters read them immediately (no reboot needed).
  /// 3. Emit `true` on [authStateChange] so `main.dart` swaps the
  ///    root widget from login to chat list.
  ///
  /// On throw: no persistence, no state emit. Caller shows the error
  /// and the user re-enters the OTP.
  Future<OtpVerifyResult> verifyOtp(String phone, String code) async {
    final result = await _client.verifyOtp(phone: phone, code: code);
    await _storage.write(key: _keyAccesskey, value: result.accesskey);
    await _storage.write(key: _keyUserId, value: result.userId);
    _client.restoreSession(
      accesskey: result.accesskey,
      userId: result.userId,
    );
    _authState.add(true);
    return result;
  }

  /// `POST /v3.0/auth/session/revoke` — AUTH_CONTRACT §4.4.
  ///
  /// Order matters: we attempt the server revoke first so the server
  /// marks the accesskey invalid before we drop it locally. If the
  /// revoke throws (network down, server 5xx), we still clear local
  /// state — offline logout would otherwise trap the user in a broken
  /// session. The stale accesskey on the server will expire via its
  /// 30-day TTL.
  Future<void> logout() async {
    try {
      await _client.revokeSession();
    } catch (_) {
      // best effort — fall through to local teardown
    }
    await _storage.delete(key: _keyAccesskey);
    await _storage.delete(key: _keyUserId);
    _client.clearSession();
    _phoneNumber = null;
    _authState.add(false);
  }

  /// Disposes the internal state stream. Call on app exit.
  Future<void> dispose() async {
    await _authState.close();
  }
}
