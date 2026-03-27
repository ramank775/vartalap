import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/widgets/message_input.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_testing/vartalap_testing.dart';
import 'test_app_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockVartalapChatClient mockMessagingClient;
  late VartalapChatClientFlutter flutterClient;
  late Contact currentUser;
  late ChannelModel testChannel;

  setUp(() async {
    await TestAppWrapper.setup();

    mockMessagingClient = MockVartalapChatClient(
      mockUserId: 'uid_me',
      tokenManager: MockTokenManager(),
      initialScenario: ManualTakeoverScenario(),
    );
    flutterClient = VartalapChatClientFlutter(
      apiKey: 'test',
      client: mockMessagingClient,
      inMemory: true,
    );

    currentUser = const Contact(
      id: 1,
      name: 'Me',
      username: 'me',
      uid: 'uid_me',
      status: ContactStatus.active,
    );
  });

  tearDown(() {
    flutterClient.dispose();
  });

  Widget createChatScreen(ChatClient chatClient) {
    return MaterialApp(
      home: Provider<VartalapChatClientFlutter>.value(
        value: flutterClient,
        child: CurrentUser(
          user: currentUser,
          child: ChatScreen(chatClient),
        ),
      ),
    );
  }

  Future<void> setupChannelData(WidgetTester tester) async {
    await tester.runAsync(() async {
      await flutterClient.login(
          messaging.Credential(username: 'uid_me', externalAuthToken: 'token')
            ..deviceId = 'dev');
      await flutterClient.init();

      await flutterClient.db.into(flutterClient.db.contacts).insert(
          ContactsCompanion.insert(
              id: const Value(1),
              uid: const Value('uid_me'),
              username: const Value('me'),
              status: ContactStatus.active),
          mode: InsertMode.insertOrIgnore);
      await flutterClient.db.into(flutterClient.db.contacts).insert(
          ContactsCompanion.insert(
              id: const Value(2),
              uid: const Value('uid_alice'),
              username: const Value('alice'),
              status: ContactStatus.active),
          mode: InsertMode.insertOrIgnore);

      final channelEntity = await flutterClient.db
          .into(flutterClient.db.channels)
          .insertReturning(ChannelsCompanion.insert(
              type: messaging.ChannelType.individual,
              cid: const Value('uid_alice'),
              config: const Value({})),
          mode: InsertMode.insertOrIgnore);
      testChannel = channelEntity;

      await flutterClient.db.into(flutterClient.db.members).insert(
          MembersCompanion.insert(
              channelId: testChannel.id, memberId: 1),
          mode: InsertMode.insertOrIgnore);
      await flutterClient.db.into(flutterClient.db.members).insert(
          MembersCompanion.insert(
              channelId: testChannel.id, memberId: 2),
          mode: InsertMode.insertOrIgnore);
    });
  }

  group('ChatScreen Integration Tests', () {
    testWidgets('Sending a message shows pending status', (tester) async {
      await setupChannelData(tester);

      final chatClient = await flutterClient.chat(
          channel: testChannel, currentUser: currentUser);
      await tester.pumpWidget(createChatScreen(chatClient));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChatScreen), findsOneWidget);

      // Type and send message
      await tester.enterText(
        find.descendant(
            of: find.byType(MessageInputWidget),
            matching: find.byType(TextField)),
        'Hello Alice',
      );
      await tester.pump(); // Let the icon switch from mic to send
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // Message should appear with pending icon (no auto-ack from ManualTakeoverScenario)
      expect(find.text('Hello Alice', findRichText: true), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsWidgets);

      // Cleanup
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Receiving a message updates the UI', (tester) async {
      await setupChannelData(tester);

      final chatClient = await flutterClient.chat(
          channel: testChannel, currentUser: currentUser);
      await tester.pumpWidget(createChatScreen(chatClient));
      await tester.pump(const Duration(milliseconds: 300));

      // Inject a message from Alice
      await tester.runAsync(() async {
        mockMessagingClient.injectMessage(messaging.RemoteMessage()
          ..id = 'in_123'
          ..head = messaging.Head(
            type: messaging.ChannelType.individual,
            to: 'uid_me',
            from: 'uid_alice',
            category: 'message',
          )
          ..meta = messaging.Meta()
          ..body = {'text': 'Hey there!'});

        await Future.delayed(const Duration(milliseconds: 500));
      });

      // Pump frames to update UI from DB stream
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Message should appear
      expect(find.text('Hey there!', findRichText: true), findsOneWidget);

      // Cleanup
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
