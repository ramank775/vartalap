import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vartalap/services/api_service.dart';

class AuthResponse {
  String phoneNumber;
  String token;
  bool status;
  dynamic error;
}

class AuthService {
  FirebaseAuth _auth;
  String _phoneNumber;
  int _resendToken;
  String _verificationId;
  User _user;
  static FlutterSecureStorage _storage = new FlutterSecureStorage();
  static AuthService _instance;

  AuthService() {
    _auth = FirebaseAuth.instance;
    _auth.authStateChanges().listen((event) {
      _user = event;
    });
  }

  Future<bool> sendOtp(String phonenumber) async {
    Completer<bool> _promise = Completer<bool>();
    if (phonenumber != _phoneNumber) {
      _resendToken = null;
      try {
        await _storage.deleteAll();
      } catch (e) {}
    }
    _phoneNumber = phonenumber;
    _auth.verifyPhoneNumber(
      timeout: Duration(seconds: 0),
      phoneNumber: _phoneNumber,
      forceResendingToken: _resendToken,
      codeSent: (String verificationId, int resendToken) async {
        _resendToken = resendToken;
        _verificationId = verificationId;
        try {
          await _storage.write(
              key: 'resendToken', value: resendToken.toString());
          await _storage.write(key: 'phoneNumber', value: _phoneNumber);
        } catch (e) {}

        _promise.complete(true);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        print("AutoRetrievalTimeout: $verificationId");
      },
      verificationCompleted: (phoneAuthCredential) {
        print("VerificationCompleted: $phoneAuthCredential");
      },
      verificationFailed: (error) {
        _promise.complete(false);
      },
    );
    return _promise.future;
  }

  Future<bool> reSendOtp() {
    return sendOtp(_phoneNumber);
  }

  Future<AuthResponse> verify(String otp) async {
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId, smsCode: otp);
    AuthResponse _resp = AuthResponse();
    try {
      var result = await _auth.signInWithCredential(credential);
      _resp.phoneNumber = _phoneNumber;
      _user = result.user;
      var idTokenResult = await result.user.getIdTokenResult();
      _resp.token = idTokenResult.token;
      _resp.status = true;
    } catch (e) {
      _resp.error = e;
      _resp.status = false;
      _resp.phoneNumber = _phoneNumber;
    }
    if (_resp.status) {
      try {
        await ApiService.login(_phoneNumber);
      } catch (e) {
        await _auth.signOut();
        _resp.error = e;
        _resp.status = false;
      }
    }

    return _resp;
  }

  bool isLoggedIn() {
    return _user != null;
  }

  String get phoneNumber {
    if (isLoggedIn()) {
      return _user.phoneNumber;
    }
    return null;
  }

  Future<String> get idToken {
    if (isLoggedIn()) {
      return _user.getIdToken();
    }
    return null;
  }

  static AuthService get instance {
    if (_instance == null) {
      _instance = AuthService();
    }
    return _instance;
  }

  static Future<void> init() async {
    await Firebase.initializeApp();
    try {
      String _phoneNumber = await _storage.read(key: 'phoneNumber');
      if (_phoneNumber != null) {
        _instance._phoneNumber = _phoneNumber;
      }
      String _resendToken = await _storage.read(key: 'resendToken');
      if (_resendToken != null) {
        _instance._resendToken = int.parse(_resendToken);
      }
      _instance._user = _instance._auth.currentUser;
    } catch (e) {}
  }
}
