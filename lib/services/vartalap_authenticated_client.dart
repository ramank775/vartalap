/// Unified Authentication Client - Single source of truth for authentication
///
/// This client combines OTP verification with VartalapClient authentication,
/// replacing the over-engineered AuthService + VartalapClientManager pattern.
/// Firebase is used ONLY as an OTP delivery service.
library;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_device_identifier/mobile_device_identifier.dart';
import 'package:vartalap/models/auth_models.dart';
import 'package:vartalap/services/otp/iotp_provider.dart';
import 'package:vartalap/services/otp/firebase_otp_provider.dart';
import 'package:vartalap/services/crashlystics.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/events.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

/// Unified authentication client that handles the complete auth flow
///
/// This is the single source of truth for authentication state.
/// It coordinates OTP delivery (via IOTPProvider) with VartalapClient authentication.
class VartalapAuthenticatedClient extends ChangeNotifier {
  final VartalapChatClientFlutter _client;
  final IOTPProvider _otpProvider;

  // Authentication state
  AuthState _state = AuthState.unauthenticated;
  AuthState? _previousState; // Track state before error
  Profile? _currentUser;
  String? _currentPhoneNumber;
  String? _lastError;

  VartalapAuthenticatedClient({
    required VartalapChatClientFlutter client,
    IOTPProvider? otpProvider,
  }) : _client = client,
       _otpProvider = otpProvider ?? FirebaseOTPProvider();

  // Public getters
  AuthState get state => _state;
  Profile? get currentUser => _currentUser;
  String? get currentPhoneNumber => _currentPhoneNumber;
  String? get lastError => _lastError;
  bool get isAuthenticated => _state == AuthState.authenticated;
  VartalapChatClientFlutter get client => _client;

  /// Initialize the client and check existing authentication
  ///
  /// This method checks if a user is logged in by verifying the stored token.
  /// It then initializes the underlying client and loads the user profile.
  Future<void> initialize() async {
    try {
      final userId = await _client.getLoggedInUser();
      if (userId != null) {
        // User has a valid token, initialize client
        _currentPhoneNumber = userId; // Phone number is userId
        
        debugPrint('[AUTH] Restoring session for: $userId');
        await _client.init();
        
        // Try to load profile for offline access
        _currentUser = await _client.getLoggedInUserProfile();
        debugPrint('[AUTH] Profile restored: ${_currentUser?.name ?? "No name"}');
        
        _setState(AuthState.authenticated);
      } else {
        _setState(AuthState.unauthenticated);
      }
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace, reason: "Failed to initialize VartalapAuthenticatedClient");
      _setError('Failed to initialize authentication', AuthState.error);
    }
  }

  /// Send OTP to the specified phone number
  Future<void> sendOTP(String phoneNumber) async {
    try {
      _setState(AuthState.sendingOTP);
      _currentPhoneNumber = phoneNumber;

      final result = await _otpProvider.sendOTP(phoneNumber);

      if (result.success) {
        _setState(AuthState.otpSent);
      } else {
        _setError(result.errorMessage ?? 'Failed to send OTP', AuthState.error);
      }
    } on AuthError catch (e) {
      _setError(e.message, AuthState.error);
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace, reason: "Failed to send OTP");
      _setError('Unexpected error sending OTP', AuthState.error);
    }
  }

  /// Verify OTP and authenticate with VartalapClient
  Future<void> verifyOTPAndLogin(String otp) async {
    try {
      _setState(AuthState.verifyingOTP);

      // Verify OTP with provider (provider manages its own session state)
      final credential = await _otpProvider.verifyOTP(otp);

      // Get unique device ID
      String deviceId = 'unknown';
      try {
        final id = await MobileDeviceIdentifier().getDeviceId();
        if (id != null && id.isNotEmpty) {
          deviceId = id;
        }
      } catch (e) {
        // Fallback to 'unknown' if device ID retrieval fails
        debugPrint('Failed to get device ID: $e');
      }

      // Authenticate with VartalapClient using the credential
      final vartalapCredentialMap = credential.toVartalapCredential(deviceId: deviceId);
      final vartalapCredential = Credential.fromJson(vartalapCredentialMap);
      await _client.login(vartalapCredential);

      // Get the authenticated user ID (works offline via token)
      debugPrint('[AUTH] Fetching logged in user after login...');
      final userId = await _client.getLoggedInUser();
      debugPrint('[AUTH] Got userId: ${userId ?? "null"}');

      if (userId == null) {
        throw AuthError.clientAuthentication('Login succeeded but no user found');
      }

      _currentPhoneNumber = userId; // Phone number is userId

      // Initialize the database for this user
      debugPrint('[AUTH] Initializing database for user: $userId');
      await _client.init();

      // Fetch and save user profile to database for offline access
      debugPrint('[AUTH] Fetching and saving user profile...');
      final profile = await _client.getLoggedInUserProfile();
      if (profile != null) {
        _currentUser = profile;
        debugPrint('[AUTH] Profile saved: ${profile.userId}');
      } else {
        debugPrint('[AUTH] Warning: Could not fetch user profile');
      }

      debugPrint('[AUTH] Setting state to authenticated');
      _setState(AuthState.authenticated);
      debugPrint('[AUTH] State is now: $_state');

    } on AuthError catch (e) {
      _setError(e.message, AuthState.error);
      rethrow; // Rethrow so UI can show error dialog
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace, reason: "Failed to verify OTP and login");
      _setError('Login failed. Please try again.', AuthState.error);
      rethrow; // Rethrow so UI can show error dialog
    }
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
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace, reason: "Failed to update profile image");
      rethrow;
    }
  }

  /// Update the current user profile
  Future<void> updateProfile({String? name, String? image}) async {
    if (_currentUser == null) return;

    try {
      final updatedProfile = Profile(
        userId: _currentUser!.userId,
        name: name ?? _currentUser!.name,
        email: _currentUser!.email,
        image: image ?? _currentUser!.image,
      );

      // Save to local database
      await _client.saveUserProfile(updatedProfile);
      
      // Update local state
      _currentUser = updatedProfile;
      notifyListeners();

      debugPrint('[AUTH] Profile updated locally: ${updatedProfile.name}');
      
      // TODO: Schedule a background task to sync with server
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace, reason: "Failed to update profile");
      rethrow;
    }
  }

  /// Logout and clear all authentication state
  ///
  /// This method clears:
  /// - Authentication token from secure storage
  /// - Database connections
  /// - Network connections
  /// - Local authentication state
  Future<void> logout() async {
    try {
      // Logout from client (clears token, closes DB and network)
      await _client.logout();

      // Clear local authentication state
      _clearState();
      _setState(AuthState.unauthenticated);

      debugPrint('[AUTH] Logout successful');
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace, reason: "Failed to logout");
      // Clear state anyway since logout should always succeed
      _clearState();
      _setState(AuthState.unauthenticated);
    }
  }

  /// Resend OTP to the current phone number
  Future<void> resendOTP() async {
    if (_currentPhoneNumber == null) {
      _setError('No phone number to resend OTP to', AuthState.error);
      return;
    }
    await sendOTP(_currentPhoneNumber!);
  }

  /// Reset error state and return to appropriate previous state
  ///
  /// If OTP was sent, returns to otpSent state to allow retry.
  /// Otherwise, returns to unauthenticated state.
  void clearError() {
    _lastError = null;
    // Restore to previous state, or unauthenticated if no previous state
    final targetState = _previousState ?? AuthState.unauthenticated;
    _previousState = null;
    _setState(targetState);
  }

  /// Update authentication state and notify listeners
  void _setState(AuthState newState) {
    _state = newState;
    _lastError = null; // Clear error when state changes successfully
    notifyListeners();
  }

  /// Set error state with message
  void _setError(String error, AuthState errorState) {
    _lastError = error;
    // Store current state before transitioning to error (unless already in error)
    if (_state != AuthState.error) {
      _previousState = _state;
    }
    _state = errorState;
    notifyListeners();
  }

  /// Clear all authentication state
  void _clearState() {
    _currentUser = null;
    _currentPhoneNumber = null;
    _lastError = null;
    _previousState = null;
  }

  @override
  void dispose() {
    _otpProvider.dispose();
    super.dispose();
  }
}
