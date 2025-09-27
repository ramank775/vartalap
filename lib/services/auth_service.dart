import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vartalap/services/crashlystics.dart';
import 'package:vartalap/services/push_notification_service.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class AuthResponse {
  late String phoneNumber;
  late String token;
  late bool status;
  late dynamic error;
}

class AuthService {
  final VartalapChatClientFlutter chatClient;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _phoneNumber;
  int? _resendToken;
  late String _verificationId;
  User? _user;
  static final FlutterSecureStorage _storage = FlutterSecureStorage();
  static AuthService? _instance;

  StreamController<bool> authStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get authStateChange => authStateController.stream;
  AuthService(this.chatClient) {
    _auth.authStateChanges().listen((event) {
      _user = event;
    });
  }

  Future<bool> sendOtp(String phonenumber) async {
    Completer<bool> promise = Completer<bool>();
    if (phonenumber != _phoneNumber) {
      _resendToken = null;
      try {
        await _storage.deleteAll();
      } catch (e, stack) {
        Crashlytics.recordError(e, stack,
            reason: "Error while access secure storage");
      }
    }
    _phoneNumber = phonenumber;
    _auth.verifyPhoneNumber(
      timeout: Duration(seconds: 0),
      phoneNumber: _phoneNumber!,
      forceResendingToken: _resendToken,
      codeSent: (String verificationId, int? resendToken) async {
        _resendToken = resendToken;
        _verificationId = verificationId;
        try {
          await _storage.write(
              key: 'resendToken', value: resendToken.toString());
          await _storage.write(key: 'phoneNumber', value: _phoneNumber);
        } catch (e, stack) {
          Crashlytics.recordError(e, stack,
              reason: "Error while access secure storage");
        }

        promise.complete(true);
      },
      codeAutoRetrievalTimeout: (verificationId) {},
      verificationCompleted: (phoneAuthCredential) {},
      verificationFailed: (error) {
        promise.complete(false);
      },
    );
    return promise.future;
  }

  Future<bool> reSendOtp() {
    return sendOtp(_phoneNumber!);
  }

  Future<AuthResponse> verify(String otp) async {
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: otp,
    );
    AuthResponse resp = AuthResponse();
    try {
      var result = await _auth.signInWithCredential(credential);
      resp.phoneNumber = _phoneNumber!;
      _user = result.user;
      var idTokenResult = await result.user!.getIdTokenResult();
      resp.token = idTokenResult.token!;
      resp.status = true;
    } catch (e, stack) {
      resp.error = e;
      resp.status = false;
      resp.phoneNumber = _phoneNumber!;
      Crashlytics.recordError(e, stack,
          reason: "Error while authentication with firebase");
    }
    if (resp.status) {
      try {
        final notificationToken = await PushNotificationService.instance.token;
        final cred = Credential(
          username: _phoneNumber!,
          externalAuthToken: resp.token,
          notificationToken: notificationToken,
        );
        await chatClient.client.login(cred);
        authStateController.sink.add(true);
      } catch (e, stack) {
        Crashlytics.recordError(e, stack, reason: "Login api service failed");
        await _auth.signOut();
        resp.error = e;
        resp.status = false;
      }
    }

    return resp;
  }

  bool isLoggedIn() {
    return _user != null;
  }

  Future<void> signout() async {
    await _auth.signOut();
    authStateController.sink.add(false);
  }

  String? get phoneNumber {
    if (isLoggedIn()) {
      return _user!.phoneNumber;
    }
    return null;
  }

  Future<String?> get idToken {
    if (isLoggedIn()) {
      return _user!.getIdToken();
    }
    return Future.value(null);
  }

  void dispose() {
    authStateController.close();
  }

  static AuthService get instance {
    if (_instance == null) {
      throw Exception("AuthService not initialized");
    }
    return _instance!;
  }

  static Future<void> init(VartalapChatClientFlutter client) async {
    try {
      _instance ??= AuthService(client);
      String? phoneNumber = await _storage.read(key: 'phoneNumber');
      if (phoneNumber != null) {
        instance._phoneNumber = phoneNumber;
      }
      String? resendToken = await _storage.read(key: 'resendToken');
      if (resendToken != null) {
        instance._resendToken = int.parse(resendToken);
      }
      instance._user = _instance!._auth.currentUser;
    } catch (e, stack) {
      Crashlytics.recordError(e, stack,
          reason: "Error while initializing auth service");
    }
  }
}
