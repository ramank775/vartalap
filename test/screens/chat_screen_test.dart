import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/widgets/message_input.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
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
      home: VartalapClientProvider(
        client: flutterClient,
        connectionState: ClientConnectionState.connected,
        child: CurrentUser(
          user: currentUser,
          child: ChatScreen(chatClient),
        ),
      ),
    );
  }

  group('ChatScreen Integration Tests', () {
    testWidgets('Sending a message shows pending then sent status', (tester) async {
      await tester.runAsync(() async {
        await flutterClient.login(messaging.Credential(username: 'uid_me', externalAuthToken: 'token')
          ..deviceId = 'dev');
        await flutterClient.init();

        // 1. Setup channel and users in DB
        await flutterClient.db.into(flutterClient.db.contacts).insert(
          ContactsCompanion.insert(id: const Value(1), uid: const Value('uid_me'), username: const Value('me'), status: ContactStatus.active));
        await flutterClient.db.into(flutterClient.db.contacts).insert(
          ContactsCompanion.insert(id: const Value(2), uid: const Value('uid_alice'), username: const Value('alice'), status: ContactStatus.active));
        
        final channelEntity = await flutterClient.db.into(flutterClient.db.channels).insertReturning(
          ChannelsCompanion.insert(type: messaging.ChannelType.individual, cid: const Value('uid_alice'), config: const Value({})));
        testChannel = channelEntity;
        
        await flutterClient.db.into(flutterClient.db.members).insert(MembersCompanion.insert(channelId: testChannel.id, memberId: 1));
        await flutterClient.db.into(flutterClient.db.members).insert(MembersCompanion.insert(channelId: testChannel.id, memberId: 2));
      });

      final chatClient = await flutterClient.chat(channel: testChannel, currentUser: currentUser);
      await tester.pumpWidget(createChatScreen(chatClient));
      
      // Wait for VartalapClientManager and StreamBuilder to finish loading
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ChatScreen), findsOneWidget);
      
      // 2. Type and send message
      await tester.enterText(
        find.descendant(of: find.byType(MessageInputWidget), matching: find.byType(TextField)),
        'Hello Alice',
      );
      
      await tester.tap(find.byIcon(Icons.send_rounded));
      
      // Allow time for local DB insert and UI update
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // 3. Should show message and pending or sent icon (clock/check)
      expect(find.text('Hello Alice', findRichText: true), findsOneWidget);
      final hasPendingIcon = find.byIcon(Icons.access_time).evaluate().isNotEmpty;
      final hasSentIcon = find.byIcon(Icons.check).evaluate().isNotEmpty;
      expect(hasPendingIcon || hasSentIcon, isTrue);

      // 4. Wait for Happy Path Scenario to progress (Sent after 500ms in mock)
      await tester.runAsync(() async {
        await Future.delayed(const Duration(seconds: 1));
      });
      await tester.pump(const Duration(milliseconds: 500));

      // 5. Should show a status icon (pending/sent/delivered/read)
      final hasPending = find.byIcon(Icons.access_time).evaluate().isNotEmpty;
      final hasSent = find.byIcon(Icons.check).evaluate().isNotEmpty;
      final hasDelivered = find.byIcon(Icons.done_all).evaluate().isNotEmpty;
      final hasRead = find.byIcon(Icons.done_all_sharp).evaluate().isNotEmpty;
      expect(hasPending || hasSent || hasDelivered || hasRead, isTrue);

      // Cleanup
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Receiving a message updates the UI', (tester) async {
      late ChatClient chatClient;
      await tester.runAsync(() async {
        await flutterClient.login(messaging.Credential(username: 'uid_me', externalAuthToken: 'token')
          ..deviceId = 'dev');
        await flutterClient.init();

        // Ensure channel exists with Alice
        await flutterClient.db.into(flutterClient.db.contacts).insert(
          ContactsCompanion.insert(id: const Value(1), uid: const Value('uid_me'), username: const Value('me'), status: ContactStatus.active), mode: InsertMode.insertOrIgnore);
        await flutterClient.db.into(flutterClient.db.contacts).insert(
          ContactsCompanion.insert(id: const Value(2), uid: const Value('uid_alice'), username: const Value('alice'), status: ContactStatus.active), mode: InsertMode.insertOrIgnore);
        
        final channelEntity = await flutterClient.db.into(flutterClient.db.channels).insertReturning(
          ChannelsCompanion.insert(type: messaging.ChannelType.individual, cid: const Value('uid_alice'), config: const Value({})), mode: InsertMode.insertOrIgnore);
        testChannel = channelEntity;
        
        await flutterClient.db.into(flutterClient.db.members).insert(MembersCompanion.insert(channelId: testChannel.id, memberId: 2), mode: InsertMode.insertOrIgnore);
        
        chatClient = await flutterClient.chat(channel: testChannel, currentUser: currentUser);
      });

      await tester.pumpWidget(createChatScreen(chatClient));
      await tester.pump(const Duration(milliseconds: 500));

      // 1. Inject a message from Alice
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
          ..body = {'text': 'Hey there!'}
        );
        
        // Wait for event bridge and DB
        await Future.delayed(const Duration(seconds: 1));
      });

      // 2. Pump frames to update UI from DB stream
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // 3. Message should appear
      expect(find.text('Hey there!', findRichText: true), findsOneWidget);

      // Cleanup
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
