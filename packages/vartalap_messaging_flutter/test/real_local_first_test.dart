import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';

import 'factories/test_data_factories.dart';

/// Tests that validate REAL local-first functionality
/// WITHOUT over-mocking the core business logic
void main() {
  group('Real Local-First Functionality Tests', () {
    late ChatDatabase database;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDataFactories.resetCounters();

      // Use real in-memory database, not mocked
      database = ChatDatabase(userId: "test_user", inMemory: true);
    });

    tearDown(() async {
      await database.close();
    });

    test('Database should persist data locally without server', () async {
      // Arrange - Use real DAO operations
      final channelDao = database.channelDao;
      final chatDao = database.chatDao;

      final channel = TestDataFactories.createChannel(id: 1);
      final contact = TestDataFactories.createContact(id: 1);
      final member = TestDataFactories.createMember(user: contact);

      // Act - Test REAL local persistence
      final createdChannel = await channelDao.createChannel(channel, [member]);

      final message = TestDataFactories.createChatMessage(
        senderId: contact.id,
        text: "Test local message",
      );
      await chatDao.sendMessage(message, createdChannel);

      // Assert - Data should persist in local database
      final storedChannels = await channelDao.getChannels().get();
      final storedMessages = await chatDao.getMessages(channel: createdChannel).get();

      expect(storedChannels, hasLength(1));
      expect(storedChannels.first.id, equals(createdChannel.id));
      expect(storedMessages, hasLength(1));
      expect((storedMessages.first).text, equals("Test local message"));
    });

    test('Local operations should work in offline-first manner', () async {
      // Arrange
      final channelDao = database.channelDao;
      final chatDao = database.chatDao;

      // Act - Simulate multiple local operations
      final channels = TestDataFactories.createChannels(3);
      final createdChannels = <ChannelModel>[];

      for (final channel in channels) {
        final created = await channelDao.createChannel(channel, []);
        createdChannels.add(created);
      }

      // Add messages to each channel
      for (final channel in createdChannels) {
        for (int i = 0; i < 5; i++) {
          final message = TestDataFactories.createChatMessage(
            text: "Message $i in ${channel.displayName}",
          );
          await chatDao.sendMessage(message, channel);
        }
      }

      // Assert - All data should be available locally
      final allChannels = await channelDao.getChannels().get();
      expect(allChannels, hasLength(3));

      for (final channel in allChannels) {
        final messages = await chatDao.getMessages(channel: channel).get();
        expect(messages, hasLength(5));
      }
    });

    test('Chat previews should update reactively with local changes', () async {
      // Arrange
      final channelDao = database.channelDao;
      final chatDao = database.chatDao;

      final channel = TestDataFactories.createChannel();
      final createdChannel = await channelDao.createChannel(channel, []);

      // Act - Watch chat previews stream (real reactive behavior)
      final previewStream = chatDao.getChatPreviews(currentUserId: 1).watch();

      // Initially no previews (no messages)
      await expectLater(
        previewStream,
        emits(isEmpty),
      );

      // Send a message
      final message = TestDataFactories.createChatMessage(text: "First message");
      await chatDao.sendMessage(message, createdChannel);

      // Assert - Preview should update reactively
      await expectLater(
        previewStream,
        emits(hasLength(1)),
      );

      // Send another message and verify update
      final secondMessage = TestDataFactories.createChatMessage(text: "Latest message");
      await chatDao.sendMessage(secondMessage, createdChannel);

      // Should still have 1 preview but with updated last message
      final previews = await chatDao.getChatPreviews(currentUserId: 1).get();
      expect(previews, hasLength(1));
      expect((previews.first.lastMessage)!.text, equals("Latest message"));
    });

    test('Local data should handle concurrent operations correctly', () async {
      // Arrange
      final channelDao = database.channelDao;
      final chatDao = database.chatDao;

      final channel = TestDataFactories.createChannel();
      final createdChannel = await channelDao.createChannel(channel, []);

      // Act - Simulate concurrent message sending
      final futures = <Future>[];
      for (int i = 0; i < 10; i++) {
        final message = TestDataFactories.createChatMessage(
          text: "Concurrent message $i",
        );
        futures.add(chatDao.sendMessage(message, createdChannel));
      }

      // Wait for all operations to complete
      await Future.wait(futures);

      // Assert - All messages should be stored correctly
      final messages = await chatDao.getMessages(channel: createdChannel).get();
      expect(messages, hasLength(10));

      // Verify messages have unique IDs (no conflicts)
      final messageIds = messages.map((m) => m.id).toSet();
      expect(messageIds, hasLength(10));
    });

    test('Message state transitions should work locally', () async {
      // Arrange
      final channelDao = database.channelDao;
      final chatDao = database.chatDao;

      final channel = TestDataFactories.createChannel();
      final createdChannel = await channelDao.createChannel(channel, []);

      // Act - Send message and transition states
      final message = TestDataFactories.createChatMessage(
        text: "State transition test",
        state: MessageState.pending,
      );
      final messageId = await chatDao.sendMessage(message, createdChannel);

      // Update to sent
      final sentMessage = TestDataFactories.createChatMessage(
        text: "State transition test",
        state: MessageState.sent,
      );
      await chatDao.updateMessage(messageId, sentMessage);

      // Assert - State should be updated locally
      final messages = await chatDao.getMessages(channel: createdChannel).get();
      expect(messages.first.state, equals(MessageState.sent));

      // Test batch read marking
      await chatDao.markMessagesAsRead([messageId]);

      final readMessages = await chatDao.getMessages(channel: createdChannel).get();
      expect(readMessages.first.state, equals(MessageState.read));
    });

    test('Local search and filtering should work efficiently', () async {
      // Arrange
      final channelDao = database.channelDao;
      final chatDao = database.chatDao;

      final channel = TestDataFactories.createChannel();
      final createdChannel = await channelDao.createChannel(channel, []);

      // Create messages with different states and content
      final testMessages = [
        TestDataFactories.createChatMessage(text: "Hello world", state: MessageState.sent),
        TestDataFactories.createChatMessage(text: "Flutter testing", state: MessageState.read),
        TestDataFactories.createChatMessage(text: "Local first", state: MessageState.delivered),
        TestDataFactories.createChatMessage(text: "Database query", state: MessageState.sent),
      ];

      for (final message in testMessages) {
        await chatDao.sendMessage(message, createdChannel);
      }

      // Act & Assert - Filter by state
      final sentMessages = await chatDao.getMessages(
        channel: createdChannel,
        filter: MessageFilter(state: MessageState.sent),
      ).get();
      expect(sentMessages, hasLength(2));

      final readMessages = await chatDao.getMessages(
        channel: createdChannel,
        filter: MessageFilter(state: MessageState.read),
      ).get();
      expect(readMessages, hasLength(1));
    });
  });
}