/// New chat › Contacts: the people on Vartalap, then WhatsApp's "Invite
/// to Vartalap" (the address book's others), each opening the phone's own
/// SMS app; one search over both.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const _asha = '+919800000001';
const _ashaLandline = '+912000000001';
const _bina = '+919800000002';
const _unnamed = '+919800000003';

String _hash(String phone) => sha256.convert(utf8.encode(phone)).toString();

void main() {
  /// The `launch` calls url_launcher made.
  final launched = <String>[];

  setUp(() {
    launched.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // contacts permission: granted
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async => 1);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
      launched.add((call.arguments as Map)['url'] as String);
      return true;
    });
  });

  Future<void> pump(WidgetTester tester,
      {List<String>? phones, Map<String, String>? names}) async {
    await tester.pumpWidget(MaterialApp(
      home: NewChatScreen(
        chatService: _FakeChat(),
        authService: _FakeAuth(),
        readContacts: () async => (
          phones ?? [_asha, _ashaLandline, _bina, _unnamed],
          names ??
              {_asha: 'Asha', _ashaLandline: 'Asha', _bina: 'Bina Aunty'},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('people not on Vartalap are listed under Invite to Vartalap',
      (tester) async {
    await pump(tester);
    expect(find.text('Asha'), findsOneWidget, reason: 'on Vartalap');
    expect(find.text('Invite to Vartalap'), findsOneWidget);
    expect(find.text('Bina Aunty'), findsOneWidget);
    expect(find.text(_bina), findsOneWidget, reason: 'the number under it');
    expect(find.text(_unnamed), findsOneWidget, reason: 'no name: the number');
    expect(find.text(_ashaLandline), findsNothing,
        reason: 'Asha is on Vartalap by her other number');
    expect(find.widgetWithText(TextButton, 'Invite'), findsNWidgets(2));
  });

  testWidgets('Invite opens the SMS app with the message filled in',
      (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Invite').first);
    await tester.pumpAndSettle();
    final uri = Uri.parse(launched.single);
    expect(uri.scheme, 'sms');
    expect(uri.path, _bina);
    expect(uri.queryParameters['body'], kInviteText);
    expect(launched.single, isNot(contains('+Vartalap')),
        reason: 'spaces as %20, not +');
    expect(kInviteText, contains('https://vartalap.one9x.org'));
  });

  testWidgets('search filters both sections, by name or number',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'bina');
    await tester.pumpAndSettle();
    expect(find.text('Bina Aunty'), findsOneWidget);
    expect(find.text('Asha'), findsNothing);
    expect(find.text(_unnamed), findsNothing);

    await tester.enterText(find.byType(TextField).first, '0003');
    await tester.pumpAndSettle();
    expect(find.text(_unnamed), findsOneWidget);
    expect(find.text('Bina Aunty'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'ash');
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Invite to Vartalap'), findsNothing,
        reason: 'no invitee matches');
  });

  testWidgets('2,000 contacts: only the rows on screen are built',
      (tester) async {
    final phones = [
      for (var i = 0; i < 2000; i++) '+9197${i.toString().padLeft(8, '0')}'
    ];
    await pump(tester,
        phones: phones, names: {for (final p in phones) p: 'Person $p'});
    expect(find.text('Invite to Vartalap'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
  });
}

class _FakeChat implements ChatService {
  @override
  Future<List<ContactRow>> discoverContacts({
    List<String> normalizedPhones = const [],
    Map<String, String> contactBookNamesByPhone = const {},
  }) async =>
      [
        ContactRow(
          userId: '00000000a',
          phoneHash: _hash(_asha),
          contactBookName: 'Asha',
          lastRefreshedMs: 0,
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeAuth extends AuthService {
  _FakeAuth()
      : super(
          client: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          storage: _NoopStorage(),
        );

  @override
  String? get currentUserId => 'abcdef012';
}

class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}
