/// Labels as the one place to manage them (WhatsApp's Lists): an empty
/// state, a new label opening on its people, its people first with a
/// search, Rename and Delete from inside it, and room for Android's bar.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/labels/labels.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';

const _asha = '00000000a';
const _ravi = '00000000b';
const _meena = '00000000c';

Future<void> _pump(WidgetTester tester, Widget home,
    {double bottomInset = 0}) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(bottom: bottomInset)),
      child: home,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no labels: say how to make one; a new one opens on its people',
      (tester) async {
    final svc = _FakeChat([]);
    await _pump(tester, LabelsScreen(chatService: svc), bottomInset: 40);
    expect(find.textContaining('No labels yet'), findsOneWidget);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect((list.padding! as EdgeInsets).bottom, 88 + 40,
        reason: 'the FAB, then the system bar');

    await tester.tap(find.text('New label'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Neighbours');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(LabelMembersScreen), findsOneWidget);
    expect(find.text('Neighbours'), findsOneWidget);
    expect(find.text('0 people'), findsOneWidget);
  });

  testWidgets("a label's people come first; search; rename and delete inside",
      (tester) async {
    final svc = _FakeChat(
        [const Label(labelId: 1, name: 'Family', userIds: {_meena})]);
    await _pump(tester, LabelsScreen(chatService: svc));
    expect(find.text('1 person'), findsOneWidget);
    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();

    final names = [
      for (final t in tester.widgetList<CheckboxListTile>(
          find.byType(CheckboxListTile)))
        (t.title! as Text).data,
    ];
    expect(names, ['Meena', 'Asha', 'Ravi'], reason: 'members first');

    await tester.tap(find.text('Asha'));
    await tester.pumpAndSettle();
    expect(svc.calls.last, 'members(1, {$_meena, $_asha})');
    expect(find.text('2 people'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget, reason: 'the row stays put');

    await tester.enterText(find.byType(TextField), 'rav');
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Family'), 'Parivar');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Parivar'), findsOneWidget, reason: 'the title');

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(LabelMembersScreen), findsNothing, reason: 'gone back');
    expect(svc.calls.sublist(1), ['rename(1, Parivar)', 'delete(1)']);
    expect(find.text('Parivar'), findsNothing);
  });
}

class _FakeChat implements ChatService {
  _FakeChat(this.labels);

  final calls = <String>[];
  List<Label> labels;
  final _changes = StreamController<List<Label>>.broadcast();

  void _set(List<Label> next) => _changes.add(labels = next);

  @override
  Stream<List<Label>> watchLabels() async* {
    yield labels;
    yield* _changes.stream;
  }

  @override
  Future<int> createLabel(String name) async {
    _set([...labels, Label(labelId: 9, name: name)]);
    return 9;
  }

  @override
  Future<void> renameLabel(int labelId, String name) async {
    calls.add('rename($labelId, $name)');
    _set([
      for (final l in labels)
        l.labelId == labelId
            ? Label(labelId: labelId, name: name, userIds: l.userIds)
            : l
    ]);
  }

  @override
  Future<void> deleteLabel(int labelId) async {
    calls.add('delete($labelId)');
    _set([
      for (final l in labels)
        if (l.labelId != labelId) l
    ]);
  }

  @override
  Future<void> setLabelMembers(int labelId, Set<String> userIds) async =>
      calls.add('members($labelId, $userIds)');

  @override
  Future<List<ContactRow>> discoverContacts({
    List<String> normalizedPhones = const [],
    Map<String, String> contactBookNamesByPhone = const {},
  }) async =>
      [
        for (final (id, name) in [
          (_asha, 'Asha'),
          (_ravi, 'Ravi'),
          (_meena, 'Meena'),
        ])
          ContactRow(userId: id, contactBookName: name, lastRefreshedMs: 0),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
