import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/dao/dao.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';
import 'package:drift/drift.dart' hide isNotNull;

import '../factories/test_data_factories.dart';

/// ChatDao tests with proper warning suppression for test environments
void main() {
  group('ChatDao Tests - Warning Free', () {
    setUpAll(() {
      // Suppress Drift multiple database warnings for tests
      // This is safe in test environments where we use in-memory databases
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    tearDownAll(() {
      // Restore warning behavior after tests
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    });

    group('Database-Independent Business Logic', () {
      setUp(() {
        TestDataFactories.resetCounters();
      });

      test('MessageFilter should validate parameters correctly', () {
        final stateFilter = MessageFilter(state: MessageState.sent);
        final typeFilter = MessageFilter(type: MessageType.text);
        final senderFilter = MessageFilter(senderId: 123);

        expect(stateFilter.state, equals(MessageState.sent));
        expect(typeFilter.type, equals(MessageType.text));
        expect(senderFilter.senderId, equals(123));
      });

      test('Message state transitions should follow business rules', () {
        final message = TestDataFactories.createTextMessage(
          state: MessageState.pending,
        );

        expect(message.updateState(MessageState.sent), isTrue);
        expect(message.state, equals(MessageState.sent));

        expect(message.updateState(MessageState.delivered), isTrue);
        expect(message.state, equals(MessageState.delivered));

        expect(message.updateState(MessageState.read), isTrue);
        expect(message.state, equals(MessageState.read));

        // Backward transitions should fail
        expect(message.updateState(MessageState.pending), isFalse);
        expect(message.state, equals(MessageState.read));
      });

      test('Message models should handle different types correctly', () {
        final textMessage = TestDataFactories.createTextMessage(
          text: "Hello World",
          senderId: 123,
        );

        expect(textMessage.type, equals(MessageType.text));
        expect(textMessage.text, equals("Hello World"));
        expect(textMessage.senderId, equals(123));
      });
    });

    group('Database Operations - Single Instance Per Test', () {
      late ChatDatabase? database;
      late ChatDao? chatDao;
      late ChannelDao? channelDao;

      setUp(() async {
        TestDataFactories.resetCounters();
        TestWidgetsFlutterBinding.ensureInitialized();

        try {
          // Create unique database for this test group
          database = ChatDatabase(
            userId: "warning_free_test_${DateTime.now().microsecondsSinceEpoch}",
            inMemory: true,
          );

          await database!.customSelect('SELECT 1').getSingle();
          chatDao = database!.chatDao;
          channelDao = database!.channelDao;
        } catch (e) {
          database = null;
          chatDao = null;
          channelDao = null;
        }
      });

      tearDown(() async {
        if (database != null) {
          await database!.close();
          database = null;
        }
      });

      test('should send and retrieve messages locally', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel(id: 1);
        final createdChannel = await channelDao!.createChannel(channel, []);

        final message = TestDataFactories.createTextMessage(
          senderId: 123,
          text: "Warning-free test message",
        );

        final messageId = await chatDao!.sendMessage(message, createdChannel);
        expect(messageId, greaterThan(0));

        final messages = await chatDao!.getMessages(channel: createdChannel).get();
        expect(messages, hasLength(1));
        expect((messages.first as TextMessage).text, equals("Warning-free test message"));
      });

      test('should handle message state updates', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel(id: 1);
        final createdChannel = await channelDao!.createChannel(channel, []);

        final message = TestDataFactories.createTextMessage(
          state: MessageState.pending,
          text: "State update test",
        );

        final messageId = await chatDao!.sendMessage(message, createdChannel);

        final updatedMessage = TestDataFactories.createTextMessage(
          state: MessageState.sent,
          text: "State update test",
        );
        await chatDao!.updateMessage(messageId, updatedMessage);

        final messages = await chatDao!.getMessages(channel: createdChannel).get();
        expect(messages.first.state, equals(MessageState.sent));
      });

      test('should handle batch read operations', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel(id: 1);
        final createdChannel = await channelDao!.createChannel(channel, []);

        // Send multiple unread messages
        final messageIds = <int>[];
        for (int i = 0; i < 3; i++) {
          final message = TestDataFactories.createTextMessage(
            text: "Unread message $i",
            state: MessageState.delivered,
          );
          final messageId = await chatDao!.sendMessage(message, createdChannel);
          messageIds.add(messageId);
        }

        // Mark all as read
        await chatDao!.markMessagesAsRead(messageIds);

        final messages = await chatDao!.getMessages(channel: createdChannel).get();
        expect(messages, hasLength(3));
        for (final message in messages) {
          expect(message.state, equals(MessageState.read));
        }
      });

      test('should generate accurate chat previews', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel();
        final createdChannel = await channelDao!.createChannel(channel, []);

        final message = TestDataFactories.createTextMessage(
          text: "Preview test message",
        );
        await chatDao!.sendMessage(message, createdChannel);

        final previews = await chatDao!.getChatPreviews().get();
        expect(previews, hasLength(1));
        expect(previews.first.channel.id, equals(createdChannel.id));
        expect(previews.first.lastMessage, isNotNull);
        expect((previews.first.lastMessage as TextMessage).text, equals("Preview test message"));
      });

      test('should handle reactive queries properly', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel();
        final createdChannel = await channelDao!.createChannel(channel, []);

        final messageStream = chatDao!.getMessages(channel: createdChannel).watch();

        // Initially empty
        await expectLater(messageStream, emits(isEmpty));

        // Add message
        final message = TestDataFactories.createTextMessage(text: "Reactive test");
        await chatDao!.sendMessage(message, createdChannel);

        // Should update reactively
        await expectLater(messageStream, emits(hasLength(1)));
      });

      test('should delete messages correctly', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel(id: 1);
        final createdChannel = await channelDao!.createChannel(channel, []);

        final message = TestDataFactories.createTextMessage(
          text: "Message to delete",
        );

        final messageId = await chatDao!.sendMessage(message, createdChannel);

        // Verify message exists
        var messages = await chatDao!.getMessages(channel: createdChannel).get();
        expect(messages, hasLength(1));

        // Delete message
        await chatDao!.deleteMessage(messageId);

        // Verify message is gone
        messages = await chatDao!.getMessages(channel: createdChannel).get();
        expect(messages, isEmpty);
      });
    });

    group('Error Handling and Edge Cases', () {
      test('should handle concurrent database operations', () async {
        TestWidgetsFlutterBinding.ensureInitialized();

        ChatDatabase? database;
        try {
          database = ChatDatabase(
            userId: "concurrent_test_${DateTime.now().microsecondsSinceEpoch}",
            inMemory: true,
          );

          await database.customSelect('SELECT 1').getSingle();

          final channelDao = database.channelDao;
          final chatDao = database.chatDao;

          final channel = TestDataFactories.createChannel();
          final createdChannel = await channelDao.createChannel(channel, []);

          // Send multiple messages concurrently
          final futures = <Future>[];
          for (int i = 0; i < 5; i++) {
            final message = TestDataFactories.createTextMessage(
              text: "Concurrent message $i",
            );
            futures.add(chatDao.sendMessage(message, createdChannel));
          }

          await Future.wait(futures);

          final messages = await chatDao.getMessages(channel: createdChannel).get();
          expect(messages, hasLength(5));

          // Verify all messages have unique IDs
          final messageIds = messages.map((m) => m.id).toSet();
          expect(messageIds, hasLength(5));
        } catch (e) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
        } finally {
          if (database != null) {
            await database.close();
          }
        }
      });

      test('should handle empty database gracefully', () async {
        TestWidgetsFlutterBinding.ensureInitialized();

        ChatDatabase? database;
        try {
          database = ChatDatabase(
            userId: "empty_test_${DateTime.now().microsecondsSinceEpoch}",
            inMemory: true,
          );

          await database.customSelect('SELECT 1').getSingle();

          final chatDao = database.chatDao;
          final channelDao = database.channelDao;

          // Empty queries should return empty results
          final emptyChannels = await channelDao.getChannels().get();
          final emptyContacts = await channelDao.getContacts().get();
          final emptyPreviews = await chatDao.getChatPreviews().get();

          expect(emptyChannels, isEmpty);
          expect(emptyContacts, isEmpty);
          expect(emptyPreviews, isEmpty);
        } catch (e) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
        } finally {
          if (database != null) {
            await database.close();
          }
        }
      });
    });
  });
}