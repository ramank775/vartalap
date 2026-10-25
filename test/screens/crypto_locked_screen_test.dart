import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/startup/crypto_locked.dart';

void main() {
  testWidgets('Try again retries; Reset asks first, then resets',
      (tester) async {
    var retries = 0;
    var resets = 0;
    await tester.pumpWidget(MaterialApp(
      home: CryptoLockedScreen(
        onRetry: () async => retries++,
        onReset: () async => resets++,
      ),
    ));

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(retries, 1);

    await tester.tap(find.text('Reset encryption'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(resets, 0);

    await tester.tap(find.text('Reset encryption'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(resets, 1);
  });
}
