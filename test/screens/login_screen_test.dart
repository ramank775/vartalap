/// LoginScreen widget tests — country-code field + E.164 validation
/// gating "Send OTP" (§4.7 plumbing: replaces the hard-coded +91 hack).
library vartalap.screens.login_screen_test;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/screens/login/login.dart';
import 'package:vartalap/services/auth_service.dart';
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

  testWidgets('country code field defaults to +91; Send OTP disabled empty',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpLogin(tester, authService: auth);

    final countryField =
        tester.widget<TextField>(find.byKey(const Key('countryCodeField')));
    expect(countryField.controller?.text, '+91');

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('valid phone + default country code enables Send OTP and sends',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpLogin(tester, authService: auth);

    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '9999999999',
    );
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(auth.sentPhones, ['+919999999999']);
  });

  testWidgets('invalid country code keeps Send OTP disabled', (tester) async {
    final auth = _FakeAuthService();
    await pumpLogin(tester, authService: auth);

    await tester.enterText(
      find.byKey(const Key('countryCodeField')),
      '91',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '9999999999',
    );
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('country code is remembered across launches', (tester) async {
    SharedPreferences.setMockInitialValues({'country_code': '+44'});
    final auth = _FakeAuthService();
    await pumpLogin(tester, authService: auth);

    final countryField =
        tester.widget<TextField>(find.byKey(const Key('countryCodeField')));
    expect(countryField.controller?.text, '+44');
  });
}

class _FakeAuthService extends AuthService {
  final List<String> sentPhones = [];

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
}

class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}
