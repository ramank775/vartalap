/// SettingsScreen widget tests — section rendering, theme/sentry pref
/// persistence, and logout dialog wiring.
library vartalap.screens.settings_screen_test;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/settings/settings.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VartalapTheme.themeMode = ThemeMode.system;
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    required AuthService authService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          authService: authService,
          config: ConfigStore(),
        ),
      ),
    );
    // Let the async _load() finish.
    await tester.pumpAndSettle();
  }

  testWidgets('renders all four section headers and tiles', (tester) async {
    final auth = _FakeAuthService();
    await pumpSettings(tester, authService: auth);

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Crash reporting (Sentry)'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Open source licenses'), findsOneWidget);
  });

  testWidgets('Sentry toggle defaults off; flipping persists true',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpSettings(tester, authService: auth);

    final switchFinder = find.byType(SwitchListTile);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kSentryOptInPrefKey), isNull);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    final prefs2 = await SharedPreferences.getInstance();
    expect(prefs2.getBool(kSentryOptInPrefKey), isTrue);
  });

  testWidgets(
      'Theme tile shows current selection; selecting Dark persists + applies',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpSettings(tester, authService: auth);

    expect(find.text('System default'), findsOneWidget);

    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();

    // Dialog with three radio options.
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    // The option label "System default" appears in the dialog and the
    // subtitle behind — at least one is visible.
    expect(find.text('System default'), findsWidgets);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kThemeModePrefKey), 'dark');
    expect(VartalapTheme.themeMode, ThemeMode.dark);
    // Subtitle on the tile updates.
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('Logout tile shows confirmation; confirming calls logout',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpSettings(tester, authService: auth);

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    // Dialog visible.
    expect(find.text('Log out?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Confirm.
    final confirmBtn = find.widgetWithText(TextButton, 'Log out');
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(auth.logoutCalls, 1);
  });
}

/// Minimal AuthService stand-in: extends the real AuthService with a
/// no-op AuthClient backing it, then overrides logout() to record
/// invocations without touching secure storage or the network.
class _FakeAuthService extends AuthService {
  int logoutCalls = 0;

  _FakeAuthService()
      : super(
          client: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          storage: _NoopStorage(),
        );

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }
}

class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}
