import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/update/app_update.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  testWidgets('the gate swaps the app for the update screen on 426',
      (tester) async {
    final appBuild = AppBuild(80);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          AppUpdateGate(appBuild: appBuild, child: child!),
      home: const Text('chats'),
    ));
    expect(find.text('chats'), findsOneWidget);

    appBuild.observe(200, '81');
    await tester.pumpAndSettle();
    expect(find.text('chats'), findsOneWidget,
        reason: 'a newer build is not a block');

    appBuild.observe(426, null);
    await tester.pumpAndSettle();
    expect(find.text('chats'), findsNothing);
    expect(find.text('Update Vartalap'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
  });

  testWidgets('the banner shows while a newer build is out until dismissed',
      (tester) async {
    final appBuild = AppBuild(80);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppUpdateBanner(appBuild: appBuild)),
    ));
    expect(find.text('New version available'), findsNothing);

    appBuild.observe(200, '81');
    await tester.pumpAndSettle();
    expect(find.text('New version available'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('New version available'), findsNothing);
  });
}
