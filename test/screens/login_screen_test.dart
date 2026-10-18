/// LoginScreen widget tests: WhatsApp-style country row + code field
/// kept in sync, E.164 validation gating "Send OTP", remembered country.
library vartalap.screens.login_screen_test;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/screens/login/login.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/utils/countries.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpLogin(
    WidgetTester tester, {
    required _FakeAuthService authService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authService: authService)),
    );
    await tester.pumpAndSettle();
  }

  String codeText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('countryCodeField')))
      .controller!
      .text;

  ElevatedButton nextButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byType(ElevatedButton));

  testWidgets('defaults to India (+91) with no saved country or SIM',
      (tester) async {
    await pumpLogin(tester, authService: _FakeAuthService());

    expect(codeText(tester), '91');
    expect(find.textContaining('India'), findsOneWidget);
    expect(nextButton(tester).onPressed, isNull);
  });

  testWidgets('valid phone sends E.164, ignoring typed separators',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpLogin(tester, authService: auth);

    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '99999-99999',
    );
    await tester.pumpAndSettle();
    expect(nextButton(tester).onPressed, isNotNull);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(auth.sentPhones, ['+919999999999']);
  });

  testWidgets('typing a code picks its country; unknown code disables Next',
      (tester) async {
    await pumpLogin(tester, authService: _FakeAuthService());
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '2025550123',
    );

    await tester.enterText(find.byKey(const Key('countryCodeField')), '1');
    await tester.pumpAndSettle();
    expect(find.textContaining('United States'), findsOneWidget);
    expect(nextButton(tester).onPressed, isNotNull);

    await tester.enterText(find.byKey(const Key('countryCodeField')), '999');
    await tester.pumpAndSettle();
    expect(find.text('Invalid country code'), findsOneWidget);
    expect(nextButton(tester).onPressed, isNull);
  });

  testWidgets('picking a country from the list fills its code', (tester) async {
    final auth = _FakeAuthService();
    await pumpLogin(tester, authService: auth);

    await tester.tap(find.byKey(const Key('countryPicker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search country or code'),
      'canada',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canada'));
    await tester.pumpAndSettle();

    // Canada shares +1 with the US; the picked country must stick.
    expect(codeText(tester), '1');
    expect(find.textContaining('Canada'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '4165550123',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(auth.sentPhones, ['+14165550123']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('country_iso'), 'CA');
  });

  testWidgets('the saved country is remembered across launches',
      (tester) async {
    SharedPreferences.setMockInitialValues({'country_iso': 'GB'});
    await pumpLogin(tester, authService: _FakeAuthService());

    expect(codeText(tester), '44');
    expect(find.textContaining('United Kingdom'), findsOneWidget);
  });

  testWidgets('OTP screen: Resend unlocks after the countdown, then restarts',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpLogin(tester, authService: auth);
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '9999999999',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(); // send resolves
    await tester.pump(const Duration(milliseconds: 500)); // route in

    TextButton resend() =>
        tester.widget<TextButton>(find.byKey(const Key('resendButton')));
    expect(find.text('Enter the 6-digit code sent to +919999999999'),
        findsOneWidget);
    expect(find.text('Resend code in 0:30'), findsOneWidget);
    expect(resend().onPressed, isNull);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resend code'), findsOneWidget);
    expect(resend().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('resendButton')));
    await tester.pump();
    expect(auth.sentPhones, ['+919999999999']);
    expect(auth.resentPhones, ['+919999999999'],
        reason: 'Resend keeps the session, so wrong codes still count.');
    expect(find.text('Resend code in 0:30'), findsOneWidget);
  });

  test('country lookups', () {
    expect(countryForIso('in')!.flag, '\u{1F1EE}\u{1F1F3}');
    expect(countryForDialCode('44')!.iso, 'GB');
    expect(countryForDialCode('7')!.iso, 'RU');
    expect(countryForDialCode('1684')!.iso, 'AS');
    expect(countryForDialCode('999'), isNull);
  });
}

class _FakeAuthService extends AuthService {
  final List<String> sentPhones = [];
  final List<String> resentPhones = [];

  _FakeAuthService()
      : super(
          client: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          storage: _NoopStorage(),
        );

  @override
  Future<OtpSendResult> sendOtp(String phone) async {
    sentPhones.add(phone);
    return const OtpSendResult(
      sessionId: 'sess-1',
      retryAfter: Duration(seconds: 30),
      expiresIn: Duration(minutes: 5),
    );
  }

  @override
  Future<OtpSendResult> resendOtp(String phone) async {
    resentPhones.add(phone);
    return const OtpSendResult(
      sessionId: 'sess-1',
      retryAfter: Duration(seconds: 30),
      expiresIn: Duration(minutes: 4),
    );
  }
}

class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}
