import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/chat/attachment_preview.dart';

/// Pushes the preview from a launcher button and records what it pops.
Future<List<AttachmentChoice?>> _open(WidgetTester tester, String path,
    {bool offerHd = false}) async {
  final popped = <AttachmentChoice?>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => popped.add(
          await Navigator.of(context).push<AttachmentChoice>(MaterialPageRoute(
            builder: (_) =>
                AttachmentPreviewScreen(path: path, offerHd: offerHd),
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

    expect(find.byTooltip('Standard quality'), findsNothing,
        reason: 'a document goes byte for byte: no HD to choose');
    await tester.enterText(find.byType(TextField), '  Q3 numbers  ');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    expect(popped, [(caption: 'Q3 numbers', hd: false)]);
  });

  testWidgets('send with no caption pops an empty one', (tester) async {
    final popped = await _open(tester, pdf);
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    expect(popped, [(caption: '', hd: false)]);
  });

  testWidgets('a photo offers HD, which the choice carries', (tester) async {
    final photo = '${dir.path}/shot.jpg';
    File(photo).writeAsBytesSync(List.filled(16, 0));
    final popped = await _open(tester, photo, offerHd: true);
    await tester.tap(find.byTooltip('Standard quality'));
    await tester.pump();
    expect(find.byTooltip('HD quality'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    expect(popped, [(caption: '', hd: true)]);
  });

  testWidgets('cancel pops null so nothing is sent', (tester) async {
    final popped = await _open(tester, pdf);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(popped, [null]);
  });
}
