import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/auth/otp_provider.dart';
import 'package:vartalap_messaging_flutter/repository/auth_repository.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;

// Manual Mocks
class MockVartalapChatClientFlutter implements VartalapChatClientFlutter {
  String? loggedInUserId;
  bool initCalled = false;
  Profile? profile;
  late AuthRepository auth;

  @override
  Future<String?> getLoggedInUser() async => loggedInUserId;

  @override
  Future<void> init() async {
    initCalled = true;
  }

  @override
  Future<Profile?> getLoggedInUserProfile() async => profile;

  @override
  Future<messaging.LoginResponse> login(messaging.Credential creds) async {
    return messaging.LoginResponse()
      ..username = creds.username
      ..accessKey = 'test-access-key'
      ..status = true
      ..isNew = false;
  }

  @override
  Future<void> logout() async {
    loggedInUserId = null;
    initCalled = false;
    profile = null;
  }

  @override
  void initAuth(IOTPProvider otpProvider) {
    auth = AuthRepository(this, otpProvider);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockOTPProvider implements IOTPProvider {
  bool sendOTPCalled = false;
  bool verifyOTPCalled = false;
  OTPResult sendOTPResult = OTPResult.success('test-id');
  OTPCredential? verifyOTPCredential;

  @override
  Future<OTPResult> sendOTP(String phoneNumber, {Map<String, dynamic>? options}) async {
    sendOTPCalled = true;
    return sendOTPResult;
  }

  @override
  Future<OTPCredential> verifyOTP(String otp) async {
    verifyOTPCalled = true;
    if (verifyOTPCredential == null) {
      throw Exception('Invalid OTP');
    }
    return verifyOTPCredential!;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthRepository auth;
  late MockVartalapChatClientFlutter mockClient;
  late MockOTPProvider mockOtpProvider;

  setUp(() {
    mockClient = MockVartalapChatClientFlutter();
    mockOtpProvider = MockOTPProvider();
    mockClient.initAuth(mockOtpProvider);
    auth = mockClient.auth;
  });

  group('AuthRepository Tests', () {
    test('Initial state is unauthenticated', () {
      expect(auth.state, AuthState.unauthenticated);
      expect(auth.isAuthenticated, false);
    });

    test('checkAuth() - user not logged in', () async {
      mockClient.loggedInUserId = null;
      await auth.checkAuth();
      expect(auth.state, AuthState.unauthenticated);
      expect(mockClient.initCalled, false);
    });

    test('checkAuth() - user already logged in', () async {
      mockClient.loggedInUserId = '+1234567890';
      mockClient.profile = Profile(
        userId: '+1234567890', 
        name: 'Test User',
        email: 'test@example.com',
        image: '',
      );
      
      await auth.checkAuth();
      
      expect(auth.state, AuthState.authenticated);
      expect(auth.isAuthenticated, true);
      expect(mockClient.initCalled, true);
      expect(auth.currentUser?.name, 'Test User');
    });

    test('sendOTP() success', () async {
      await auth.sendOTP('+1234567890');
      
      expect(mockOtpProvider.sendOTPCalled, true);
      expect(auth.state, AuthState.otpSent);
      expect(auth.currentPhoneNumber, '+1234567890');
    });

    test('sendOTP() failure', () async {
      mockOtpProvider.sendOTPResult = OTPResult.failure('Network Error');
      
      await auth.sendOTP('+1234567890');
      
      expect(auth.state, AuthState.error);
      expect(auth.lastError, 'Network Error');
    });

    test('verifyOTP() success', () async {
      mockOtpProvider.verifyOTPCredential = OTPCredential(
        phoneNumber: '+1234567890',
        externalAuthToken: 'token',
      );
      // Simulate successful login returning user ID
      mockClient.loggedInUserId = '+1234567890';
      mockClient.profile = Profile(
        userId: '+1234567890', 
        name: 'Verified User',
        email: 'verified@example.com',
        image: '',
      );

      await auth.verifyOTP('123456');
      
      expect(mockOtpProvider.verifyOTPCalled, true);
      expect(auth.state, AuthState.authenticated);
      expect(auth.currentUser?.name, 'Verified User');
    });

    test('logout() clears state', () async {
      // Setup authenticated state
      mockClient.loggedInUserId = '+1234567890';
      await auth.checkAuth();
      expect(auth.isAuthenticated, true);
      
      await auth.logout();
      
      expect(auth.isAuthenticated, false);
      expect(auth.state, AuthState.unauthenticated);
      expect(auth.currentUser, null);
    });
  });
}
