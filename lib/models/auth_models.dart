/// Authentication-related models for the unified authentication system
///
/// This file contains all models related to authentication, OTP verification,
/// and auth state management that decouple the app from specific OTP providers.
library;

/// Authentication state enum representing the current state of user authentication
enum AuthState {
  /// User is not authenticated
  unauthenticated,

  /// Currently sending OTP to the user's phone
  sendingOTP,

  /// OTP has been successfully sent and user can enter it
  otpSent,

  /// Currently verifying the OTP and authenticating with VartalapClient
  verifyingOTP,

  /// User is successfully authenticated with VartalapClient
  authenticated,

  /// An error occurred during any phase of authentication
  error,
}

/// Result of OTP sending operation
class OTPResult {
  /// Unique identifier for the OTP verification session
  final String verificationId;

  /// Whether the OTP was sent successfully
  final bool success;

  /// Error message if the operation failed
  final String? errorMessage;

  /// Optional provider-specific data
  final Map<String, dynamic>? metadata;

  const OTPResult({
    required this.verificationId,
    required this.success,
    this.errorMessage,
    this.metadata,
  });

  /// Create a successful OTP result
  factory OTPResult.success(String verificationId, {Map<String, dynamic>? metadata}) {
    return OTPResult(
      verificationId: verificationId,
      success: true,
      metadata: metadata,
    );
  }

  /// Create a failed OTP result
  factory OTPResult.failure(String errorMessage, {Map<String, dynamic>? metadata}) {
    return OTPResult(
      verificationId: '',
      success: false,
      errorMessage: errorMessage,
      metadata: metadata,
    );
  }

  @override
  String toString() {
    return 'OTPResult(verificationId: $verificationId, success: $success, errorMessage: $errorMessage)';
  }
}

/// Credential object that contains the verification information for VartalapClient
/// This is provider-agnostic and can be created from any OTP provider
class OTPCredential {
  /// The phone number that was verified
  final String phoneNumber;

  /// The external authentication token (e.g., Firebase ID token)
  final String externalAuthToken;

  /// Optional notification token for push notifications
  final String? notificationToken;

  /// Provider-specific metadata
  final Map<String, dynamic>? metadata;

  const OTPCredential({
    required this.phoneNumber,
    required this.externalAuthToken,
    this.notificationToken,
    this.metadata,
  });

  /// Convert to VartalapClient Credential format
  Map<String, dynamic> toVartalapCredential() {
    return {
      'username': phoneNumber,
      'externalAuthToken': externalAuthToken,
      'notificationToken': notificationToken,
    };
  }

  @override
  String toString() {
    return 'OTPCredential(phoneNumber: $phoneNumber, hasToken: ${externalAuthToken.isNotEmpty})';
  }
}

/// Authentication error types for better error categorization
enum AuthErrorType {
  /// Error occurred during OTP delivery
  otpDelivery,

  /// Error occurred during OTP verification
  otpVerification,

  /// Error occurred during VartalapClient authentication
  clientAuthentication,

  /// Network-related error
  network,

  /// Invalid input from user
  invalidInput,

  /// Session expired or invalid state
  sessionExpired,

  /// Unknown or unexpected error
  unknown,
}

/// Comprehensive authentication error with categorization
class AuthError implements Exception {
  /// Type of authentication error
  final AuthErrorType type;

  /// User-friendly error message
  final String message;

  /// Technical error details for debugging
  final String? technicalDetails;

  /// Original exception that caused this error
  final Object? originalError;

  /// Stack trace for debugging
  final StackTrace? stackTrace;

  const AuthError({
    required this.type,
    required this.message,
    this.technicalDetails,
    this.originalError,
    this.stackTrace,
  });

  /// Create an OTP delivery error
  factory AuthError.otpDelivery(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AuthError(
      type: AuthErrorType.otpDelivery,
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// Create an OTP verification error
  factory AuthError.otpVerification(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AuthError(
      type: AuthErrorType.otpVerification,
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// Create a VartalapClient authentication error
  factory AuthError.clientAuthentication(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AuthError(
      type: AuthErrorType.clientAuthentication,
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// Create a network error
  factory AuthError.network(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AuthError(
      type: AuthErrorType.network,
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() {
    return 'AuthError(type: $type, message: $message, technicalDetails: $technicalDetails)';
  }
}

/// Configuration options for OTP sending
class OTPOptions {
  /// Timeout for OTP delivery in seconds
  final int? timeoutSeconds;

  /// Whether to use voice call instead of SMS
  final bool useVoiceCall;

  /// Custom template or message for OTP
  final String? customTemplate;

  /// Provider-specific options
  final Map<String, dynamic>? providerOptions;

  const OTPOptions({
    this.timeoutSeconds,
    this.useVoiceCall = false,
    this.customTemplate,
    this.providerOptions,
  });

  /// Create default OTP options
  factory OTPOptions.defaults() {
    return const OTPOptions(
      timeoutSeconds: 60,
      useVoiceCall: false,
    );
  }
}