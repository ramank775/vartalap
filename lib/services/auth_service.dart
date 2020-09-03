import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

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

  static AuthService _instance;

  AuthService() {
    _auth = FirebaseAuth.instance;
  }

  Future<bool> sendOtp(String phonenumber) {
    Completer<bool> _promise = Completer<bool>();
    _phoneNumber = phonenumber;
    _auth.verifyPhoneNumber(
      timeout: Duration(seconds: 0),
      phoneNumber: _phoneNumber,
      forceResendingToken: _resendToken,
      codeSent: (String verificationId, int resendToken) {
        _resendToken = resendToken;
        _verificationId = verificationId;
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
      var idTokenResult = await result.user.getIdTokenResult();
      _resp.token = idTokenResult.token;
      _resp.status = true;
    } catch (e) {
      _resp.error = e;
      _resp.status = false;
      _resp.phoneNumber = _phoneNumber;
    }
    return _resp;
  }

  bool isLoggedIn() {
    return _auth.currentUser != null;
  }

  String get phoneNumber {
    if (isLoggedIn()) {
      return _auth.currentUser.phoneNumber;
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
  }
}
