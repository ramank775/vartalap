/// OTP Provider abstraction interface
///
/// This interface defines the contract for OTP delivery services, allowing
/// easy replacement of OTP providers (Firebase, Twilio, AWS SNS, etc.)
/// without affecting the core authentication logic.
library;

import 'package:vartalap/models/auth_models.dart';

/// Abstract interface for OTP (One-Time Password) providers
///
/// This interface abstracts the OTP delivery mechanism from the authentication
/// logic, allowing Firebase to be easily replaced with other OTP services
/// like Twilio, AWS SNS, or custom SMS gateways.
///
/// The provider is responsible only for OTP delivery and verification,
/// NOT for authentication state management. VartalapAuthenticatedClient
/// remains the single source of truth for authentication.
abstract class IOTPProvider {
  /// Send OTP to the specified phone number
  ///
  /// This method initiates the OTP delivery process. The implementation
  /// should handle provider-specific logic (Firebase phone auth,
  /// Twilio SMS API, etc.) and return an [OTPResult] with verification details.
  ///
  /// Parameters:
  /// - [phoneNumber]: The phone number in international format (e.g., +1234567890)
  /// - [options]: Optional configuration for OTP delivery
  ///
  /// Returns: [OTPResult] containing verification ID and success status
  ///
  /// Throws: [AuthError] if OTP delivery fails
  ///
  /// Example:
  /// ```dart
  /// final result = await provider.sendOTP('+1234567890');
  /// if (result.success) {
  ///   // Proceed to OTP verification
  /// }
  /// ```
  Future<OTPResult> sendOTP(
    String phoneNumber, {
    OTPOptions? options,
  });

  /// Verify the OTP entered by the user
  ///
  /// This method validates the OTP code against the verification session
  /// and returns a credential that can be used for VartalapClient authentication.
  ///
  /// Parameters:
  /// - [verificationId]: The verification ID returned from [sendOTP]
  /// - [otp]: The OTP code entered by the user
  ///
  /// Returns: [OTPCredential] containing authentication token for VartalapClient
  ///
  /// Throws: [AuthError] if OTP verification fails
  ///
  /// Example:
  /// ```dart
  /// final credential = await provider.verifyOTP(verificationId, '123456');
  /// await vartalapClient.login(credential);
  /// ```
  Future<OTPCredential> verifyOTP(
    String verificationId,
    String otp,
  );

  /// Get provider capabilities
  ///
  /// Returns information about what this provider supports
  /// (voice calls, custom templates, etc.)
  OTPProviderCapabilities get capabilities;

  /// Clean up provider resources
  ///
  /// This method should be called when the provider is no longer needed
  /// to clean up any listeners, timers, or other resources.
  void dispose();
}

/// Capabilities supported by an OTP provider
class OTPProviderCapabilities {
  /// Whether the provider supports voice calls for OTP delivery
  final bool supportsVoiceCalls;

  /// Whether the provider supports custom OTP templates
  final bool supportsCustomTemplates;

  /// Whether the provider supports resending OTP
  final bool supportsResend;

  /// Maximum timeout supported by the provider (in seconds)
  final int maxTimeoutSeconds;

  /// Minimum timeout supported by the provider (in seconds)
  final int minTimeoutSeconds;

  /// Provider-specific features
  final Map<String, dynamic> customFeatures;

  const OTPProviderCapabilities({
    this.supportsVoiceCalls = false,
    this.supportsCustomTemplates = false,
    this.supportsResend = true,
    this.maxTimeoutSeconds = 300,
    this.minTimeoutSeconds = 30,
    this.customFeatures = const {},
  });

  /// Create capabilities for a basic SMS-only provider
  factory OTPProviderCapabilities.smsOnly() {
    return const OTPProviderCapabilities(
      supportsVoiceCalls: false,
      supportsCustomTemplates: false,
      supportsResend: true,
      maxTimeoutSeconds: 120,
      minTimeoutSeconds: 30,
    );
  }

  /// Create capabilities for a full-featured provider
  factory OTPProviderCapabilities.fullFeatured() {
    return const OTPProviderCapabilities(
      supportsVoiceCalls: true,
      supportsCustomTemplates: true,
      supportsResend: true,
      maxTimeoutSeconds: 600,
      minTimeoutSeconds: 15,
    );
  }
}

/// Factory for creating OTP providers
///
/// This factory allows for easy swapping of OTP providers based on
/// configuration or feature flags.
abstract class OTPProviderFactory {
  /// Create the default OTP provider
  ///
  /// This should return the primary OTP provider for the application.
  /// Can be configured through environment variables or app configuration.
  static IOTPProvider createDefault() {
    // This will be implemented when we create the concrete providers
    throw UnimplementedError('OTPProviderFactory.createDefault() not implemented yet');
  }

  /// Create a Firebase OTP provider
  ///
  /// Returns a Firebase-based OTP provider implementation.
  static IOTPProvider createFirebase() {
    // This will be implemented when we create FirebaseOTPProvider
    throw UnimplementedError('OTPProviderFactory.createFirebase() not implemented yet');
  }

  /// Create a test OTP provider for development/testing
  ///
  /// Returns a mock provider that always succeeds for testing purposes.
  static IOTPProvider createTest() {
    return TestOTPProvider();
  }
}

/// Test implementation of IOTPProvider for development and testing
///
/// This provider always succeeds and doesn't actually send any OTP.
/// Useful for development, testing, and debugging.
class TestOTPProvider implements IOTPProvider {
  static const String _testVerificationId = 'test_verification_id';
  static const String _testToken = 'test_auth_token';

  @override
  OTPProviderCapabilities get capabilities => OTPProviderCapabilities.fullFeatured();

  @override
  Future<OTPResult> sendOTP(String phoneNumber, {OTPOptions? options}) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    return OTPResult.success(
      _testVerificationId,
      metadata: {
        'phoneNumber': phoneNumber,
        'provider': 'test',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  @override
  Future<OTPCredential> verifyOTP(String verificationId, String otp) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    // Accept any OTP for testing
    if (verificationId != _testVerificationId) {
      throw AuthError.otpVerification('Invalid verification ID');
    }

    return OTPCredential(
      phoneNumber: '+1234567890', // Mock phone number
      externalAuthToken: _testToken,
      metadata: {
        'provider': 'test',
        'verificationId': verificationId,
        'otp': otp,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  @override
  void dispose() {
    // Nothing to clean up for test provider
  }
}