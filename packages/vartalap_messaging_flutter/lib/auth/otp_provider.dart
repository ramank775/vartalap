import 'dart:async';

abstract class IOTPProvider {
  Future<OTPResult> sendOTP(
    String phoneNumber, {
    Map<String, dynamic>? options,
  });

  Future<OTPCredential> verifyOTP(String otp);

  void dispose();
}

class OTPResult {
  final bool success;
  final String? verificationId;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;

  OTPResult({
    required this.success,
    this.verificationId,
    this.errorMessage,
    this.metadata,
  });

  factory OTPResult.success(String verificationId, {Map<String, dynamic>? metadata}) {
    return OTPResult(
      success: true,
      verificationId: verificationId,
      metadata: metadata,
    );
  }

  factory OTPResult.failure(String errorMessage, {Map<String, dynamic>? metadata}) {
    return OTPResult(
      success: false,
      errorMessage: errorMessage,
      metadata: metadata,
    );
  }
}

class OTPCredential {
  final String phoneNumber;
  final String externalAuthToken;
  final Map<String, dynamic>? metadata;

  OTPCredential({
    required this.phoneNumber,
    required this.externalAuthToken,
    this.metadata,
  });

  Map<String, dynamic> toVartalapCredential({required String deviceId}) {
    return {
      "username": phoneNumber,
      "authToken": externalAuthToken,
      "deviceId": deviceId,
    };
  }
}

class OTPOptions {
  final int? timeoutSeconds;
  final bool useVoiceCall;
  final String? customTemplate;
  final Map<String, dynamic>? providerOptions;

  const OTPOptions({
    this.timeoutSeconds,
    this.useVoiceCall = false,
    this.customTemplate,
    this.providerOptions,
  });

  factory OTPOptions.defaults() {
    return const OTPOptions(
      timeoutSeconds: 60,
      useVoiceCall: false,
    );
  }
}

enum AuthErrorType {
  otpDelivery,
  otpVerification,
  clientAuthentication,
  network,
  invalidInput,
  sessionExpired,
  unknown,
}

class AuthError implements Exception {
  final AuthErrorType type;
  final String message;
  final String? technicalDetails;
  final Object? originalError;
  final StackTrace? stackTrace;

  const AuthError({
    required this.type,
    required this.message,
    this.technicalDetails,
    this.originalError,
    this.stackTrace,
  });

  factory AuthError.otpDelivery(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AuthError(
      type: AuthErrorType.otpDelivery,
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory AuthError.otpVerification(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AuthError(
      type: AuthErrorType.otpVerification,
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory AuthError.clientAuthentication(String message, {Object? originalError, StackTrace? stackTrace}) {
    return AuthError(
      type: AuthErrorType.clientAuthentication,
      message: message,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() => 'AuthError($type): $message';
}

class OTPProviderCapabilities {
  final bool canResend;
  final bool supportsVoice;
  final bool supportsEmail;

  const OTPProviderCapabilities({
    this.canResend = true,
    this.supportsVoice = false,
    this.supportsEmail = false,
  });
}