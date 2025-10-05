/// Firebase implementation of IOTPProvider
///
/// This provider uses Firebase Phone Authentication for OTP delivery and verification.
/// It extracts and isolates Firebase-specific logic from the authentication flow,
/// making it easy to replace Firebase with other OTP services.
library;

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vartalap/models/auth_models.dart';
import 'package:vartalap/services/otp/iotp_provider.dart';
import 'package:vartalap/services/crashlystics.dart';
import 'package:vartalap/services/firebase_initializer.dart';
// Push notifications are handled separately from authentication

/// Firebase implementation of IOTPProvider with lazy initialization
///
/// This provider handles OTP delivery and verification using Firebase Phone Authentication.
/// It's responsible ONLY for OTP-related operations, not for authentication state management.
///
/// Key responsibilities:
/// - Send OTP via Firebase Phone Auth
/// - Verify OTP and generate Firebase ID token
/// - Handle Firebase-specific errors and edge cases
/// - Manage verification sessions and resend tokens
class FirebaseOTPProvider implements IOTPProvider {
  FirebaseAuth? _auth;
  final FlutterSecureStorage _storage;

  // Firebase-specific state for OTP verification
  String? _currentVerificationId;
  int? _resendToken;
  String? _currentPhoneNumber;

  // Completers for async operations
  final Map<String, Completer<OTPResult>> _sendOtpCompleters = {};

  FirebaseOTPProvider({
    FirebaseAuth? auth,
    FlutterSecureStorage? storage,
  })  : _auth = auth,
        _storage = storage ?? const FlutterSecureStorage();

  /// Lazy getter for FirebaseAuth that ensures Firebase is initialized
  Future<FirebaseAuth> get _lazyAuth async {
    if (_auth != null) return _auth!;

    await FirebaseInitializer.ensureInitialized();
    _auth = FirebaseAuth.instance;
    return _auth!;
  }

  @override
  OTPProviderCapabilities get capabilities => const OTPProviderCapabilities(
        supportsVoiceCalls: false, // Firebase doesn't expose voice call option
        supportsCustomTemplates: false, // Firebase uses fixed templates
        supportsResend: true,
        maxTimeoutSeconds: 120,
        minTimeoutSeconds: 30,
        customFeatures: {
          'auto_verification': true,
          'sms_retrieval': true,
          'provider': 'firebase',
        },
      );

  @override
  Future<OTPResult> sendOTP(String phoneNumber, {OTPOptions? options}) async {
    try {
      // Clean up previous session if phone number changed
      if (phoneNumber != _currentPhoneNumber) {
        await _cleanupPreviousSession();
      }

      _currentPhoneNumber = phoneNumber;
      final completer = Completer<OTPResult>();
      final sessionId = _generateSessionId();
      _sendOtpCompleters[sessionId] = completer;

      // Configure timeout
      final timeoutSeconds = options?.timeoutSeconds ?? 60;

      final auth = await _lazyAuth;
      await auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: Duration(seconds: timeoutSeconds),
        forceResendingToken: _resendToken,

        // OTP sent successfully
        codeSent: (String verificationId, int? resendToken) async {
          _currentVerificationId = verificationId;
          _resendToken = resendToken;

          // Persist session data securely
          await _persistSessionData(phoneNumber, resendToken);

          if (!completer.isCompleted) {
            completer.complete(OTPResult.success(
              verificationId,
              metadata: {
                'phoneNumber': phoneNumber,
                'provider': 'firebase',
                'hasResendToken': resendToken != null,
                'timestamp': DateTime.now().toIso8601String(),
                'sessionId': sessionId,
              },
            ));
          }
        },

        // Auto-verification completed (rare on Android)
        verificationCompleted: (PhoneAuthCredential credential) {
          // Note: This happens rarely and indicates auto-verification
          // The credential contains the verified phone number
          if (!completer.isCompleted) {
            completer.complete(OTPResult.success(
              'auto_verified',
              metadata: {
                'phoneNumber': phoneNumber,
                'provider': 'firebase',
                'autoVerified': true,
                'timestamp': DateTime.now().toIso8601String(),
              },
            ));
          }
        },

        // Verification failed
        verificationFailed: (FirebaseAuthException error) {
          final authError = _mapFirebaseError(error, 'OTP delivery failed');
          if (!completer.isCompleted) {
            completer.complete(OTPResult.failure(
              authError.message,
              metadata: {
                'phoneNumber': phoneNumber,
                'provider': 'firebase',
                'errorCode': error.code,
                'errorMessage': error.message,
                'timestamp': DateTime.now().toIso8601String(),
              },
            ));
          }
        },

        // Auto-retrieval timeout (Android SMS auto-fill timeout)
        codeAutoRetrievalTimeout: (String verificationId) {
          // This is not an error, just means auto-retrieval timed out
          // The user can still manually enter the OTP
          // Store the verification ID as fallback
          _currentVerificationId = verificationId;
        },
      );

      // Set up timeout for the completer
      Timer(Duration(seconds: timeoutSeconds + 10), () {
        if (!completer.isCompleted) {
          completer.complete(OTPResult.failure(
            'OTP delivery timed out. Please try again.',
            metadata: {
              'phoneNumber': phoneNumber,
              'provider': 'firebase',
              'timeout': true,
              'timestamp': DateTime.now().toIso8601String(),
            },
          ));
        }
      });

      return await completer.future;
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace,
          reason: "Firebase OTP send failed");

      throw AuthError.otpDelivery(
        'Failed to send OTP: ${e.toString()}',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<OTPCredential> verifyOTP(String otp) async {
    try {
      if (_currentPhoneNumber == null) {
        throw AuthError.otpVerification(
            'No phone number associated with this verification session');
      }

      if (_currentVerificationId == null) {
        throw AuthError.otpVerification(
            'No active verification session. Please request OTP again.');
      }

      final verifiedPhoneNumber = _currentPhoneNumber!;
      final verificationId = _currentVerificationId!;
      User? user;

      final auth = await _lazyAuth;

      // Handle auto-verification case
      if (verificationId == 'auto_verified') {
        // For auto-verification, we need to get the current user's token
        user = auth.currentUser;
        if (user == null) {
          throw AuthError.otpVerification(
              'Auto-verification failed: no user found');
        }
      } else {
        // Standard OTP verification
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: otp,
        );

        final userCredential = await auth.signInWithCredential(credential);
        user = userCredential.user;

        if (user == null) {
          throw AuthError.otpVerification(
              'Verification succeeded but no user was created');
        }
      }

      // Get the Firebase ID token for VartalapClient authentication
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw AuthError.otpVerification(
            'Failed to retrieve ID token after verification');
      }

      return OTPCredential(
        phoneNumber: verifiedPhoneNumber,
        externalAuthToken: idToken,
        metadata: {
          'provider': 'firebase',
          'verificationId': verificationId,
          'userId': user.uid,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } on FirebaseAuthException catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace,
          reason: "Firebase OTP verification failed");

      final authError = _mapFirebaseError(e, 'OTP verification failed');
      throw authError;
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace,
          reason: "OTP verification unexpected error");

      throw AuthError.otpVerification(
        'Unexpected error during OTP verification: ${e.toString()}',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Resend OTP to the current phone number
  ///
  /// This method uses the stored resend token to resend OTP to the same phone number.
  /// It's a convenience method that calls [sendOTP] with the current phone number.
  Future<OTPResult> resendOTP({OTPOptions? options}) async {
    if (_currentPhoneNumber == null) {
      throw AuthError.otpDelivery('No phone number to resend OTP to');
    }

    return await sendOTP(_currentPhoneNumber!, options: options);
  }

  @override
  void dispose() {
    // Complete any pending completers
    for (final completer in _sendOtpCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete(OTPResult.failure('Provider disposed'));
      }
    }
    _sendOtpCompleters.clear();

    // Clear session data
    _currentVerificationId = null;
    _resendToken = null;
    _currentPhoneNumber = null;
  }

  /// Clean up previous session data
  Future<void> _cleanupPreviousSession() async {
    _resendToken = null;
    try {
      await _storage.deleteAll();
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace,
          reason: "Error cleaning up secure storage");
    }
  }

  /// Persist session data securely
  Future<void> _persistSessionData(String phoneNumber, int? resendToken) async {
    try {
      await _storage.write(key: 'phoneNumber', value: phoneNumber);
      if (resendToken != null) {
        await _storage.write(key: 'resendToken', value: resendToken.toString());
      }
    } catch (e, stackTrace) {
      Crashlytics.recordError(e, stackTrace,
          reason: "Error persisting session data");
    }
  }

  /// Generate a unique session ID for tracking
  String _generateSessionId() {
    return 'otp_${DateTime.now().millisecondsSinceEpoch}_${_currentPhoneNumber.hashCode}';
  }

  /// Map Firebase errors to AuthError
  AuthError _mapFirebaseError(
      FirebaseAuthException firebaseError, String context) {
    String userMessage;
    AuthErrorType errorType;

    switch (firebaseError.code) {
      case 'invalid-phone-number':
        userMessage =
            'Invalid phone number format. Please check and try again.';
        errorType = AuthErrorType.invalidInput;
        break;
      case 'too-many-requests':
        userMessage = 'Too many attempts. Please try again later.';
        errorType = AuthErrorType.otpDelivery;
        break;
      case 'invalid-verification-code':
        userMessage = 'Invalid OTP code. Please check and try again.';
        errorType = AuthErrorType.otpVerification;
        break;
      case 'invalid-verification-id':
        userMessage = 'Verification session expired. Please request a new OTP.';
        errorType = AuthErrorType.sessionExpired;
        break;
      case 'session-expired':
        userMessage = 'OTP session expired. Please request a new OTP.';
        errorType = AuthErrorType.sessionExpired;
        break;
      case 'quota-exceeded':
        userMessage = 'SMS quota exceeded. Please try again later.';
        errorType = AuthErrorType.otpDelivery;
        break;
      case 'network-request-failed':
        userMessage =
            'Network error. Please check your connection and try again.';
        errorType = AuthErrorType.network;
        break;
      default:
        userMessage =
            '$context: ${firebaseError.message ?? firebaseError.code}';
        errorType = AuthErrorType.unknown;
    }

    return AuthError(
      type: errorType,
      message: userMessage,
      technicalDetails:
          'Firebase error: ${firebaseError.code} - ${firebaseError.message}',
      originalError: firebaseError,
    );
  }
}
