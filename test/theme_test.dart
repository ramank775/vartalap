/// The theme's density (WhatsApp-like rows, chips, fields and bottom
/// bar), measured on rendered widgets, light and dark; and the font sizes
/// it must not touch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/theme/theme.dart';

void main() {
  for (final (name, theme) in [
    ('light', lightThemeData),
    ('dark', darkThemeData),
  ]) {
    testWidgets('$name: rows, chips, fields and the bottom bar are compact',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: ListView(
            children: [
              const ListTile(
                key: Key('two'),
                leading: CircleAvatar(),
                title: Text('Asha'),
                subtitle: Text('Hello'),
              ),
              const ListTile(key: Key('one'), title: Text('Labels')),
              const ListTile(
                key: Key('big'),
                leading: SizedBox.square(key: Key('cover'), dimension: 56),
                title: Text('Diwali'),
                subtitle: Text('12 photos'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  key: const Key('chip'),
                  label: const Text('Family'),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const TextField(key: Key('field')),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.chat), label: 'Chats'),
              NavigationDestination(
                  icon: Icon(Icons.dynamic_feed), label: 'Timeline'),
            ],
          ),
        ),
      ));

      double height(String key) => tester.getSize(find.byKey(Key(key))).height;
      expect(height('two'), 72);
      expect(height('one'), 56);
      expect(
          tester.getSize(find.byKey(const Key('cover'))), const Size.square(56),
          reason: 'a 56dp leading is not squashed');
      expect(height('chip'), 34);
      expect(height('field'), 44);
      expect(tester.getSize(find.byType(NavigationBar)).height, 68);

      double fontSize(String text) => tester
          .widget<RichText>(find.descendant(
              of: find.text(text), matching: find.byType(RichText)))
          .text
          .style!
          .fontSize!;
      expect(fontSize('Asha'), 16, reason: 'font sizes stay');
      expect(fontSize('Hello'), 14);
    });
  }

  test('dialogs are a little wider, their buttons closer in', () {
    for (final theme in [lightThemeData, darkThemeData]) {
      expect(theme.dialogTheme.insetPadding,
          const EdgeInsets.symmetric(horizontal: kSpaceLg, vertical: kSpaceLg));
      expect(theme.dialogTheme.actionsPadding,
          const EdgeInsets.fromLTRB(kSpaceLg, 0, kSpaceMd, kSpaceMd));
    }
  });
}
