/// v3 auth adapter — wraps [AuthClient] and persists the session
/// (accesskey + user_id + refreshToken + deviceId) in
/// flutter_secure_storage.
///
/// Surface per V3_ARCHITECTURE.md decision 7 and AUTH_CONTRACT.md
/// §3 (OTP), §4 (sessions), §8 (logout).
library vartalap.services.auth_service;

import 'dart:async';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// Secure-storage keys per AUTH_CONTRACT §14.1.
const String _keyAccesskey = 'v3.accesskey';
const String _keyUserId = 'v3.user_id';
const String _keyRefreshToken = 'v3.refreshToken';
const String _keyDeviceId = 'v3.deviceId';
const String _keyOtpSessionId = 'v3.otpSessionId';
const String _keyOtpPhone = 'v3.otpPhone';
const String _keyPhone = 'v3.phone';
const String _keyDisplayName = 'v3.displayName';
const String _keyUsername = 'v3.username';
const String _keyStatusText = 'v3.statusText';

class AuthService {
  final AuthClient _client;
  final FlutterSecureStorage _storage;

  /// Emits [true] after a successful [verifyOtp]; emits [false] after
  /// [logout]. Consumed by `main.dart` to route between login and the
  /// chat list.
  final StreamController<bool> _authState =
      StreamController<bool>.broadcast();

  String? _phoneNumber;
  String? _displayName;
  String? _username;
  String? _statusText;
  final StreamController<String?> _displayNameChange =
      StreamController<String?>.broadcast();
  final StreamController<String?> _usernameChange =
      StreamController<String?>.broadcast();
  final StreamController<String?> _statusTextChange =
      StreamController<String?>.broadcast();

  /// Held between [sendOtp] and [verifyOtp] — the server's session
  /// identifier for the OTP attempt (AUTH_CONTRACT §3.1).
  String? _otpSessionId;

  /// Set after a successful [verifyOtp] if the server returned a
  /// default channel (mock-server seed-peer feature). Consumed once
  /// by the post-login bootstrap in `main.dart`.
  String? lastDefaultChannelId;

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
  ///
  /// Also ensures a stable deviceId exists (generated on first boot,
  /// persisted forever).
  Future<void> init() async {
    // Ensure deviceId exists.
    var deviceId = await _storage.read(key: _keyDeviceId);
    if (deviceId == null) {
      deviceId = _generateDeviceId();
      await _storage.write(key: _keyDeviceId, value: deviceId);
    }
    _client.setDeviceId(deviceId);

    // Restore session if we have one.
    final accesskey = await _storage.read(key: _keyAccesskey);
    final userId = await _storage.read(key: _keyUserId);
    final refreshToken = await _storage.read(key: _keyRefreshToken);
    if (accesskey != null && userId != null) {
      _client.restoreSession(
        accesskey: accesskey,
        userId: userId,
        refreshToken: refreshToken,
        deviceId: deviceId,
      );
    }

    // Restore in-flight OTP session (survives hot restart).
    _otpSessionId = await _storage.read(key: _keyOtpSessionId);
    // Prefer the permanent phone (set on verifyOtp); fall back to the
    // OTP scratch key so a hot restart mid-OTP still shows the number.
    _phoneNumber = await _storage.read(key: _keyPhone) ??
        await _storage.read(key: _keyOtpPhone);
    _displayName = await _storage.read(key: _keyDisplayName);
    _username = await _storage.read(key: _keyUsername);
    _statusText = await _storage.read(key: _keyStatusText);
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

  /// User-chosen display name. Local-only for now (no server endpoint
  /// in v3.0); persisted in secure storage and emitted on
  /// [displayNameChange] when set or cleared.
  String? get displayName => _displayName;

  /// Emits the new value (or null) whenever [setDisplayName] is called.
  Stream<String?> get displayNameChange => _displayNameChange.stream;

  /// Persist [name] (trimmed) as the user's display name. Pass null or
  /// empty to clear. Best-effort PATCH to `/v3.0/users/me` so peers
  /// sharing a channel get a `ProfileEdited` push and update their
  /// local contact row. Server failures are swallowed — local-first
  /// wins, and the next successful patch covers the drift.
  Future<void> setDisplayName(String? name) async {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _displayName = null;
      await _storage.delete(key: _keyDisplayName);
    } else {
      _displayName = trimmed;
      await _storage.write(key: _keyDisplayName, value: trimmed);
    }
    _displayNameChange.add(_displayName);
    if (isLoggedIn) {
      try {
        await _client.patchOwnProfile(displayName: _displayName ?? '');
      } catch (_) {/* offline / 5xx → local-only */}
    }
  }

  String? get username => _username;
  Stream<String?> get usernameChange => _usernameChange.stream;

  Future<void> setUsername(String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _username = null;
      await _storage.delete(key: _keyUsername);
    } else {
      _username = trimmed;
      await _storage.write(key: _keyUsername, value: trimmed);
    }
    _usernameChange.add(_username);
    if (isLoggedIn) {
      try {
        await _client.patchOwnProfile(username: _username ?? '');
      } catch (_) {/* offline / 5xx → local-only */}
    }
  }

  String? get statusText => _statusText;
  Stream<String?> get statusTextChange => _statusTextChange.stream;

  Future<void> setStatusText(String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _statusText = null;
      await _storage.delete(key: _keyStatusText);
    } else {
      _statusText = trimmed;
      await _storage.write(key: _keyStatusText, value: trimmed);
    }
    _statusTextChange.add(_statusText);
    if (isLoggedIn) {
      try {
        await _client.patchOwnProfile(statusText: _statusText ?? '');
      } catch (_) {/* offline / 5xx → local-only */}
    }
  }

  /// `POST /v3.0/auth/otp/send` — AUTH_CONTRACT §3.1.
  ///
  /// Returns the [OtpSendResult] containing the sessionId needed for
  /// [verifyOtp]. Also stashes the sessionId internally so the
  /// verify-OTP screen doesn't need to carry it.
  Future<OtpSendResult> sendOtp(String phone) async {
    _phoneNumber = phone;
    final result = await _client.sendOtp(phone: phone);
    _otpSessionId = result.sessionId;
    await _storage.write(key: _keyOtpSessionId, value: result.sessionId);
    await _storage.write(key: _keyOtpPhone, value: phone);
    return result;
  }

  /// `POST /v3.0/auth/otp/verify` — AUTH_CONTRACT §3.2.
  ///
  /// On success:
  /// 1. Persist accesskey + user_id + refreshToken to secure storage.
  /// 2. [AuthClient] already has them in memory from the call.
  /// 3. Emit `true` on [authStateChange] so `main.dart` swaps the
  ///    root widget from login to chat list.
  ///
  /// On throw: no persistence, no state emit. Caller shows the error
  /// and the user re-enters the OTP.
  Future<OtpVerifyResult> verifyOtp(String phone, String code) async {
    final sessionId = _otpSessionId;
    if (sessionId == null) {
      throw StateError('verifyOtp called before sendOtp');
    }
    final result = await _client.verifyOtp(
      phone: phone,
      code: code,
      sessionId: sessionId,
    );
    await _storage.write(key: _keyAccesskey, value: result.accesskey);
    await _storage.write(key: _keyUserId, value: result.userId);
    await _storage.write(key: _keyRefreshToken, value: result.refreshToken);
    await _storage.write(key: _keyPhone, value: phone);
    _otpSessionId = null;
    _phoneNumber = phone;
    lastDefaultChannelId = result.defaultChannelId;
    await _storage.delete(key: _keyOtpSessionId);
    await _storage.delete(key: _keyOtpPhone);
    _authState.add(true);
    return result;
  }

  /// Coalesce concurrent refresh attempts. Multiple callers (the
  /// scheduler observing AUTH_FAILURE, the WS observing
  /// WS_REAUTH_REQUIRED) can fire near-simultaneously; we share the
  /// same in-flight future so we only hit the server once.
  Future<bool>? _refreshInFlight;

  /// Try to refresh the session by exchanging the stored refresh token
  /// for a new accesskey. On success: persist the new tokens and
  /// return true. On failure (no token, refresh rejected): tear down
  /// the local session via [logout] and return false — that emits
  /// `authStateChange=false` so the UI routes to login.
  ///
  /// Coalesced — concurrent calls share one in-flight future, so two
  /// near-simultaneous AUTH_FAILUREs hit the server once.
  Future<bool> refreshSession() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final fut = _doRefresh().whenComplete(() => _refreshInFlight = null);
    _refreshInFlight = fut;
    return fut;
  }

  Future<bool> _doRefresh() async {
    final newKey = await _client.refresh();
    if (newKey == null) {
      // Refresh failed — refresh token is gone or rejected. Force the
      // user back to login by tearing down the session.
      await logout();
      return false;
    }
    // Persist the freshened tokens. AuthClient.refresh updated its
    // in-memory state but not the storage layer.
    await _storage.write(key: _keyAccesskey, value: newKey);
    final newRt = _client.currentRefreshToken;
    if (newRt != null) {
      await _storage.write(key: _keyRefreshToken, value: newRt);
    }
    return true;
  }

  /// `POST /v3.0/auth/session/revoke` — AUTH_CONTRACT §4.6.
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
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyPhone);
    await _storage.delete(key: _keyDisplayName);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyStatusText);
    _client.clearSession();
    _phoneNumber = null;
    _displayName = null;
    _username = null;
    _statusText = null;
    _otpSessionId = null;
    _authState.add(false);
  }

  /// Disposes the internal state stream. Call on app exit.
  Future<void> dispose() async {
    await _authState.close();
    await _displayNameChange.close();
    await _usernameChange.close();
    await _statusTextChange.close();
  }

  /// Generate a stable device identifier (UUIDv4 — good enough for a
  /// random opaque token per AUTH_CONTRACT §3.1). We use v4 here
  /// because the deviceId doesn't need time-ordering — it just needs
  /// to be unique per install.
  static String _generateDeviceId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    // Set version 4 (bits 6-7 of byte 6).
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant 1 (bits 6-7 of byte 8).
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
