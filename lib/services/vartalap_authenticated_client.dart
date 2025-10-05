/// Unified Authentication Client - Single source of truth for authentication
///
/// This client combines OTP verification with VartalapClient authentication,
/// replacing the over-engineered AuthService + VartalapClientManager pattern.
/// Firebase is used ONLY as an OTP delivery service.
library;

import 'package:flutter/foundation.dart';
import 'package:mobile_device_identifier/mobile_device_identifier.dart';
import 'package:vartalap/models/auth_models.dart';
import 'package:vartalap/services/otp/iotp_provider.dart';
import 'package:vartalap/services/otp/firebase_otp_provider.dart';
import 'package:vartalap/services/crashlystics.dart';
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
  bool get isAuthenticated => _currentUser != null;
  VartalapChatClientFlutter get client => _client;

  /// Initialize the client and check existing authentication
  Future<void> initialize() async {
    try {
      final user = await _client.getLoggedInUser();
      if (user != null) {
        _currentUser = user;
        _currentPhoneNumber = user.userId; // Phone number is userId
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
      await _client.client.login(vartalapCredential);

      // Get the authenticated user
      final user = await _client.getLoggedInUser();
      if (user == null) {
        throw AuthError.clientAuthentication('Login succeeded but no user found');
      }

      _currentUser = user;
      _setState(AuthState.authenticated);

    } on AuthError catch (e) {
      _setError(e.message, AuthState.error);
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace, reason: "Failed to verify OTP and login");
      _setError('Login failed. Please try again.', AuthState.error);
    }
  }

  /// Logout and clear all authentication state
  Future<void> logout() async {
    try {
      // Close client connections
      await _client.client.close();
      _clearState();
      _setState(AuthState.unauthenticated);
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

  /// Reset error state and return to unauthenticated
  void clearError() {
    _lastError = null;
    _setState(AuthState.unauthenticated);
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
    _state = errorState;
    notifyListeners();
  }

  /// Clear all authentication state
  void _clearState() {
    _currentUser = null;
    _currentPhoneNumber = null;
    _lastError = null;
  }

  @override
  void dispose() {
    _otpProvider.dispose();
    super.dispose();
  }
}