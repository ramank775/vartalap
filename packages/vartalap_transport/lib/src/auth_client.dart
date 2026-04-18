import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_token_provider.dart';

/// Self-hosted OTP auth + session management per AUTH_CONTRACT.md.
///
/// Synchronous REST calls — these do NOT go through `outbound_ops`
/// (SPIKE_B_SYNC.md §12a lists them as "NOT in the queue"). They block
/// on the network and surface failures directly to the UI.
///
/// **Surface lock (2026-04-15).** Method signatures here are the
/// contract that step 8 (transports) and step 10 (UI) build against
/// in parallel. Adding methods is fine; changing existing signatures
/// requires deliberate cross-track coordination — the scheduler,
/// transport adapters, and UI all assume these shapes.
class AuthClient implements AuthTokenProvider {
  final Uri baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  String? _accesskey;
  String? _userId;
  String? _refreshToken;
  String? _deviceId;

  AuthClient({
    required this.baseUrl,
    http.Client? httpClient,
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// Seed in-memory session from persisted secure-storage values on app
  /// boot. UI calls this once at startup if the user has a saved
  /// session. Triggers no network. The transport adapters can call
  /// [refresh] later if the accesskey is rejected.
  void restoreSession({
    required String accesskey,
    required String userId,
    String? refreshToken,
    String? deviceId,
  }) {
    _accesskey = accesskey;
    _userId = userId;
    _refreshToken = refreshToken;
    _deviceId = deviceId;
  }

  /// Set the stable device identifier. Called once on boot from
  /// AuthService after reading (or generating) the persisted deviceId.
  void setDeviceId(String deviceId) {
    _deviceId = deviceId;
  }

  /// Drops in-memory session state. Caller is responsible for clearing
  /// `flutter_secure_storage` and the local store.
  void clearSession() {
    _accesskey = null;
    _userId = null;
    _refreshToken = null;
  }

  /// Close the underlying HTTP client if we own it.
  void dispose() {
    if (_ownsClient) _client.close();
  }

  // ---- AuthTokenProvider ------------------------------------------------

  @override
  String? get currentAccesskey => _accesskey;

  @override
  String? get currentUserId => _userId;

  @override
  Future<String?> refresh() async {
    final rt = _refreshToken;
    final did = _deviceId;
    if (rt == null || did == null) return null;
    try {
      final result = await refreshSession(refreshToken: rt, deviceId: did);
      _accesskey = result.accesskey;
      _refreshToken = result.refreshToken;
      _userId = result.userId;
      return result.accesskey;
    } catch (_) {
      return null;
    }
  }

  // ---- AUTH_CONTRACT endpoints -----------------------------------------

  /// `POST /v3.0/auth/otp/send` — AUTH_CONTRACT §3.1.
  Future<OtpSendResult> sendOtp({required String phone}) async {
    final did = _deviceId;
    if (did == null) {
      throw StateError('AuthClient.sendOtp: deviceId not set');
    }
    final resp = await _post('/v3.0/auth/otp/send', body: {
      'phone': phone,
      'deviceId': did,
    });
    _assertOk(resp, 'sendOtp');
    final json = _decodeJson(resp);
    return OtpSendResult(
      sessionId: json['sessionId'] as String,
      retryAfter: Duration(seconds: json['resendAfterSec'] as int),
      expiresIn: Duration(seconds: json['expiresInSec'] as int),
      isExistingAccount: json['isExistingAccount'] as bool? ?? false,
    );
  }

  /// `POST /v3.0/auth/otp/verify` — AUTH_CONTRACT §3.2.
  /// On success stores `accesskey` + `user_id` in memory; callers
  /// persist to `flutter_secure_storage`.
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String code,
    required String sessionId,
  }) async {
    final did = _deviceId;
    if (did == null) {
      throw StateError('AuthClient.verifyOtp: deviceId not set');
    }
    final resp = await _post('/v3.0/auth/otp/verify', body: {
      'sessionId': sessionId,
      'code': code,
      'deviceId': did,
    });
    _assertOk(resp, 'verifyOtp');
    final json = _decodeJson(resp);

    final accesskey = json['accesskey'] as String;
    final userId = json['user_id'] as String;
    final refreshToken = json['refreshToken'] as String;

    _accesskey = accesskey;
    _userId = userId;
    _refreshToken = refreshToken;

    return OtpVerifyResult(
      accesskey: accesskey,
      refreshToken: refreshToken,
      userId: userId,
      accesskeyTtl: Duration(
        milliseconds:
            (json['accesskeyExpiresAt'] as int) - DateTime.now().millisecondsSinceEpoch,
      ),
      refreshTokenTtl: Duration(
        milliseconds:
            (json['refreshTokenExpiresAt'] as int) - DateTime.now().millisecondsSinceEpoch,
      ),
      isNewUser: json['isNew'] as bool? ?? false,
    );
  }

  /// `POST /v3.0/auth/session/refresh` — AUTH_CONTRACT §4.3.
  Future<SessionRefreshResult> refreshSession({
    required String refreshToken,
    required String deviceId,
  }) async {
    final resp = await _post('/v3.0/auth/session/refresh', body: {
      'refreshToken': refreshToken,
      'deviceId': deviceId,
    });
    _assertOk(resp, 'refreshSession');
    final json = _decodeJson(resp);
    return SessionRefreshResult(
      userId: json['user_id'] as String,
      accesskey: json['accesskey'] as String,
      refreshToken: json['refreshToken'] as String,
      accesskeyExpiresAt: json['accesskeyExpiresAt'] as int,
      refreshTokenExpiresAt: json['refreshTokenExpiresAt'] as int,
    );
  }

  /// `POST /v3.0/auth/session/revoke` — AUTH_CONTRACT §4.6.
  Future<void> revokeSession() async {
    final headers = _authHeaders();
    final body = <String, dynamic>{};
    if (_refreshToken != null) {
      body['refreshToken'] = _refreshToken;
    }
    final resp = await _post('/v3.0/auth/session/revoke',
        body: body, headers: headers);
    // Best-effort: don't throw on failure — logout clears local state
    // regardless (AuthService handles this).
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    // Surface server errors for logging but don't block logout.
    throw AuthClientException(
      'revokeSession',
      resp.statusCode,
      _tryParseErrorCode(resp),
      _tryParseErrorMessage(resp),
    );
  }

  /// `GET /v3.0/users/me` — AUTH_CONTRACT §4.4.
  Future<Map<String, dynamic>> getOwnProfile() async {
    final resp = await _get('/v3.0/users/me', headers: _authHeaders());
    _assertOk(resp, 'getOwnProfile');
    return _decodeJson(resp);
  }

  /// `PATCH /v3.0/users/me` — AUTH_CONTRACT §4.5.
  Future<Map<String, dynamic>> patchOwnProfile({
    String? username,
    String? displayName,
    String? avatarUrl,
    String? statusText,
  }) async {
    final body = <String, dynamic>{};
    // Explicit null means "clear"; absent means "unchanged". We only
    // include fields the caller actually passed. Dart doesn't
    // distinguish "not passed" from "passed as null" at this level,
    // so we include all non-null values. To clear a field the caller
    // must use a separate clearProfile method or the UI must send the
    // raw JSON directly — acceptable for v3.0.
    if (username != null) body['username'] = username;
    if (displayName != null) body['displayName'] = displayName;
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    if (statusText != null) body['statusText'] = statusText;

    final resp = await _patch('/v3.0/users/me',
        body: body, headers: _authHeaders());
    _assertOk(resp, 'patchOwnProfile');
    return _decodeJson(resp);
  }

  /// `GET /v3.0/users/<user_id>` — AUTH_CONTRACT §7.5.
  Future<Map<String, dynamic>> getUser(String userId) async {
    final resp =
        await _get('/v3.0/users/$userId', headers: _authHeaders());
    _assertOk(resp, 'getUser');
    return _decodeJson(resp);
  }

  /// `POST /v3.0/contacts/lookup` — AUTH_CONTRACT §7.2.
  Future<List<ContactMatch>> lookupContacts(
      List<String> phoneHashes) async {
    final resp = await _post('/v3.0/contacts/lookup',
        body: {'phoneHashes': phoneHashes}, headers: _authHeaders());
    _assertOk(resp, 'lookupContacts');
    final json = _decodeJson(resp);
    final matches = json['matches'] as List<dynamic>? ?? [];
    return matches
        .cast<Map<String, dynamic>>()
        .map((m) => ContactMatch(
              phoneHash: m['phoneHash'] as String,
              userId: m['user_id'] as String,
              username: m['username'] as String?,
            ))
        .toList();
  }

  /// `POST /v3.0/push/topic` — AUTH_CONTRACT §5.1.
  Future<void> registerPushTopic({
    required String topicUrl,
  }) async {
    final resp = await _post('/v3.0/push/topic',
        body: {'topicUrl': topicUrl}, headers: _authHeaders());
    _assertOk(resp, 'registerPushTopic');
  }

  /// `POST /v3.0/auth/phone/rebind/start` — AUTH_CONTRACT §9.2.
  Future<OtpSendResult> startPhoneRebind({required String newPhone}) async {
    final resp = await _post('/v3.0/auth/phone/rebind/start',
        body: {'newPhone': newPhone}, headers: _authHeaders());
    _assertOk(resp, 'startPhoneRebind');
    final json = _decodeJson(resp);
    return OtpSendResult(
      sessionId: json['rebindSessionId'] as String,
      retryAfter: Duration(seconds: json['resendAfterSec'] as int),
      expiresIn: Duration(seconds: json['expiresInSec'] as int),
    );
  }

  /// `POST /v3.0/auth/phone/rebind/verify` — AUTH_CONTRACT §9.3.
  Future<Map<String, dynamic>> verifyPhoneRebind({
    required String rebindSessionId,
    required String code,
  }) async {
    final resp = await _post('/v3.0/auth/phone/rebind/verify',
        body: {'rebindSessionId': rebindSessionId, 'code': code},
        headers: _authHeaders());
    _assertOk(resp, 'verifyPhoneRebind');
    return _decodeJson(resp);
  }

  /// `POST /v3.0/users/me/delete` — AUTH_CONTRACT §8.2.
  Future<void> deleteAccount({required String confirmation}) async {
    final resp = await _post('/v3.0/users/me/delete',
        body: {'confirmation': confirmation}, headers: _authHeaders());
    _assertOk(resp, 'deleteAccount');
  }

  // ---- HTTP helpers ---------------------------------------------------

  Map<String, String> _authHeaders() {
    final key = _accesskey;
    if (key == null) {
      throw StateError('AuthClient: no accesskey — not signed in');
    }
    return {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Future<http.Response> _post(
    String path, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) {
    final uri = baseUrl.resolve(path);
    return _client.post(
      uri,
      headers: headers ??
          const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _get(
    String path, {
    required Map<String, String> headers,
  }) {
    final uri = baseUrl.resolve(path);
    return _client.get(uri, headers: headers);
  }

  Future<http.Response> _patch(
    String path, {
    required Map<String, dynamic> body,
    required Map<String, String> headers,
  }) {
    final uri = baseUrl.resolve(path);
    return _client.patch(uri, headers: headers, body: jsonEncode(body));
  }

  Map<String, dynamic> _decodeJson(http.Response resp) {
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  void _assertOk(http.Response resp, String method) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw AuthClientException(
      method,
      resp.statusCode,
      _tryParseErrorCode(resp),
      _tryParseErrorMessage(resp),
    );
  }

  String? _tryParseErrorCode(http.Response resp) {
    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final err = json['error'] as Map<String, dynamic>?;
      return err?['code'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _tryParseErrorMessage(http.Response resp) {
    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final err = json['error'] as Map<String, dynamic>?;
      return err?['message'] as String?;
    } catch (_) {
      return null;
    }
  }
}

/// Structured error from any AuthClient call.
class AuthClientException implements Exception {
  final String method;
  final int statusCode;
  final String? errorCode;
  final String? message;

  const AuthClientException(
      this.method, this.statusCode, this.errorCode, this.message);

  @override
  String toString() {
    final code = errorCode ?? 'http_$statusCode';
    final msg = message ?? '';
    return 'AuthClientException($method): $code — $msg';
  }

  /// True if this is a rate-limit error (429).
  bool get isRateLimited => statusCode == 429;

  /// True if this is an auth failure (401).
  bool get isAuthFailure => statusCode == 401;

  /// True if the session is locked (423, too many wrong OTP codes).
  bool get isSessionLocked => statusCode == 423;
}

class OtpSendResult {
  final String sessionId;
  final Duration retryAfter;
  final Duration expiresIn;
  final bool isExistingAccount;

  const OtpSendResult({
    required this.sessionId,
    required this.retryAfter,
    required this.expiresIn,
    this.isExistingAccount = false,
  });
}

class OtpVerifyResult {
  final String accesskey;
  final String refreshToken;
  final String userId;
  final Duration accesskeyTtl;
  final Duration refreshTokenTtl;
  final bool isNewUser;

  const OtpVerifyResult({
    required this.accesskey,
    required this.refreshToken,
    required this.userId,
    required this.accesskeyTtl,
    required this.refreshTokenTtl,
    required this.isNewUser,
  });
}

class SessionRefreshResult {
  final String userId;
  final String accesskey;
  final String refreshToken;
  final int accesskeyExpiresAt;
  final int refreshTokenExpiresAt;

  const SessionRefreshResult({
    required this.userId,
    required this.accesskey,
    required this.refreshToken,
    required this.accesskeyExpiresAt,
    required this.refreshTokenExpiresAt,
  });
}

class ContactMatch {
  final String phoneHash;
  final String userId;
  final String? username;

  const ContactMatch({
    required this.phoneHash,
    required this.userId,
    this.username,
  });
}
