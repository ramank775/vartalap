/// Who can find you by your number (decision 223): the signup step after
/// the username, and the same screen from Settings › Privacy.
library vartalap.screens.discoverability_screen_test;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/login/discoverability.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const _book = <PickableContact>[
  (name: 'Amma', phones: ['+919800000001', '+919800000002']),
  (name: 'Ravi', phones: ['+919800000003']),
];

Future<List<PickableContact>?> _readBook() async => _book;

void main() {
  Finder button(String label) => find.widgetWithText(FilledButton, label);

  // a phone screen, so the whole list is laid out
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 3;
  });
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> pumpSignup(WidgetTester tester, _FakeAuth auth,
      {VoidCallback? onDone, ContactsReader readContacts = _readBook}) async {
    await tester.pumpWidget(MaterialApp(
      theme: lightThemeData,
      home: DiscoverabilityScreen(
          authService: auth, onDone: onDone, readContacts: readContacts),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('signup: no way back, Everyone ready to go, Continue saves it',
      (tester) async {
    final auth = _FakeAuth();
    var done = 0;
    await pumpSignup(tester, auth, onDone: () => done++);

    expect(find.text('Who can find you by your number?'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('You can change this later in Settings › Privacy.'),
        findsOneWidget);
    expect(
        tester
            .widget<RadioGroup<Discoverability>>(
                find.byType(RadioGroup<Discoverability>))
            .groupValue,
        Discoverability.everyone);

    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();
    expect(auth.saves, [(Discoverability.everyone, null)]);
    expect(done, 1);
  });

  testWidgets('Nobody: found only by username', (tester) async {
    final auth = _FakeAuth();
    await pumpSignup(tester, auth);
    await tester.tap(find.text('Nobody'));
    await tester.pump();
    expect(find.text('People can find you only by your @username'),
        findsOneWidget);
    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();
    expect(auth.saves, [(Discoverability.nobody, null)]);
  });

  testWidgets('Only people I choose opens the contacts, then saves the list',
      (tester) async {
    final auth = _FakeAuth();
    await pumpSignup(tester, auth);

    await tester.tap(find.text('Only people I choose'));
    await tester.pumpAndSettle();
    expect(find.text('Choose people'), findsOneWidget);
    expect(find.text('+919800000001, +919800000002'), findsOneWidget);

    // a contact with two numbers: both are chosen
    await tester.tap(find.text('Amma'));
    await tester.pump();
    expect(find.textContaining('2 chosen.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('2 numbers chosen'), findsOneWidget);
    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();
    expect(auth.saves.single.$1, Discoverability.chosen);
    expect(auth.saves.single.$2, ['+919800000001', '+919800000002']);
  });

  testWidgets('backing out of the contacts keeps the previous choice',
      (tester) async {
    final auth = _FakeAuth();
    await pumpSignup(tester, auth);
    await tester.tap(find.text('Only people I choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ravi'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<RadioGroup<Discoverability>>(
                find.byType(RadioGroup<Discoverability>))
            .groupValue,
        Discoverability.everyone);
    expect(find.text('People you pick from your contacts'), findsOneWidget);
  });

  testWidgets('the contacts can be searched; no permission asks for it',
      (tester) async {
    await pumpSignup(tester, _FakeAuth());
    await tester.tap(find.text('Only people I choose'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rav');
    await tester.pump();
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Amma'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await pumpSignup(tester, _FakeAuth(), readContacts: () async => null);
    await tester.tap(find.text('Only people I choose'));
    await tester.pumpAndSettle();
    expect(find.text('Allow Vartalap to read your contacts to choose people.'),
        findsOneWidget);
  });

  testWidgets('a save that fails says so and stays', (tester) async {
    final auth = _FakeAuth()..fail = true;
    var done = 0;
    await pumpSignup(tester, auth, onDone: () => done++);
    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(done, 0);
  });

  testWidgets('from Settings: the server value shows, Save goes back',
      (tester) async {
    final auth = _FakeAuth()
      ..serverMode = Discoverability.chosen
      ..chosen = ['+919800000003'];
    await tester.pumpWidget(MaterialApp(
      theme: lightThemeData,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => DiscoverabilityScreen(
                  authService: auth, readContacts: _readBook))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('1 number chosen'), findsOneWidget);
    expect(find.text('Choose people'), findsOneWidget);
    await tester.tap(find.text('Everyone'));
    await tester.pump();
    await tester.tap(button('Save'));
    await tester.pumpAndSettle();
    expect(auth.saves, [(Discoverability.everyone, null)]);
    expect(find.text('open'), findsOneWidget, reason: 'popped back');
  });
}

class _FakeAuth extends AuthService {
  Discoverability serverMode = Discoverability.everyone;
  List<String> chosen = const [];
  bool fail = false;
  final saves = <(Discoverability, List<String>?)>[];

  _FakeAuth()
      : super(
          client: AuthClient(baseUrl: Uri.parse('https://example.invalid')),
          storage: _NoopStorage(),
        );

  @override
  Discoverability get discoverability => serverMode;

  @override
  List<String> get chosenPhones => chosen;

  @override
  Future<Discoverability> refreshDiscoverability() async => serverMode;

  @override
  Future<void> setDiscoverability(Discoverability mode,
      {List<String>? chosen}) async {
    if (fail) throw StateError('offline');
    saves.add((mode, chosen));
    serverMode = mode;
    if (chosen != null) this.chosen = chosen;
  }
}

class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}
