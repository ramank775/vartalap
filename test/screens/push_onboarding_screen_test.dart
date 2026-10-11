/// The push chooser (DECISIONS 120): the options it offers for each
/// combination of Google and installed push apps, no pre-selection, and
/// the notification grant asked only after a pick.
library vartalap.screens.push_onboarding_screen_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/screens/login/push_onboarding.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap/theme/theme.dart';

import '../fake_unified_push.dart';

const _ntfy = 'io.heckel.ntfy';
const _nextPush = 'org.unifiedpush.distributor.nextpush';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late FakeUnifiedPush distributor;
  late PushService push;
  late int permissionRequests;
  late int done;

  Future<void> pump(
    WidgetTester tester, {
    bool google = false,
    List<String> apps = const [],
  }) async {
    // A 360x760dp phone.
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    distributor = FakeUnifiedPush(
      google: google,
      distributors: apps,
      labels: const {_ntfy: 'ntfy', _nextPush: 'NextPush'},
    );
    permissionRequests = 0;
    done = 0;
    final client = FakePushAuthClient()
      ..restoreSession(accesskey: 'sk_a', userId: 'a00000001');
    push = PushService(
      authClient: client,
      unifiedPush: distributor,
      storage: InMemorySecureStorage(),
      notifyWake: () async {},
      requestPermission: () async => permissionRequests++,
    );
    await tester.pumpWidget(MaterialApp(
      theme: lightThemeData,
      home: PushOnboardingScreen(push: push, onDone: () => done++),
    ));
    await tester.pumpAndSettle();
  }

  /// The options scroll on a small screen; bring one into view first.
  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  FilledButton button(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('opens with nothing selected and no permission dialog',
      (tester) async {
    await pump(tester, google: true, apps: const [_ntfy, _nextPush]);

    expect(find.text('Google Play services'), findsOneWidget);
    expect(find.text('ntfy'), findsOneWidget);
    expect(find.text('NextPush'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      isNull,
      reason: 'DECISIONS 120: no pre-selection',
    );
    expect(button(tester).onPressed, isNull);
    expect(permissionRequests, 0,
        reason: 'the dialog must not cover the explanation');
    expect(tester.takeException(), isNull, reason: 'fits 360x760');
  });

  testWidgets('no Google: only the push apps and Not now', (tester) async {
    await pump(tester, apps: const [_ntfy, _nextPush]);

    expect(find.text('Google Play services'), findsNothing);
    expect(find.text('ntfy'), findsOneWidget);
    expect(find.text('NextPush'), findsOneWidget);
    expect(find.text('A push app such as ntfy'), findsNothing);
  });

  testWidgets('no push app: offers one to get, and the button says so',
      (tester) async {
    await pump(tester, google: true);

    expect(find.text('Google Play services'), findsOneWidget);
    await tapText(tester, 'A push app such as ntfy');

    expect(find.text('Get ntfy'), findsOneWidget);
    expect(permissionRequests, 0);
  });

  testWidgets('back from the store with the app installed: it is picked',
      (tester) async {
    await pump(tester);
    await tapText(tester, 'A push app such as ntfy');

    distributor.distributors = const [_ntfy];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('ntfy'), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      _ntfy,
    );
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('picking Google asks for the grant only then, and registers',
      (tester) async {
    await pump(tester, google: true, apps: const [_ntfy]);

    await tapText(tester, 'Google Play services');
    expect(permissionRequests, 0, reason: 'selecting is not choosing');

    await tapText(tester, 'Continue');

    expect(done, 1);
    expect(permissionRequests, 1);
    expect(distributor.savedDistributor, kPushChoiceGoogle);
    expect(distributor.registerVapids, [vapidA]);
    expect((await SharedPreferences.getInstance()).getString(kPushChoiceKey),
        kPushChoiceGoogle);
  });

  testWidgets('Not now is saved and asks for nothing', (tester) async {
    await pump(tester, google: true, apps: const [_ntfy]);

    await tapText(tester, 'Not now');
    await tapText(tester, 'Continue');

    expect(done, 1);
    expect(permissionRequests, 0);
    expect(distributor.registerVapids, isEmpty);
    expect(push.state.value, PushState.off);
    expect((await SharedPreferences.getInstance()).getString(kPushChoiceKey),
        kPushChoiceNone);
  });
}
