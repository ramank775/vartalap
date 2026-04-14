import 'dart:async';

import 'auth_token_provider.dart';

/// Self-hosted OTP auth + session management per AUTH_CONTRACT.md.
///
/// Synchronous REST calls — these do NOT go through `outbound_ops`
/// (SPIKE_B_SYNC.md §12a lists them as "NOT in the queue"). They block
/// on the network and surface failures directly to the UI.
///
/// The scaffold surfaces the method signatures and implements
/// [AuthTokenProvider] so transport adapters can consume it. Wire
/// impls land with step 7 of the V3_ARCHITECTURE roadmap.
///
/// **Surface lock (2026-04-15).** Method signatures here are the
/// contract that step 8 (transports) and step 10 (UI) build against
/// in parallel. Adding methods is fine; changing existing signatures
/// requires deliberate cross-track coordination — the scheduler,
/// transport adapters, and UI all assume these shapes.
class AuthClient implements AuthTokenProvider {
  final Uri baseUrl;

  String? _accesskey;
  String? _userId;

  AuthClient({required this.baseUrl});

  /// Seed in-memory session from persisted secure-storage values on app
  /// boot. UI calls this once at startup if the user has a saved
  /// session. Triggers no network. The transport adapters can call
  /// [refresh] later if the accesskey is rejected.
  void restoreSession({
    required String accesskey,
    required String userId,
  }) {
    _accesskey = accesskey;
    _userId = userId;
  }

  /// Drops in-memory session state. Caller is responsible for clearing
  /// `flutter_secure_storage` and the local store.
  void clearSession() {
    _accesskey = null;
    _userId = null;
  }

  // ---- AuthTokenProvider ------------------------------------------------

  @override
  String? get currentAccesskey => _accesskey;

  @override
  String? get currentUserId => _userId;

  @override
  Future<String?> refresh() =>
      throw UnimplementedError('AuthClient.refresh — wired in step 7');

  // ---- AUTH_CONTRACT endpoints -----------------------------------------

  /// `POST /v3.0/auth/otp/send` — AUTH_CONTRACT §3.1.
  Future<OtpSendResult> sendOtp({required String phone}) =>
      throw UnimplementedError('AuthClient.sendOtp — wired in step 7');

  /// `POST /v3.0/auth/otp/verify` — AUTH_CONTRACT §3.2.
  /// On success stores `accesskey` + `user_id` in memory; callers
  /// persist to `flutter_secure_storage`.
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String code,
  }) =>
      throw UnimplementedError('AuthClient.verifyOtp — wired in step 7');

  /// `POST /v3.0/auth/session/refresh` — AUTH_CONTRACT §4.3.
  Future<void> refreshSession({required String refreshToken}) =>
      throw UnimplementedError('AuthClient.refreshSession — wired in step 7');

  /// `POST /v3.0/auth/session/revoke` — AUTH_CONTRACT §4.4.
  Future<void> revokeSession() =>
      throw UnimplementedError('AuthClient.revokeSession — wired in step 7');

  /// `GET /v3.0/users/me` — AUTH_CONTRACT §4.5.
  Future<Map<String, dynamic>> getOwnProfile() =>
      throw UnimplementedError('AuthClient.getOwnProfile — wired in step 7');

  /// `PATCH /v3.0/users/me` — AUTH_CONTRACT §4.5.
  ///
  /// The UI calls this directly for username / display name / avatar
  /// edits AS the actual REST call dispatched by the `edit_profile`
  /// outbound_ops kind. Setting `username = null` clears it. Server
  /// enforces the 1-change-per-90-days rate limit
  /// (AUTH_CONTRACT §10.6).
  Future<Map<String, dynamic>> patchOwnProfile({
    String? username,
    String? displayName,
    String? avatarUrl,
    String? statusText,
  }) =>
      throw UnimplementedError(
          'AuthClient.patchOwnProfile — wired in step 7');

  /// `GET /v3.0/users/<user_id>` — AUTH_CONTRACT §7.5.
  Future<Map<String, dynamic>> getUser(String userId) =>
      throw UnimplementedError('AuthClient.getUser — wired in step 7');

  /// `POST /v3.0/contacts/lookup` — AUTH_CONTRACT §7.2.
  Future<Map<String, dynamic>> lookupContacts(List<String> phoneHashes) =>
      throw UnimplementedError('AuthClient.lookupContacts — wired in step 7');

  /// `POST /v3.0/push/topic` — AUTH_CONTRACT §5. NOTE: the scheduler
  /// enqueues `register_push_topic` ops against `outbound_ops`
  /// (SPIKE_B §12a note). This method is the actual REST call the
  /// [RestTransport] makes when dispatching that op kind.
  Future<void> registerPushTopic({
    required String deviceId,
    required String topic,
  }) =>
      throw UnimplementedError(
          'AuthClient.registerPushTopic — wired in step 7');

  /// `POST /v3.0/auth/phone/rebind/start` — AUTH_CONTRACT §9.
  Future<void> startPhoneRebind({required String newPhone}) =>
      throw UnimplementedError(
          'AuthClient.startPhoneRebind — wired in step 7');

  /// `POST /v3.0/auth/phone/rebind/verify` — AUTH_CONTRACT §9.
  Future<void> verifyPhoneRebind({required String code}) =>
      throw UnimplementedError(
          'AuthClient.verifyPhoneRebind — wired in step 7');

  /// `DELETE /v3.0/users/me` — AUTH_CONTRACT §8.
  Future<void> deleteAccount() =>
      throw UnimplementedError('AuthClient.deleteAccount — wired in step 7');
}

class OtpSendResult {
  final Duration retryAfter;
  const OtpSendResult({required this.retryAfter});
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
