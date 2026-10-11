import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/chat/attachment_preview.dart';

/// Pushes the preview from a launcher button and records what it pops.
Future<List<String?>> _open(WidgetTester tester, String path) async {
  final popped = <String?>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => popped.add(
          await Navigator.of(context).push<String>(MaterialPageRoute(
            builder: (_) => AttachmentPreviewScreen(path: path),
          )),
        ),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return popped;
}

void main() {
  late Directory dir;
  late String pdf;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('preview_test');
    pdf = '${dir.path}/report.pdf';
    File(pdf).writeAsBytesSync(List.filled(2048, 0));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('a document shows its name and size; send pops the caption',
      (tester) async {
    final popped = await _open(tester, pdf);

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  Q3 numbers  ');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    expect(popped, ['Q3 numbers']);
  });

  testWidgets('send with no caption pops an empty one', (tester) async {
    final popped = await _open(tester, pdf);
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    expect(popped, ['']);
  });

  testWidgets('cancel pops null so nothing is sent', (tester) async {
    final popped = await _open(tester, pdf);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(popped, [null]);
  });
}
