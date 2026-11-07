import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/services/crash_reports.dart';

void main() {
  late Directory dir;
  late CrashReports reports;

  /// What each hand-off was asked, and whether it "took" it.
  late List<(String, Map<String, String>)> handOffs;
  late Map<String, bool> takes;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('crash_reports_test');
    handOffs = [];
    takes = {'email': true, 'share': true};
    reports = CrashReports(dir, build: '3.0.0+90')
      ..handOff = ((method, mail) async {
        handOffs.add((method, mail));
        return takes[method]!;
      })
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

  /// Answers the dialog with [button]; what it said.
  Future<String> answer(WidgetTester tester, String button) async {
    final done = reports.offer(await home(tester));
    await tester.pumpAndSettle();
    final said = tester
        .widget<Text>(find
            .descendant(
                of: find.byType(AlertDialog), matching: find.byType(Text))
            .first)
        .data!;
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    await done;
    return said;
  }

  testWidgets('a crash: asked once; Send opens an email app filled in',
      (tester) async {
    File('${dir.path}/1700000000000.dart.txt')
        .writeAsStringSync('2.9.0+79\nRangeError\n#0 f');
    android(1700000000001);
    final done = reports.offer(await home(tester));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Vartalap closed unexpectedly. Send a report to '
            'help fix it? It opens your email app, where you can read the '
            'report before you send it.'),
        findsOneWidget);
    expect(
        find.textContaining('It has no messages, phone numbers or contacts.'),
        findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await done;

    final [(method, mail)] = handOffs;
    expect(method, 'email');
    expect(mail['to'], 'vartalap@one9x.org');
    expect(mail['subject'], 'Vartalap crash report (build 80)',
        reason: 'the newest report\'s build');
    expect(
        mail['body'],
        'Android 7.0 (API 24), Xiaomi Redmi 4\n'
        '\n2023-11-14T22:13:20.001Z, build 2.9.0+80, Android crash:\n'
        'java.lang.IllegalStateException\n'
        '\tat com.one9x.vartalap.PushInbox.wake(PushInbox.kt:40)\n\n'
        '\n2023-11-14T22:13:20.000Z, build 2.9.0+79, Dart error:\n'
        'RangeError\n#0 f\n');
    expect(reports.waiting(), isEmpty, reason: 'handed off counts as sent');
  });

  testWidgets('no email app: the share sheet; neither: kept for next time',
      (tester) async {
    reports.record(StateError('x'), StackTrace.fromString('#0 f'));
    takes = {'email': false, 'share': false};
    await answer(tester, 'Send');
    expect(handOffs.map((h) => h.$1), ['email', 'share']);
    expect(reports.waiting(), hasLength(1));

    takes = {'email': false, 'share': true};
    await answer(tester, 'Send');
    expect(handOffs.last.$1, 'share');
    expect(reports.waiting(), isEmpty);
  });

  testWidgets("Don't send drops them unsent; a long one is cut",
      (tester) async {
    reports.record(StateError('x'), StackTrace.current);
    expect(await answer(tester, "Don't send"),
        startsWith('Vartalap ran into a problem. Send a report'),
        reason: 'a Dart error alone: the app did not close');
    expect(handOffs, isEmpty);
    expect(reports.waiting(), isEmpty);

    File('${dir.path}/1700000000000.dart.txt')
        .writeAsStringSync('3.0.0+90\nStackOverflowError\n${'#0 f\n' * 5000}');
    expect(reports.mail(reports.waiting(), const {})['body'],
        hasLength(CrashReports.maxBody));
  });
}
