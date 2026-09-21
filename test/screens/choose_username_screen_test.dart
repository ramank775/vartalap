/// The mandatory username step — AUTH_CONTRACT §2.4.
library vartalap.screens.choose_username_screen_test;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/login/choose_username.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  Future<void> pump(WidgetTester tester, _FakeAuthService auth,
      {VoidCallback? onDone}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: ChooseUsernameScreen(authService: auth, onDone: onDone),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The availability check is debounced; give it room to land.
  Future<void> settleCheck(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Finder continueButton() => find.widgetWithText(FilledButton, 'Continue');

  testWidgets('cannot be skipped: no back button, Continue starts disabled',
      (tester) async {
    await pump(tester, _FakeAuthService());

    expect(find.text('Choose your username'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Skip'), findsNothing);
    expect(
      tester.widget<FilledButton>(continueButton()).onPressed,
      isNull,
      reason: 'AUTH_CONTRACT §2.4: there is no skip, and nothing to '
          'continue to until a handle is actually free.',
    );
  });

  testWidgets('sync validator blocks Continue and never asks the server',
      (tester) async {
    final auth = _FakeAuthService();
    await pump(tester, auth);

    await tester.enterText(find.byType(TextField), 'ab');
    await settleCheck(tester);

    expect(find.text('At least 3 characters'), findsOneWidget);
    expect(tester.widget<FilledButton>(continueButton()).onPressed, isNull);
    expect(auth.checked, isEmpty);
  });

  testWidgets('a taken handle blocks Continue', (tester) async {
    final auth = _FakeAuthService(taken: {'kavya'});
    await pump(tester, auth);

    await tester.enterText(find.byType(TextField), 'kavya');
    await settleCheck(tester);

    expect(auth.checked, ['kavya']);
    expect(find.text('@kavya is taken. Try another.'), findsOneWidget);
    expect(tester.widget<FilledButton>(continueButton()).onPressed, isNull);
    expect(auth.setUsernameCalls, isEmpty);
  });

  testWidgets('an available handle enables Continue, which sets the username',
      (tester) async {
    final auth = _FakeAuthService();
    var done = 0;
    await pump(tester, auth, onDone: () => done++);

    await tester.enterText(find.byType(TextField), 'kavya_m');
    await settleCheck(tester);

    expect(find.text('@kavya_m is available'), findsOneWidget);
    expect(tester.widget<FilledButton>(continueButton()).onPressed, isNotNull);

    await tester.tap(continueButton());
    await tester.pumpAndSettle();

    expect(auth.setUsernameCalls, ['kavya_m']);
    expect(done, 1);
  });

  testWidgets('input is lower-cased before it reaches the server',
      (tester) async {
    final auth = _FakeAuthService();
    await pump(tester, auth);

    await tester.enterText(find.byType(TextField), 'Kavya');
    await settleCheck(tester);

    expect(
      auth.checked,
      ['kavya'],
      reason: 'AUTH_CONTRACT §2.4: wire values are lower-case only; the '
          'client lower-cases before sending.',
    );
  });

  testWidgets('a PATCH that loses the uniqueness race is surfaced',
      (tester) async {
    final auth = _FakeAuthService(patchThrows: true);
    await pump(tester, auth);

    await tester.enterText(find.byType(TextField), 'kavya_m');
    await settleCheck(tester);
    await tester.tap(continueButton());
    await tester.pumpAndSettle();

    expect(
      find.text('Could not claim that username. Try another.'),
      findsOneWidget,
      reason: 'AUTH_CONTRACT §4.5: a clean availability check can still '
          'lose the PATCH race with 409 USERNAME_TAKEN.',
    );
    expect(tester.widget<FilledButton>(continueButton()).onPressed, isNull);
  });
}

class _FakeAuthService extends AuthService {
  final Set<String> taken;
  final bool patchThrows;
  final List<String> checked = [];
  final List<String?> setUsernameCalls = [];
  String? _username;
  final _usernameStream = StreamController<String?>.broadcast();

  _FakeAuthService({this.taken = const {}, this.patchThrows = false})
      : super(
          client: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          storage: _NoopStorage(),
        );

  @override
  String? get username => _username;

  @override
  Stream<String?> get usernameChange => _usernameStream.stream;

  @override
  Future<UsernameAvailability> checkUsernameAvailability(
      String candidate) async {
    checked.add(candidate);
    return UsernameAvailability(available: !taken.contains(candidate));
  }

  @override
  Future<void> setUsername(String? value) async {
    if (patchThrows) {
      throw const AuthClientException(
          'patchOwnProfile', 409, 'USERNAME_TAKEN', 'taken');
    }
    setUsernameCalls.add(value);
    _username = value;
    _usernameStream.add(_username);
  }
}

class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}
