// Stub: Firebase removed per V3_ARCHITECTURE.md decision 1. Replacement pending v3 auth/push/crash work.
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vartalap/services/crashlystics.dart';

class AuthResponse {
  late String phoneNumber;
  late String token;
  late bool status;
  late dynamic error;
}

class AuthService {
  String? _phoneNumber;
  // ignore: unused_field
  int? _resendToken;
  // ignore: unused_field
  String? _verificationId;
  static FlutterSecureStorage _storage = new FlutterSecureStorage();
  static AuthService? _instance;

  StreamController<bool> authStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get authStateChange => authStateController.stream;
  AuthService();

  Future<bool> sendOtp(String phonenumber) async {
    throw UnimplementedError(
        'Firebase auth removed; self-hosted OTP pending per docs/AUTH_CONTRACT.md');
  }

  Future<bool> reSendOtp() {
    throw UnimplementedError(
        'Firebase auth removed; self-hosted OTP pending per docs/AUTH_CONTRACT.md');
  }

  Future<AuthResponse> verify(String otp) async {
    throw UnimplementedError(
        'Firebase auth removed; self-hosted OTP pending per docs/AUTH_CONTRACT.md');
  }

  bool isLoggedIn() {
    return false;
  }

  Future<void> signout() async {
    authStateController.sink.add(false);
  }

  String? get phoneNumber {
    return _phoneNumber;
  }

  Future<String?> get idToken {
    return Future.value(null);
  }

  dispose() {
    this.authStateController.close();
  }

  static AuthService get instance {
    if (_instance == null) {
      _instance = AuthService();
    }
    return _instance!;
  }

  static Future<void> init() async {
    try {
      String? _phoneNumber = await _storage.read(key: 'phoneNumber');
      if (_phoneNumber != null) {
        instance._phoneNumber = _phoneNumber;
      }
      String? _resendToken = await _storage.read(key: 'resendToken');
      if (_resendToken != null) {
        instance._resendToken = int.parse(_resendToken);
      }
    } catch (e, stack) {
      Crashlytics.recordError(e, stack,
          reason: "Error while initializing auth service");
    }
  }
}
