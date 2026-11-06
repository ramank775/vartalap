import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/screens/settings/privacy.dart';
import 'package:vartalap/services/crash_reports.dart';

void main() {
  late Directory dir;
  late CrashReports reports;
  late List<Map<String, Object>> sent;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('crash_reports_test');
    sent = [];
    reports = CrashReports(dir, build: '3.0.0+90')
      ..send = ((report) async => sent.add(report))
      ..device =
          (() async => {'android': '7.0 (API 24)', 'model': 'Xiaomi Redmi 4'});
  });

  tearDown(() => dir.deleteSync(recursive: true));

  String text(File f) => f.readAsStringSync();

  test('an error is kept with its type and frames, never its message', () {
    try {
      throw StateError('hi Ravi, my number is +919812345678');
    } catch (e, stack) {
      reports.record(e, stack);
      reports.record(e, stack);
    }
    final [file] = reports.waiting();
    expect(file.path, endsWith('.dart.txt'));
    expect(text(file), startsWith('3.0.0+90\nStateError\n#0'));
    expect(text(file), isNot(contains('Ravi')));
    expect(text(file), isNot(contains('9812345678')));

    for (var i = 0; i < 20; i++) {
      reports.record(RangeError(i), StackTrace.fromString('#0 f$i'));
    }
    expect(reports.waiting(), hasLength(CrashReports.maxWaiting),
        reason: 'a crash loop does not fill the phone');
  });

  Future<BuildContext> home(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
      context = ctx;
      return const SizedBox();
    })));
    return context;
  }

  void android(int ms) => File('${dir.path}/$ms.android.txt')
      .writeAsStringSync('2.9.0+80\njava.lang.IllegalStateException\n'
          '\tat com.one9x.vartalap.PushInbox.wake(PushInbox.kt:40)\n');

  testWidgets('a crash: asked once, sent on Send, gone from the phone',
      (tester) async {
    android(1700000000000);
    final done = reports.offer(await home(tester));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Vartalap closed unexpectedly. Send a report to '
            'help fix it?'),
        findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await done;
    expect(sent, [
      {
        'at': 1700000000000,
        'kind': 'android',
        'build': '2.9.0+80',
        'android': '7.0 (API 24)',
        'model': 'Xiaomi Redmi 4',
        'trace': 'java.lang.IllegalStateException\n'
            '\tat com.one9x.vartalap.PushInbox.wake(PushInbox.kt:40)\n',
      }
    ]);
    expect(reports.waiting(), isEmpty);
  });

  testWidgets("Don't send drops them unsent", (tester) async {
    reports.record(StateError('x'), StackTrace.current);
    final done = reports.offer(await home(tester));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vartalap ran into a problem.'), findsOneWidget);
    await tester.tap(find.text("Don't send"));
    await tester.pumpAndSettle();
    await done;
    expect(sent, isEmpty);
    expect(reports.waiting(), isEmpty);
  });

  testWidgets('sent without asking when the user said so; kept while offline',
      (tester) async {
    SharedPreferences.setMockInitialValues({kCrashReportsAutoKey: true});
    android(1700000000001);
    reports.send = (_) async => throw const SocketException('offline');
    await reports.offer(await home(tester));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(reports.waiting(), hasLength(1), reason: 'tried again next start');

    reports.send = (report) async => sent.add(report);
    await reports.offer(await home(tester));
    expect(sent.single['kind'], 'android');
    expect(reports.waiting(), isEmpty);
  });

  testWidgets('Settings › Privacy turns automatic reports on', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CrashReportsSwitch())));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
        reason: 'off until the user turns it on');
    await tester.tap(find.text('Send crash reports automatically'));
    await tester.pumpAndSettle();
    expect(
        (await SharedPreferences.getInstance()).getBool(kCrashReportsAutoKey),
        isTrue);
  });
}
