import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
