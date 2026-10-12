/// SettingsScreen widget tests — WhatsApp layout (decision 154): the
/// profile header and area rows, then each page's prefs and dialogs.
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

  /// [page] opens that area's row (Account, Privacy, Chats, Help).
  Future<void> pumpSettings(
    WidgetTester tester, {
    required AuthService authService,
    String? page,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          authService: authService,
          config: ConfigStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (page != null) {
      await tester.tap(find.text(page));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('opens with your profile, then one row per area',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpSettings(tester, authService: auth);

    // No display name yet: the header falls back to the handle.
    expect(find.text('@alice_k'), findsOneWidget);
    expect(find.text('Hey there, I am using Vartalap'), findsOneWidget);
    for (final row in ['Account', 'Privacy', 'Chats', 'Help']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text('Appearance'), findsNothing);

    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Open source licenses'), findsOneWidget);
  });

  testWidgets('Sentry toggle defaults off; flipping persists true',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpSettings(tester, authService: auth, page: 'Privacy');

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
      'Send test event tile and DSN override field appear only once opted in',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpSettings(tester, authService: auth, page: 'Privacy');

    expect(find.text('Send test event'), findsNothing);
    expect(find.text('DSN override (advanced)'), findsNothing);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(find.text('Send test event'), findsOneWidget);
    expect(find.text('DSN override (advanced)'), findsOneWidget);

    // Flipping back off hides them again.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(find.text('Send test event'), findsNothing);
    expect(find.text('DSN override (advanced)'), findsNothing);
  });

  testWidgets('DSN override persists to prefs on submit', (tester) async {
    final auth = _FakeAuthService();
    await pumpSettings(tester, authService: auth, page: 'Privacy');

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'DSN override (advanced)'),
      'https://example.invalid/1',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kSentryDsnOverridePrefKey),
        'https://example.invalid/1');
  });

  testWidgets(
      'Theme tile shows current selection; selecting Dark persists + applies',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpSettings(tester, authService: auth, page: 'Chats');

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
    await pumpSettings(tester, authService: auth, page: 'Account');

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

  testWidgets('Delete account needs "DELETE <username>" typed (AUTH_CONTRACT §8.2)',
      (tester) async {
    final auth = _FakeAuthService();
    await pumpSettings(tester, authService: auth, page: 'Account');

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    final delete = find.widgetWithText(TextButton, 'Delete');
    expect(tester.widget<TextButton>(delete).onPressed, isNull,
        reason: 'never a one-tap button');
    await tester.enterText(find.byType(TextField), 'delete alice_k');
    await tester.pump();
    expect(tester.widget<TextButton>(delete).onPressed, isNull,
        reason: 'case-sensitive, like the server');

    await tester.enterText(find.byType(TextField), 'DELETE alice_k');
    await tester.pump();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(auth.deleted, ['DELETE alice_k']);
  });
}

/// Minimal AuthService stand-in: extends the real AuthService with a
/// no-op AuthClient backing it, then overrides logout() to record
/// invocations without touching secure storage or the network.
class _FakeAuthService extends AuthService {
  int logoutCalls = 0;
  final deleted = <String>[];

  @override
  String? get username => 'alice_k';

  @override
  Future<void> deleteAccount(String confirmation) async =>
      deleted.add(confirmation);

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
