import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_device_identifier/mobile_device_identifier.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/events.dart';

enum AuthState {
  unauthenticated,
  sendingOTP,
  otpSent,
  verifyingOTP,
  authenticated,
  error,
}

class AuthRepository extends ChangeNotifier {
  final VartalapChatClientFlutter _client;
  final IOTPProvider _otpProvider;

  AuthState _state = AuthState.unauthenticated;
  String? _lastError;
  String? _currentPhoneNumber;
  Profile? _currentUser;

  AuthRepository(this._client, this._otpProvider);

  AuthState get state => _state;
  String? get lastError => _lastError;
  String? get currentPhoneNumber => _currentPhoneNumber;
  Profile? get currentUser => _currentUser;
  bool get isAuthenticated => _state == AuthState.authenticated;

  /// Check token and restore session
  Future<void> checkAuth() async {
    try {
      final userId = await _client.getLoggedInUser();
      if (userId != null) {
        _currentPhoneNumber = userId;
        await _client.init();
        _currentUser = await _client.getLoggedInUserProfile();
        _setState(AuthState.authenticated);
      } else {
        _setState(AuthState.unauthenticated);
      }
    } catch (e) {
      debugPrint('[AUTH] Check auth failed: $e');
      _setError('Failed to restore session', AuthState.error);
    }
  }

  Future<void> sendOTP(String phoneNumber) async {
    _setState(AuthState.sendingOTP);
    _currentPhoneNumber = phoneNumber;
    try {
      final result = await _otpProvider.sendOTP(phoneNumber);
      if (result.success) {
        _setState(AuthState.otpSent);
      } else {
        _setError(result.errorMessage ?? 'Failed to send OTP', AuthState.error);
      }
    } catch (e) {
      _setError('Error sending OTP: $e', AuthState.error);
    }
  }

  Future<void> verifyOTP(String otp) async {
    _setState(AuthState.verifyingOTP);
    try {
      final credential = await _otpProvider.verifyOTP(otp);

      String deviceId = 'unknown';
      try {
        deviceId = (await MobileDeviceIdentifier().getDeviceId()) ?? 'unknown';
      } catch (_) {}

      final vartalapCred = Credential.fromJson(
          credential.toVartalapCredential(deviceId: deviceId));

      await _client.login(vartalapCred);
      await _client.init();

      final userId = await _client.getLoggedInUser();
      if (userId == null) throw Exception('No user found after login');

      _currentPhoneNumber = userId;
      _currentUser = await _client.getLoggedInUserProfile();

      _setState(AuthState.authenticated);
    } catch (e) {
      debugPrint('[AUTH] Login failed: $e');
      _setError('Login failed: $e', AuthState.error);
    }
  }

  Future<void> logout() async {
    await _client.logout();
    _currentUser = null;
    _currentPhoneNumber = null;
    _setState(AuthState.unauthenticated);
  }

  Future<void> updateProfile({String? name, String? image}) async {
    if (_currentUser == null) return;

    final updated = Profile(
      userId: _currentUser!.userId,
      name: name ?? _currentUser!.name,
      email: _currentUser!.email,
      image: image ?? _currentUser!.image,
    );

    await _client.saveUserProfile(updated);
    _currentUser = updated;
    notifyListeners();
    // Todo: sync
  }

  /// Update the current user profile image
  Future<void> updateProfileImage(String path) async {
    if (_currentUser == null) return;

    try {
      final fileName = path.split('/').last;
      final extension = fileName.split('.').last;

      await _client.db.transaction(() async {
        // 1. Create Local Asset for Profile Image
        final assetId = await _client.db.into(_client.db.assests).insert(
              AssestsCompanion.insert(
                type: const Value('profile_image'),
                path: Value(path),
                mimeType: Value(extension),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );

        // 2. Schedule Upload Task
        final task = _client.factory.create(
          AssetUploadTask.name,
          payload: assetId,
        );
        await _client.scheduler.schedule(task);

        // 3. Update local state (optimistic)
        final updatedProfile = Profile(
          userId: _currentUser!.userId,
          name: _currentUser!.name,
          email: _currentUser!.email,
          image: path, // Local path for immediate display
        );

        await _client.saveUserProfile(updatedProfile);
        _currentUser = updatedProfile;
        notifyListeners();
      });

      debugPrint('[AUTH] Profile image update scheduled: $path');
    } catch (e) {
      debugPrint('[AUTH] Failed to update profile image: $e');
      rethrow;
    }
  }

  void _setState(AuthState newState) {
    _state = newState;
    _lastError = null;
    notifyListeners();
  }

  void _setError(String msg, AuthState errorState) {
    _lastError = msg;
    _state = errorState;
    notifyListeners();
  }
}
