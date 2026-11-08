/// Avatar initials: whole characters only. Half an emoji is malformed
/// UTF-16, and laying it out threw on a Pixel 10 (build 86), taking down
/// the list the avatar was in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/widgets/avator.dart';

void main() {
  const cases = {
    'Ravi Kumar': 'RK',
    '😀 Ravi': 'R',
    'Ravi 🙏 Kumar': 'R',
    '🙏': '🙏',
    '👨‍👩‍👧 family': 'F',
    '_ravi kumar': 'RK',
    '+919876543210': '9',
    'अमित शर्मा': 'अश',
  };
  for (final MapEntry(key: name, value: initials) in cases.entries) {
    testWidgets('"$name" shows "$initials"', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(child: Avator(text: name, width: 48, height: 48)),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text(initials), findsOneWidget);
    });
  }
}
