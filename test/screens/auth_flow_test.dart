import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/login/login.dart';
import 'package:vartalap/screens/login/verify_otp.dart';
import 'package:vartalap/services/otp/iotp_provider.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_testing/vartalap_testing.dart';
import 'test_app_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockVartalapChatClient mockMessagingClient;
  late VartalapChatClientFlutter client;

  setUp(() async {
    await TestAppWrapper.setup();

    mockMessagingClient = MockVartalapChatClient(
      tokenManager: MockTokenManager(),
    );
    client = VartalapChatClientFlutter(
      apiKey: 'test',
      client: mockMessagingClient,
      inMemory: true,
    );
    client.initAuth(MockOTPProvider());
  });

  tearDown(() {
    client.dispose();
  });

  Widget createTestableWidget(Widget child) {
    return MultiProvider(
      providers: [
        Provider<VartalapChatClientFlutter>.value(value: client),
        ChangeNotifierProvider<AuthRepository>.value(value: client.auth),
      ],
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
      await tester.runAsync(() async {
        await tester.pumpWidget(createTestableWidget(const LoginScreen()));
        // Wait for country code initialization
        await Future.delayed(const Duration(seconds: 1));
      });
      await tester.pumpAndSettle();

      // Enter phone number - IntlPhoneField uses a TextField internally
      final phoneField = find.byType(IntlPhoneField);
      expect(phoneField, findsOneWidget);

      final textField =
          find.descendant(of: phoneField, matching: find.byType(TextField));
      await tester.enterText(textField, '1234567890');
      await tester.pumpAndSettle();

            // Tap Next
            await tester.tap(find.text('Next'));
      
            // Loading indicator should appear in a dialog
            // Use multiple pumps to ensure we catch the dialog before it potentially closes
            await tester.pump(); 
            await tester.pump(const Duration(milliseconds: 100));
            
            expect(find.textContaining('Please wait'), findsOneWidget);
      
            // Wait for OTP to be "sent" (500ms delay in mock + animation)
            await tester.runAsync(() async {
              await Future.delayed(const Duration(seconds: 1));
            });
            await tester.pumpAndSettle();
            // Should now be on VerifyOtpWidget
      expect(find.byType(VerifyOtpWidget), findsOneWidget);
    });

    testWidgets('VerifyOtpWidget handles successful login', (tester) async {
      await tester.runAsync(() async {
        // Manually set state to otpSent to simulate being on the verify screen
        await client.auth.sendOTP('+11234567890');

        await tester.pumpWidget(createTestableWidget(const VerifyOtpWidget()));

        // Enter "123456" via the numeric keyboard
        for (var digit in ['1', '2', '3', '4', '5', '6']) {
          await tester.tap(find.text(digit));
          await tester.pump();
        }

        // Tap Confirm
        await tester.tap(find.text('Confirm'));

        // Wait for async login and database init to complete
        await Future.delayed(const Duration(seconds: 2));
      });

      await tester.pumpAndSettle();

      // State should be authenticated
      expect(client.auth.isAuthenticated, true);
    });
  });
}
