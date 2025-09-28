import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/dao/dao.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

import '../utils/database_test_utils.dart';
import '../factories/test_data_factories.dart';

void main() {
  group('ChatDao Tests - Local-First Functionality', () {
    late ChatDatabase database;
    late ChatDao chatDao;
    late ChannelDao channelDao;

    setUpAll(() {
      // Initialize Flutter binding for platform channels and database operations
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      TestDataFactories.resetCounters();
      database = DatabaseTestUtils.createInMemoryDatabase(userId: "test_user");
      await DatabaseTestUtils.verifyDatabaseConnectivity(database);
      chatDao = database.chatDao;
      channelDao = database.channelDao;
    });

    tearDown(() async {
      await database.close();
    });

    group('Message Operations', () {
      test('should send message and store locally', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        final message = TestDataFactories.createTextMessage(
          senderId: 123,
          text: "Hello, World!",
        );

        // Insert test channel first
        await channelDao.createChannel(channel, []);

        // Act - Send message locally
        final messageId = await chatDao.sendMessage(message, channel);

        // Assert
        expect(messageId, isNotNull);
        expect(messageId, greaterThan(0));

        // Verify message was stored
        final messages = await chatDao.getMessages(channel: channel).get();
        expect(messages, hasLength(1));
        expect((messages.first as TextMessage).text, equals("Hello, World!"));
        expect(messages.first.senderId, equals(123));
      });

      test('should retrieve messages reactively', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        await channelDao.createChannel(channel, []);

        final messages = TestDataFactories.createConversation(
          messageCount: 3,
          senderIds: [1, 2],
        );

        // Act - Send multiple messages
        for (final message in messages) {
          await chatDao.sendMessage(message, channel);
        }

        // Assert - Test reactive query
        final stream = chatDao.getMessages(channel: channel).watch();
        
        await expectLater(
          stream,
          emits(hasLength(3)),
        );

        // Add another message and verify stream updates
        final newMessage = TestDataFactories.createTextMessage(
          text: "New message",
        );
        await chatDao.sendMessage(newMessage, channel);

        await expectLater(
          stream,
          emits(hasLength(4)),
        );
      });

      test('should update message content', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        await channelDao.createChannel(channel, []);

        final originalMessage = TestDataFactories.createTextMessage(
          text: "Original text",
          state: MessageState.pending,
        );

        // Act - Send message and update it
        final messageId = await chatDao.sendMessage(originalMessage, channel);
        
        final editedMessage = TestDataFactories.createTextMessage(
          text: "Edited text",
          state: MessageState.sent,
        );
        await chatDao.updateMessage(messageId, editedMessage);

        // Assert
        final messages = await chatDao.getMessages(channel: channel).get();
        expect(messages, hasLength(1));
        expect((messages.first as TextMessage).text, equals("Edited text"));
        expect(messages.first.state, equals(MessageState.sent));
      });

      test('should delete message locally', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        await channelDao.createChannel(channel, []);

        final message = TestDataFactories.createTextMessage(
          text: "Message to delete",
        );

        // Act - Send and then delete message
        final messageId = await chatDao.sendMessage(message, channel);
        await chatDao.deleteMessage(messageId);

        // Assert
        final messages = await chatDao.getMessages(channel: channel).get();
        expect(messages, isEmpty);
      });

      test('should mark messages as read', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        await channelDao.createChannel(channel, []);

        // Send some unread messages
        final messageIds = <int>[];
        for (int i = 0; i < 3; i++) {
          final message = TestDataFactories.createTextMessage(
            text: "Unread message $i",
            state: MessageState.delivered,
          );
          final messageId = await chatDao.sendMessage(message, channel);
          messageIds.add(messageId);
        }

        // Act - Mark messages as read
        await chatDao.markMessagesAsRead(messageIds);

        // Assert
        final messages = await chatDao.getMessages(channel: channel).get();
        expect(messages, hasLength(3));
        for (final message in messages) {
          expect(message.state, equals(MessageState.read));
        }
      });

      test('should mark entire channel as read', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        await channelDao.createChannel(channel, []);

        // Send some unread messages
        for (int i = 0; i < 5; i++) {
          final message = TestDataFactories.createTextMessage(
            text: "Unread message $i",
            state: MessageState.delivered,
          );
          await chatDao.sendMessage(message, channel);
        }

        // Act - Mark entire channel as read
        await chatDao.markChannelAsRead(channel.id);

        // Assert
        final messages = await chatDao.getMessages(channel: channel).get();
        expect(messages, hasLength(5));
        for (final message in messages) {
          expect(message.state, equals(MessageState.read));
        }
      });
    });

    group('Chat Previews', () {
      test('should generate chat previews with last message', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        await channelDao.createChannel(channel, []);

        final messages = TestDataFactories.createConversation(
          messageCount: 5,
        );

        // Send messages in chronological order
        for (final message in messages) {
          await chatDao.sendMessage(message, channel);
        }

        // Act
        final previews = await chatDao.getChatPreviews().get();

        // Assert
        expect(previews, hasLength(1));
        final preview = previews.first;
        expect(preview.channel.id, equals(channel.id));
        expect(preview.lastMessage, isNotNull);
        expect(preview.unreadCount, equals(5)); // All messages are sent by default, not read
      });

      test('should calculate unread message count correctly', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        await channelDao.createChannel(channel, []);

        // Send some read messages
        final readMessage = TestDataFactories.createTextMessage(
          state: MessageState.read,
        );
        await chatDao.sendMessage(readMessage, channel);

        // Send some unread messages
        for (int i = 0; i < 3; i++) {
          final unreadMessage = TestDataFactories.createTextMessage(
            state: MessageState.delivered,
            text: "Unread message $i",
          );
          await chatDao.sendMessage(unreadMessage, channel);
        }

        // Act
        final previews = await chatDao.getChatPreviews().get();

        // Assert
        expect(previews, hasLength(1));
        expect(previews.first.unreadCount, equals(3));
      });
    });

    group('Member Operations', () {
      test('should add members to channel', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        final members = TestDataFactories.createMembers(2);

        await channelDao.createChannel(channel, []);

        // First sync the contacts that the members reference
        final contacts = members.map((m) => m.user).toList();
        await channelDao.syncContacts(contacts);

        // Act
        await chatDao.addMembers(members, channel);

        // Assert
        final retrievedMembers = await chatDao.getMembers(channelId: channel.id).get();
        expect(retrievedMembers, hasLength(2));
      });

      test('should remove member from channel', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        final member = TestDataFactories.createMember();

        // First sync the contact that the member references
        await channelDao.syncContacts([member.user]);

        await channelDao.createChannel(channel, [member]);

        // Act
        await chatDao.removeMember(member, channel);

        // Assert
        final members = await chatDao.getMembers(channelId: channel.id).get();
        expect(members, isEmpty);
      });
    });

    group('Performance Tests', () {
      test('should handle large number of messages efficiently', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        await channelDao.createChannel(channel, []);

        const messageCount = 100; // Reduced for faster testing
        final stopwatch = Stopwatch()..start();

        // Act - Insert large number of messages
        for (int i = 0; i < messageCount; i++) {
          final message = TestDataFactories.createTextMessage(
            text: "Message $i",
          );
          await chatDao.sendMessage(message, channel);
        }

        stopwatch.stop();

        // Assert - Verify all messages stored and performance is reasonable
        final messages = await chatDao.getMessages(channel: channel).get();
        expect(messages, hasLength(messageCount));
        
        // Performance assertion - should complete within reasonable time
        expect(stopwatch.elapsedMilliseconds, lessThan(2000)); // 2 seconds max
      });

      test('should efficiently retrieve messages by filter', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        await channelDao.createChannel(channel, []);

        // Insert test messages with different states
        for (int i = 0; i < 20; i++) {
          final message = TestDataFactories.createTextMessage(
            text: "Message $i",
            state: i % 2 == 0 ? MessageState.read : MessageState.delivered,
          );
          await chatDao.sendMessage(message, channel);
        }

        // Act - Query with filter
        final readMessages = await chatDao.getMessages(
          channel: channel,
          filter: MessageFilter(state: MessageState.read),
        ).get();

        // Assert
        expect(readMessages, hasLength(10)); // Half should be read
        for (final message in readMessages) {
          expect(message.state, equals(MessageState.read));
        }
      });
    });
  });
}

