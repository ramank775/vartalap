/// The group pickers (New group, Add members): connections only, and a
/// search field narrowing them by name or @username.
library vartalap.screens.member_picker_screen_test;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/group_create/group_create.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_store/vartalap_store.dart';

const _asha = ContactRow(
    userId: 'u-asha',
    username: 'asha_k',
    contactBookName: 'Asha',
    lastRefreshedMs: 1);
const _ravi = ContactRow(
    userId: 'u-ravi',
    username: 'ravi99',
    contactBookName: 'Ravi Kumar',
    lastRefreshedMs: 1);
const _meena =
    ContactRow(userId: 'u-meena', username: 'meena', lastRefreshedMs: 1);
const _stranger = ContactRow(
    userId: 'u-x',
    username: 'xavier',
    contactBookName: 'Xavier',
    lastRefreshedMs: 1);

void main() {
  test('contactMatches: name or @username, any case', () {
    expect(contactMatches(_ravi, 'kum'), isTrue);
    expect(contactMatches(_ravi, 'RAVI9'), isTrue);
    expect(contactMatches(_ravi, '@ravi9'), isTrue);
    expect(contactMatches(_asha, '@ravi'), isFalse);
    expect(contactMatches(_meena, '@mee'), isTrue);
    expect(contactMatches(_asha, '  '), isTrue);
  });

  testWidgets('typing narrows the list; picking clears the search',
      (tester) async {
    List<ContactRow>? done;
    await tester.pumpWidget(MaterialApp(
      theme: lightThemeData,
      home: MemberPickerScreen(
        chatService: _FakeChatService(),
        title: 'New group',
        doneIcon: Icons.arrow_forward,
        onDone: (_, picked) => done = picked,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Xavier'), findsNothing, reason: 'not a connection');

    await tester.enterText(find.byType(TextField), '@ravi');
    await tester.pumpAndSettle();
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('Asha'), findsNothing);

    await tester.tap(find.text('Ravi Kumar'));
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget, reason: 'search cleared');
    expect(find.text('1 selected'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No one found for "zzz"'), findsOneWidget);
    // the picked stay picked whatever the search shows
    await tester.tap(find.byTooltip('Next'));
    expect(done?.map((c) => c.userId), ['u-ravi']);
  });
}

class _FakeChatService implements ChatService {
  @override
  Future<List<ContactRow>> discoverContacts({
    List<String> normalizedPhones = const [],
    Map<String, String> contactBookNamesByPhone = const {},
  }) async =>
      const [_asha, _ravi, _meena, _stranger];

  @override
  Future<Set<String>> connectedUsers() async => {'u-asha', 'u-ravi', 'u-meena'};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
