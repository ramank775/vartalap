/// ProfileScreen widget tests — fully inline-editable UI, no popups.
library vartalap.screens.profile_screen_test;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/profile/profile.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  Future<void> pumpProfile(
    WidgetTester tester, {
    required AuthService authService,
    Brightness brightness = Brightness.dark,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark ? darkThemeData : lightThemeData,
        home: ProfileScreen(
          authService: authService,
          config: ConfigStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('logged-in user with name shows name + phone + rows',
      (tester) async {
    final auth = _FakeAuthService(
      phone: '+919876543210',
      name: 'Raman Jay',
    );
    await pumpProfile(tester, authService: auth);

    expect(find.text('Profile'), findsOneWidget); // app bar
    expect(find.text('Raman Jay'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget); // formatted

    // Row labels (read mode) — top of the list.
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);

    // Phone / QR / Sign out live further down — confirm by scrolling
    // them into view rather than asserting they are already visible
    // (the test surface clips below the fold).
    final listView = find.byType(ListView);
    expect(listView, findsOneWidget);
    await tester.drag(listView, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('QR code'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    // No more popup-driven buttons.
    expect(find.text('Edit profile'), findsNothing);
    expect(find.text('Share QR'), findsNothing);

    // Old-screen leftovers.
    expect(find.textContaining('User ID:'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Storage and data'), findsNothing);
  });

  testWidgets('no display name shows placeholder + person glyph fallback',
      (tester) async {
    final auth = _FakeAuthService(phone: '+919876543210', name: null);
    await pumpProfile(tester, authService: auth);

    // The Name row's placeholder.
    expect(find.text('Add your name'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('null phone renders "Unknown" but does not crash',
      (tester) async {
    final auth = _FakeAuthService(phone: null, name: null);
    await pumpProfile(tester, authService: auth);

    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Add your name'), findsOneWidget);
  });

  testWidgets('phone formatter: +91 12-digit groups as +91 NNNNN NNNNN',
      (tester) async {
    final auth = _FakeAuthService(phone: '+919876543210', name: 'X');
    await pumpProfile(tester, authService: auth);
    expect(find.text('+91 98765 43210'), findsOneWidget);
  });

  testWidgets('phone formatter: non-+91 falls through to right-grouped',
      (tester) async {
    final auth = _FakeAuthService(phone: '+14155552671', name: 'X');
    await pumpProfile(tester, authService: auth);
    expect(find.text('+1 4 155 552 671'), findsOneWidget);
  });

  testWidgets('tapping Name row enters edit mode with TextField + actions',
      (tester) async {
    final auth = _FakeAuthService(phone: '+919876543210', name: 'Raman');
    await pumpProfile(tester, authService: auth);

    // Read mode: row visible; no TextField yet.
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Raman'));
    await tester.pumpAndSettle();

    // Edit mode: TextField appears with current value, plus check + close.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('committing name edit calls setDisplayName and exits edit',
      (tester) async {
    final auth = _FakeAuthService(phone: '+919876543210', name: 'Raman');
    await pumpProfile(tester, authService: auth);

    await tester.tap(find.text('Raman'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Raman Jay');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(auth.setDisplayNameCalls, ['Raman Jay']);
    // Back to read mode with new value.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Raman Jay'), findsOneWidget);
  });

  testWidgets('cancel button reverts edit without calling setter',
      (tester) async {
    final auth = _FakeAuthService(phone: '+919876543210', name: 'Raman');
    await pumpProfile(tester, authService: auth);

    await tester.tap(find.text('Raman'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Throwaway');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(auth.setDisplayNameCalls, isEmpty);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Raman'), findsOneWidget);
  });

  testWidgets('username row edit calls setUsername', (tester) async {
    final auth = _FakeAuthService(phone: '+919876543210', name: 'Raman');
    await pumpProfile(tester, authService: auth);

    // The placeholder text in the Username row.
    await tester.tap(find.text('Add a username'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'raman');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(auth.setUsernameCalls, ['raman']);
    // Read-mode shows the value with the @ prefix.
    expect(find.text('@raman'), findsOneWidget);
  });

  testWidgets('status row edit calls setStatusText', (tester) async {
    final auth = _FakeAuthService(phone: '+919876543210', name: 'Raman');
    await pumpProfile(tester, authService: auth);

    await tester.tap(find.text('Hey there, I am using Vartalap'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Available');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(auth.setStatusTextCalls, ['Available']);
    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('QR row tap toggles inline expansion', (tester) async {
    final auth = _FakeAuthService(phone: '+919876543210', name: 'Raman');
    await pumpProfile(tester, authService: auth);

    expect(find.text('QR sharing coming soon'), findsNothing);
    expect(find.text('Scan to add me'), findsOneWidget);

    final qrRow = find.widgetWithText(ListTile, 'QR code');
    await tester.tap(qrRow);
    await tester.pumpAndSettle();

    expect(find.text('QR sharing coming soon'), findsOneWidget);
    expect(find.text('Tap to hide'), findsOneWidget);

    // Tap again to collapse.
    await tester.tap(qrRow);
    await tester.pumpAndSettle();
    expect(find.text('QR sharing coming soon'), findsNothing);
    expect(find.text('Scan to add me'), findsOneWidget);
  });

  testWidgets(
      'Sign out is two-tap inline: first arms, second confirms and logs out',
      (tester) async {
    final auth = _FakeAuthService(phone: '+919876543210', name: 'Raman');
    await pumpProfile(tester, authService: auth);

    // Scroll the row into the viewport — the test surface is tall but
    // CI defaults can clip the bottom. The button is the only TextButton
    // on the screen so byType is the most robust selector.
    final signOut = find.byType(TextButton);
    await tester.scrollUntilVisible(signOut, 200);
    await tester.pumpAndSettle();

    // First tap arms — no logout yet.
    await tester.tap(signOut);
    await tester.pump();
    expect(auth.logoutCalls, 0);
    expect(find.text('Tap again to confirm'), findsOneWidget);

    // Second tap fires logout.
    await tester.tap(find.widgetWithText(TextButton, 'Tap again to confirm'));
    await tester.pump();
    expect(auth.logoutCalls, 1);
  });

  testWidgets('Sign out arm auto-resets after timeout', (tester) async {
    final auth = _FakeAuthService(phone: '+919876543210', name: 'Raman');
    await pumpProfile(tester, authService: auth);

    // Scroll the row into the viewport — the test surface is tall but
    // CI defaults can clip the bottom. The button is the only TextButton
    // on the screen so byType is the most robust selector.
    final signOut = find.byType(TextButton);
    await tester.scrollUntilVisible(signOut, 200);
    await tester.pumpAndSettle();

    await tester.tap(signOut);
    await tester.pump();
    expect(find.text('Tap again to confirm'), findsOneWidget);

    // Auto-reset is 4s in production; pump past it.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Tap again to confirm'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
    expect(auth.logoutCalls, 0);
  });
}

/// Real AuthService with a no-op transport + storage, plus injected
/// values for the getters the screen reads. Captures calls to the
/// inline-editable setters so tests can assert they fired.
class _FakeAuthService extends AuthService {
  final String? _phone;
  String? _name;
  String? _username;
  String? _statusText;
  int logoutCalls = 0;
  final List<String?> setDisplayNameCalls = [];
  final List<String?> setUsernameCalls = [];
  final List<String?> setStatusTextCalls = [];

  final _nameStream = StreamController<String?>.broadcast();
  final _usernameStream = StreamController<String?>.broadcast();
  final _statusStream = StreamController<String?>.broadcast();

  _FakeAuthService({required String? phone, required String? name})
      : _phone = phone,
        _name = name,
        super(
          client: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          storage: _NoopStorage(),
        );

  @override
  String? get phoneNumber => _phone;

  @override
  String? get displayName => _name;

  @override
  Stream<String?> get displayNameChange => _nameStream.stream;

  @override
  Future<void> setDisplayName(String? name) async {
    setDisplayNameCalls.add(name);
    _name = name?.trim();
    _nameStream.add(_name);
  }

  @override
  String? get username => _username;

  @override
  Stream<String?> get usernameChange => _usernameStream.stream;

  @override
  Future<void> setUsername(String? value) async {
    setUsernameCalls.add(value);
    _username = value?.trim();
    _usernameStream.add(_username);
  }

  @override
  String? get statusText => _statusText;

  @override
  Stream<String?> get statusTextChange => _statusStream.stream;

  @override
  Future<void> setStatusText(String? value) async {
    setStatusTextCalls.add(value);
    _statusText = value?.trim();
    _statusStream.add(_statusText);
  }

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }
}

class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}
