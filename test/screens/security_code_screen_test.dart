import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vartalap/screens/chat_info/security_code.dart';

void main() {
  test('twelve groups of five, four to a row', () {
    final digits = List.generate(60, (i) => '${i % 10}').join();
    expect(SecurityCodeScreen.rows(digits), [
      '01234  56789  01234  56789',
      '01234  56789  01234  56789',
      '01234  56789  01234  56789',
    ]);
  });

  testWidgets('before any message it says what to do', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: SecurityCodeScreen(name: 'Bea', number: Future.value(null))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Send or receive a message with Bea first'),
        findsOneWidget);
  });

  final mine = List.generate(60, (i) => '${i % 10}').join();

  test('the QR carries a version and the digits, and nothing else reads',
      () {
    expect(securityCodeQr(mine), 'vartalap-sc:1:$mine');
    expect(securityCodeFromQr(securityCodeQr(mine)), mine);
    expect(securityCodeFromQr('vartalap-sc:2:$mine'), isNull,
        reason: 'a version this app does not know');
    expect(securityCodeFromQr('vartalap-sc:1:1234'), isNull);
    expect(securityCodeFromQr('vartalap://u/bea'), isNull);
  });

  Future<void> pumpScan(WidgetTester tester, String? scanned) async {
    await tester.pumpWidget(MaterialApp(
      home: SecurityCodeScreen(
        name: 'Bea',
        number: Future.value(mine),
        scan: (_) async => scanned,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the code as a QR, and its scan of the same code '
      'verifies', (tester) async {
    await pumpScan(tester, securityCodeQr(mine));
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Security code verified'), findsNothing);

    await tester.ensureVisible(find.text('Scan code'));
    await tester.tap(find.text('Scan code'));
    await tester.pumpAndSettle();
    expect(find.text('Security code verified'), findsOneWidget);
  });

  testWidgets('a different code says they do not match', (tester) async {
    final other = '9${mine.substring(1)}';
    await pumpScan(tester, securityCodeQr(other));
    await tester.ensureVisible(find.text('Scan code'));
    await tester.tap(find.text('Scan code'));
    await tester.pumpAndSettle();
    expect(find.text("Security codes don't match"), findsOneWidget);
    expect(find.text('Security code verified'), findsNothing);
  });

  testWidgets('another QR is not taken for a code', (tester) async {
    await pumpScan(tester, 'vartalap://u/bea');
    await tester.ensureVisible(find.text('Scan code'));
    await tester.tap(find.text('Scan code'));
    await tester.pumpAndSettle();
    expect(find.text('Not a security code'), findsOneWidget);
  });

  testWidgets('backing out of the camera changes nothing', (tester) async {
    await pumpScan(tester, null);
    await tester.ensureVisible(find.text('Scan code'));
    await tester.tap(find.text('Scan code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Security code'), findsNothing);
  });
}
