import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/dao/dao.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

import '../factories/test_data_factories.dart';

/// ChatDao tests that gracefully handle SQLite dependency
/// and focus on testing real business logic when possible
void main() {
  group('ChatDao Tests - Local-First Business Logic', () {

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    group('Database-Independent Business Logic', () {
      test('MessageFilter should validate filter parameters correctly', () {
        // Test real filter logic without database
        final stateFilter = MessageFilter(state: MessageState.sent);
        final typeFilter = MessageFilter(type: MessageType.text);
        final senderFilter = MessageFilter(senderId: 123);
        final messageIdFilter = MessageFilter(messageId: 456);

        expect(stateFilter.state, equals(MessageState.sent));
        expect(stateFilter.type, isNull);
        expect(stateFilter.senderId, isNull);

        expect(typeFilter.type, equals(MessageType.text));
        expect(typeFilter.state, isNull);

        expect(senderFilter.senderId, equals(123));
        expect(messageIdFilter.messageId, equals(456));
      });

      test('Message state transitions should follow business rules', () {
        // Test real message business logic
        final message = TestDataFactories.createChatMessage(
          state: MessageState.pending,
        );

        // Test forward state progression
        expect(message.updateState(MessageState.sent), isTrue);
        expect(message.state, equals(MessageState.sent));

        expect(message.updateState(MessageState.delivered), isTrue);
        expect(message.state, equals(MessageState.delivered));

        expect(message.updateState(MessageState.read), isTrue);
        expect(message.state, equals(MessageState.read));

        // Test that backward transitions are not allowed
        expect(message.updateState(MessageState.pending), isFalse);
        expect(message.state, equals(MessageState.read));
      });

      test('Chat message models should handle different types correctly', () {
        // Test real message model behavior
        final textMessage = TestDataFactories.createChatMessage(
          text: "Hello World",
          senderId: 123,
        );

        expect(textMessage.type, equals(MessageType.text));
        expect(textMessage.text, equals("Hello World"));
        expect(textMessage.senderId, equals(123));
        expect(textMessage.previewContent, equals("Hello World"));

        // Test notification content generation
        final notificationContent = textMessage.notificationContent;
        expect(notificationContent.show, isTrue);
        expect(notificationContent.content, equals("Hello World"));
      });

      test('Message equality should work correctly', () {
        // Test real equality logic
        final message1 = TestDataFactories.createChatMessage(id: 1, text: "Test");
        final message2 = TestDataFactories.createChatMessage(id: 1, text: "Different text");
        final message3 = TestDataFactories.createChatMessage(id: 2, text: "Test");

        // Messages with same ID should be equal
        expect(message1, equals(message2));
        expect(message1.hashCode, equals(message2.hashCode));

        // Messages with different IDs should not be equal
        expect(message1, isNot(equals(message3)));
      });

      test('Member model should handle user relationships correctly', () {
        // Test real member business logic
        final user = TestDataFactories.createContact(id: 1, name: "John Doe");
        final member = TestDataFactories.createMember(
          user: user,
          role: "admin",
          since: DateTime.now().subtract(Duration(days: 30)),
        );

        expect(member.user.id, equals(1));
        expect(member.user.displayName, equals("John Doe"));
        expect(member.role, equals("admin"));
        expect(member.since.isBefore(DateTime.now()), isTrue);
      });
    });

    group('Database Operations (when SQLite available)', () {
      late ChatDatabase? database;
      late ChatDao? chatDao;
      late ChannelDao? channelDao;

      setUp(() async {
        TestDataFactories.resetCounters();

        try {
          // Attempt to create in-memory database
          database = ChatDatabase(userId: "test_user", inMemory: true);

          // Test basic connectivity
          await database!.customSelect('SELECT 1').getSingle();

          chatDao = database!.chatDao;
          channelDao = database!.channelDao;
        } catch (e) {
          // SQLite not available - skip database tests
          database = null;
          chatDao = null;
          channelDao = null;
        }
      });

      tearDown(() async {
        if (database != null) {
          await database!.close();
        }
      });

      test('should send and retrieve messages locally', () async {
        // Skip if SQLite not available
        if (database == null || chatDao == null || channelDao == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev to run this test');
          return;
        }

        // Test real local database operations
        final channel = TestDataFactories.createChannel(id: 1);
        final createdChannel = await channelDao!.createChannel(channel, []);

        final message = TestDataFactories.createChatMessage(
          senderId: 123,
          text: "Local test message",
        );

        // Test real message persistence
        final messageId = await chatDao!.sendMessage(message, createdChannel);
        expect(messageId, greaterThan(0));

        // Test real message retrieval
        final messages = await chatDao!.getMessages(channel: createdChannel).get();
        expect(messages, hasLength(1));
        expect((messages.first).text, equals("Local test message"));
      });

      test('should handle message state updates locally', () async {
        if (database == null || chatDao == null || channelDao == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev to run this test');
          return;
        }

        final channel = TestDataFactories.createChannel(id: 1);
        final createdChannel = await channelDao!.createChannel(channel, []);

        final message = TestDataFactories.createChatMessage(
          state: MessageState.pending,
          text: "State test message",
        );

        final messageId = await chatDao!.sendMessage(message, createdChannel);

        // Test real state update
        final updatedMessage = TestDataFactories.createChatMessage(
          state: MessageState.sent,
          text: "State test message",
        );
        await chatDao!.updateMessage(messageId, updatedMessage);

        final messages = await chatDao!.getMessages(channel: createdChannel).get();
        expect(messages.first.state, equals(MessageState.sent));
      });

      test('should generate chat previews correctly', () async {
        if (database == null || chatDao == null || channelDao == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev to run this test');
          return;
        }

        final channel = TestDataFactories.createChannel();
        final createdChannel = await channelDao!.createChannel(channel, []);

        final message = TestDataFactories.createChatMessage(
          text: "Preview test message",
        );
        await chatDao!.sendMessage(message, createdChannel);

        // Test real chat preview generation
        final previews = await chatDao!.getChatPreviews().get();
        expect(previews, hasLength(1));
        expect(previews.first.channel.id, equals(createdChannel.id));
        expect(previews.first.lastMessage, isNotNull);
      });

      test('should handle reactive queries correctly', () async {
        if (database == null || chatDao == null || channelDao == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev to run this test');
          return;
        }

        final channel = TestDataFactories.createChannel();
        final createdChannel = await channelDao!.createChannel(channel, []);

        // Test real reactive behavior
        final messageStream = chatDao!.getMessages(channel: createdChannel).watch();

        // Initially empty
        await expectLater(messageStream, emits(isEmpty));

        // Add message and verify reactive update
        final message = TestDataFactories.createChatMessage(text: "Reactive test");
        await chatDao!.sendMessage(message, createdChannel);

        await expectLater(messageStream, emits(hasLength(1)));
      });
    });
  });
}