import 'package:flutter/foundation.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

// Re-export from package
export 'package:vartalap_messaging_flutter/auth/otp_provider.dart';

/// Test implementation of IOTPProvider for development and testing
class TestOTPProvider implements IOTPProvider {
  static const String _testVerificationId = 'test_verification_id';
  static const String _testToken = 'test_auth_token';
  static const String _correctOTP = '123456';

  String? _currentPhoneNumber;

  @override
  Future<OTPResult> sendOTP(String phoneNumber, {Map<String, dynamic>? options}) async {
    _currentPhoneNumber = phoneNumber;

    if (!AppConfig.isTesting) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    debugPrint('[TEST OTP] Phone: $phoneNumber');
    debugPrint('[TEST OTP] Use OTP: $_correctOTP');

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
  Future<OTPCredential> verifyOTP(String otp) async {
    if (!AppConfig.isTesting) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (_currentPhoneNumber == null) {
      throw const AuthError(
          type: AuthErrorType.otpVerification,
          message: 'No active OTP session. Please request OTP first.');
    }

    if (otp != _correctOTP) {
      throw const AuthError(
          type: AuthErrorType.otpVerification,
          message: 'Invalid OTP. Use "$_correctOTP" for test mode.');
    }

    return OTPCredential(
      phoneNumber: _currentPhoneNumber!,
      externalAuthToken: _testToken,
      metadata: {
        'provider': 'test',
        'verificationId': _testVerificationId,
        'otp': otp,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  @override
  void dispose() {
    _currentPhoneNumber = null;
  }
}

/// Simple Mock implementation

class MockOTPProvider extends TestOTPProvider {

  @override

  Future<OTPResult> sendOTP(String phoneNumber, {Map<String, dynamic>? options}) async {

    await Future.delayed(const Duration(milliseconds: 500));

    return super.sendOTP(phoneNumber, options: options);

  }



  @override

  Future<OTPCredential> verifyOTP(String otp) async {

    await Future.delayed(const Duration(milliseconds: 500));

    return super.verifyOTP(otp);

  }

}
