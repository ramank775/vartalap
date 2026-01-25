import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/models/auth_models.dart';
import 'package:vartalap/services/otp/iotp_provider.dart';
import 'package:vartalap/services/vartalap_authenticated_client.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;

// Manual Mocks
class MockVartalapChatClientFlutter implements VartalapChatClientFlutter {
  String? loggedInUserId;
  bool initCalled = false;
  Profile? profile;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockOTPProvider implements IOTPProvider {
  bool sendOTPCalled = false;
  bool verifyOTPCalled = false;
  OTPResult sendOTPResult = OTPResult.success('test-id');
  OTPCredential? verifyOTPCredential;

  @override
  Future<OTPResult> sendOTP(String phoneNumber, {OTPOptions? options}) async {
    sendOTPCalled = true;
    return sendOTPResult;
  }

  @override
  Future<OTPCredential> verifyOTP(String otp) async {
    verifyOTPCalled = true;
    if (verifyOTPCredential == null) {
      throw AuthError.otpVerification('Invalid OTP');
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

  late VartalapAuthenticatedClient authClient;
  late MockVartalapChatClientFlutter mockClient;
  late MockOTPProvider mockOtpProvider;

  setUp(() {
    mockClient = MockVartalapChatClientFlutter();
    mockOtpProvider = MockOTPProvider();
    authClient = VartalapAuthenticatedClient(
      client: mockClient,
      otpProvider: mockOtpProvider,
    );
  });

  group('VartalapAuthenticatedClient Tests', () {
    test('Initial state is unauthenticated', () {
      expect(authClient.state, AuthState.unauthenticated);
      expect(authClient.isAuthenticated, false);
    });

    test('initialize() - user not logged in', () async {
      mockClient.loggedInUserId = null;
      await authClient.initialize();
      expect(authClient.state, AuthState.unauthenticated);
      expect(mockClient.initCalled, false);
    });

    test('initialize() - user already logged in', () async {
      mockClient.loggedInUserId = '+1234567890';
      mockClient.profile = Profile(
        userId: '+1234567890', 
        name: 'Test User',
        email: 'test@example.com',
        image: '',
      );
      
      await authClient.initialize();
      
      expect(authClient.state, AuthState.authenticated);
      expect(authClient.isAuthenticated, true);
      expect(mockClient.initCalled, true);
      expect(authClient.currentUser?.name, 'Test User');
    });

    test('sendOTP() success', () async {
      await authClient.sendOTP('+1234567890');
      
      expect(mockOtpProvider.sendOTPCalled, true);
      expect(authClient.state, AuthState.otpSent);
      expect(authClient.currentPhoneNumber, '+1234567890');
    });

    test('sendOTP() failure', () async {
      mockOtpProvider.sendOTPResult = OTPResult.failure('Network Error');
      
      await authClient.sendOTP('+1234567890');
      
      expect(authClient.state, AuthState.error);
      expect(authClient.lastError, 'Network Error');
    });

    test('verifyOTPAndLogin() success', () async {
      mockOtpProvider.verifyOTPCredential = const OTPCredential(
        phoneNumber: '+1234567890',
        externalAuthToken: 'token',
      );
      mockClient.loggedInUserId = '+1234567890';
      mockClient.profile = Profile(
        userId: '+1234567890', 
        name: 'Verified User',
        email: 'verified@example.com',
        image: '',
      );

      // We need to mock the login call as well
      // Since we use noSuchMethod, it might just work if we don't call it,
      // but verifyOTPAndLogin calls client.login(vartalapCredential)
      
      await authClient.verifyOTPAndLogin('123456');
      
      expect(mockOtpProvider.verifyOTPCalled, true);
      expect(authClient.state, AuthState.authenticated);
      expect(authClient.currentUser?.name, 'Verified User');
    });

    test('logout() clears state', () async {
      // Setup authenticated state
      mockClient.loggedInUserId = '+1234567890';
      await authClient.initialize();
      expect(authClient.isAuthenticated, true);
      
      await authClient.logout();
      
      expect(authClient.isAuthenticated, false);
      expect(authClient.state, AuthState.unauthenticated);
      expect(authClient.currentUser, null);
    });
  });
}
