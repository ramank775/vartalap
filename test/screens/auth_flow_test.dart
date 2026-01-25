import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/login/login.dart';
import 'package:vartalap/screens/login/verify_otp.dart';
import 'package:vartalap/services/otp/iotp_provider.dart';
import 'package:vartalap/services/vartalap_authenticated_client.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_testing/vartalap_testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockVartalapChatClient mockMessagingClient;
  late VartalapAuthenticatedClient authClient;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Vartalap Test',
      packageName: 'com.one9x.vartalap.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'buildSignature',
    );
    await AppConfig.initialize();

    mockMessagingClient = MockVartalapChatClient(
      tokenManager: MockTokenManager(),
    );
    authClient = VartalapAuthenticatedClient(
      client: VartalapChatClientFlutter(
        apiKey: 'test',
        client: mockMessagingClient,
      ),
      otpProvider: OTPProviderFactory.createTest(),
    );
  });

  Widget createTestableWidget(Widget child) {
    return ChangeNotifierProvider<VartalapAuthenticatedClient>.value(
      value: authClient,
      child: MaterialApp(
        home: child,
        routes: {
          '/verify-otp': (context) => const VerifyOtpWidget(),
        },
      ),
    );
  }

  group('Authentication Flow Widget Tests', () {
    testWidgets('IntroductionScreen navigates to LoginScreen', (tester) async {
      await tester.pumpWidget(createTestableWidget(const IntroductionScreen()));

      expect(find.text('AGREE AND CONTINUE'), findsOneWidget);

      await tester.tap(find.text('AGREE AND CONTINUE'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('LoginScreen handles OTP request and navigation',
        (tester) async {
      await tester.pumpWidget(createTestableWidget(const LoginScreen()));
      await tester.pumpAndSettle();

      debugDumpApp(); // This will print the widget tree to the console

      // Enter phone number
      await tester.enterText(
        find.byType(TextField),
        '1234567890',
      );
      await tester.pump();

      // Tap Next
      await tester.tap(find.text('Next'));

      // Loading indicator should appear
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for OTP to be "sent"
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Should now be on VerifyOtpWidget
      expect(find.byType(VerifyOtpWidget), findsOneWidget);
    });

    testWidgets('VerifyOtpWidget handles successful login', (tester) async {
      // Manually set state to otpSent to simulate being on the verify screen
      await authClient.sendOTP('+11234567890');

      await tester.pumpWidget(createTestableWidget(const VerifyOtpWidget()));

      // Enter "123456" via the numeric keyboard
      for (var digit in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }

      // Tap Confirm
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // State should be authenticated
      expect(authClient.isAuthenticated, true);
    });
  });
}
