import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/dao/dao.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

import '../factories/test_data_factories.dart';
import '../utils/database_manager.dart';

/// ChatDao tests with proper database lifecycle management
/// Prevents "multiple database instances" warnings from Drift
void main() {
  group('ChatDao Tests - Properly Managed Database', () {
    setUpAll(() {
      TestDatabaseManager.reset();
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    tearDownAll(() async {
      await TestDatabaseManager.closeAllTestDatabases();
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
        final message = TestDataFactories.createChatMessage(
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
        final textMessage = TestDataFactories.createChatMessage(
          text: "Hello World",
          senderId: 123,
        );

        expect(textMessage.type, equals(MessageType.text));
        expect(textMessage.text, equals("Hello World"));
        expect(textMessage.senderId, equals(123));
      });
    });

    group('Database Operations - Managed Lifecycle', () {
      late ChatDatabase? database;
      late ChatDao? chatDao;
      late ChannelDao? channelDao;

      setUp(() async {
        TestDataFactories.resetCounters();

        // Use managed database to prevent multiple instance warnings
        database = await TestDatabaseManager.createSafeTestDatabase(
          testName: "chat_dao_test",
          userId: "test_user",
        );

        if (database != null) {
          chatDao = database!.chatDao;
          channelDao = database!.channelDao;
          
          // Clear tables to ensure clean state for each test
          await database!.delete(database!.messages).go();
          await database!.delete(database!.members).go();
          await database!.delete(database!.channels).go();
          await database!.delete(database!.contacts).go();
        }
      });

      // Note: Don't close database in tearDown - manager handles it

      test('should send and retrieve messages locally', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel(id: 1);
        final createdChannel = await channelDao!.createChannel(channel, []);

        final message = TestDataFactories.createChatMessage(
          senderId: 123,
          text: "Managed database test message",
        );

        final messageId = await chatDao!.sendMessage(message, createdChannel);
        expect(messageId, greaterThan(0));

        final messages = await chatDao!.getMessages(channel: createdChannel).get();
        expect(messages, hasLength(1));
        expect((messages.first).text, equals("Managed database test message"));
      });

      test('should handle message state updates', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel(id: 2);
        final createdChannel = await channelDao!.createChannel(channel, []);

        final message = TestDataFactories.createChatMessage(
          state: MessageState.pending,
          text: "State update test",
        );

        final messageId = await chatDao!.sendMessage(message, createdChannel);

        final updatedMessage = TestDataFactories.createChatMessage(
          state: MessageState.sent,
          text: "State update test",
        );
        await chatDao!.updateMessage(messageId, updatedMessage);

        final messages = await chatDao!.getMessages(channel: createdChannel).get();
        expect(messages.first.state, equals(MessageState.sent));
      });

      test('should generate chat previews correctly', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel(id: 3);
        final createdChannel = await channelDao!.createChannel(channel, []);

        final message = TestDataFactories.createChatMessage(
          text: "Preview test message",
        );
        await chatDao!.sendMessage(message, createdChannel);

        final previews = await chatDao!.getChatPreviews().get();
        expect(previews, hasLength(1));
        expect(previews.first.channel.id, equals(createdChannel.id));
        expect(previews.first.lastMessage, isNotNull);
      });

      test('should handle reactive queries without race conditions', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel(id: 4);
        final createdChannel = await channelDao!.createChannel(channel, []);

        final messageStream = chatDao!.getMessages(channel: createdChannel).watch();

        // Initially empty
        await expectLater(messageStream, emits(isEmpty));

        // Add message
        final message = TestDataFactories.createChatMessage(text: "Reactive test");
        await chatDao!.sendMessage(message, createdChannel);

        // Should update reactively
        await expectLater(messageStream, emits(hasLength(1)));
      });

      test('should handle concurrent operations safely', () async {
        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final channel = TestDataFactories.createChannel(id: 5);
        final createdChannel = await channelDao!.createChannel(channel, []);

        // Send multiple messages concurrently
        final futures = <Future>[];
        for (int i = 0; i < 5; i++) {
          final message = TestDataFactories.createChatMessage(
            text: "Concurrent message $i",
          );
          futures.add(chatDao!.sendMessage(message, createdChannel));
        }

        await Future.wait(futures);

        final messages = await chatDao!.getMessages(channel: createdChannel).get();
        expect(messages, hasLength(5));

        // Verify all messages have unique IDs
        final messageIds = messages.map((m) => m.id).toSet();
        expect(messageIds, hasLength(5));
      });
    });

    group('Error Handling and Edge Cases', () {
      test('should handle empty database gracefully', () async {
        final database = await TestDatabaseManager.createSafeTestDatabase(
          testName: "empty_test",
          userId: "empty_user",
        );

        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final chatDao = database.chatDao;
        final channelDao = database.channelDao;

        // Empty queries should return empty results, not throw
        final emptyChannels = await channelDao.getChannels().get();
        final emptyContacts = await channelDao.getContacts().get();
        final emptyPreviews = await chatDao.getChatPreviews().get();

        expect(emptyChannels, isEmpty);
        expect(emptyContacts, isEmpty);
        expect(emptyPreviews, isEmpty);
      });

      test('should handle invalid message operations gracefully', () async {
        final database = await TestDatabaseManager.createSafeTestDatabase(
          testName: "invalid_ops_test",
          userId: "invalid_user",
        );

        if (database == null) {
          markTestSkipped('SQLite not available - install libsqlite3-dev');
          return;
        }

        final chatDao = database.chatDao;

        // Try to update non-existent message
        final fakeMessage = TestDataFactories.createChatMessage();

        // This should not throw, but might not update anything
        await chatDao.updateMessage(99999, fakeMessage);

        // Try to delete non-existent message
        await chatDao.deleteMessage(99999);

        // These operations should complete without throwing
        expect(true, isTrue); // Test passes if no exceptions thrown
      });
    });
  });
}