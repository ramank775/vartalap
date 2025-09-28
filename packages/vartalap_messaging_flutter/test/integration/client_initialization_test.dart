import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/dao/dao.dart';

import '../mocks/mock_vartalap_chat_client.dart';
import '../factories/test_data_factories.dart';
import '../utils/database_test_utils.dart';

void main() {
  group('Local-First Database Integration Tests', () {
    late ChatDatabase database;
    late ChatDao chatDao;
    late ChannelDao channelDao;
    late MockVartalapChatClient mockChatClient;

    setUpAll(() {
      // Initialize Flutter binding for database operations
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      TestDataFactories.resetCounters();

      // Create mock client that bypasses server authentication
      mockChatClient = MockVartalapChatClient(
        mockUserId: QuickTestData.testUserId.toString(),
      );

      // Create in-memory database for testing local-first functionality
      database = DatabaseTestUtils.createInMemoryDatabase(
        userId: QuickTestData.testUserId.toString(),
      );
      await DatabaseTestUtils.verifyDatabaseConnectivity(database);
      chatDao = database.chatDao;
      channelDao = database.channelDao;
    });

    tearDown(() async {
      await database.close();
      mockChatClient.dispose();
    });

    group('Database Initialization', () {
      test('should initialize in-memory database successfully', () async {
        // Assert - Database should be properly initialized
        expect(database, isNotNull);
        expect(chatDao, isNotNull);
        expect(channelDao, isNotNull);

        // Verify database operations work
        final channels = await channelDao.getChannels().get();
        expect(channels, isEmpty); // No channels initially
      });

      test('should handle basic CRUD operations', () async {
        // Act - Test basic database operations
        final contacts = TestDataFactories.createContacts(3);
        await channelDao.syncContacts(contacts);

        // Assert - Contacts should be stored
        final storedContacts = await channelDao.getContacts().get();
        expect(storedContacts, hasLength(3));
      });

      test('should work without platform dependencies', () async {
        // This test ensures our in-memory database approach works
        // without requiring Flutter platform channels

        // Act - Perform various database operations
        final channel = TestDataFactories.createChannel();
        await channelDao.createChannel(channel, []);

        final message = TestDataFactories.createTextMessage();
        final messageId = await chatDao.sendMessage(message, channel);

        // Assert - All operations should work without platform dependencies
        expect(messageId, greaterThan(0));

        final messages = await chatDao.getMessages(channel: channel).get();
        expect(messages, hasLength(1));
      });
    });

    group('Local-First Operations', () {
      test('should create channel without server connectivity', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(
          extraData: {'name': 'Test Group'},
        );
        final members = TestDataFactories.createMembers(2);

        // First sync the contacts that the members reference
        final contacts = members.map((m) => m.user).toList();
        await channelDao.syncContacts(contacts);

        // Act - Create channel locally
        final createdChannel = await channelDao.createChannel(channel, members);

        // Assert
        expect(createdChannel.id, isNotNull);
        expect(createdChannel.displayName, equals('Test Group'));

        // Verify channel appears in channels list
        final channels = await channelDao.getChannels().get();
        expect(channels, hasLength(1));
        expect(channels.first.id, equals(createdChannel.id));
      });

      test('should sync contacts locally without server', () async {
        // Arrange
        final contacts = TestDataFactories.createContacts(5);

        // Act - Sync contacts locally
        await channelDao.syncContacts(contacts);

        // Assert - Contacts should be available locally
        final syncedContacts = await channelDao.getContacts().get();
        expect(syncedContacts, hasLength(5));
      });

      test('should handle multiple concurrent operations', () async {
        // Act - Perform multiple operations concurrently
        final futures = <Future>[];

        // Create multiple channels
        for (int i = 0; i < 3; i++) {
          final channel = TestDataFactories.createChannel(
            extraData: {'name': 'Channel $i'},
          );
          futures.add(channelDao.createChannel(channel, []));
        }

        // Sync contacts
        final contacts = TestDataFactories.createContacts(10);
        futures.add(channelDao.syncContacts(contacts));

        // Wait for all operations to complete
        await Future.wait(futures);

        // Assert - All operations should complete successfully
        final channels = await channelDao.getChannels().get();
        expect(channels, hasLength(3));

        final syncedContacts = await channelDao.getContacts().get();
        expect(syncedContacts, hasLength(10));
      });
    });

    group('Reactive Streams', () {
      test('should provide reactive channel updates', () async {
        // Act - Start watching channels
        final channelStream = channelDao.getChannels().watch();

        // Initially empty
        await expectLater(
          channelStream,
          emits(hasLength(0)),
        );

        // Create a channel
        final channel = TestDataFactories.createChannel();
        await channelDao.createChannel(channel, []);

        // Should emit updated list
        await expectLater(
          channelStream,
          emits(hasLength(1)),
        );
      });

      test('should provide reactive message updates', () async {
        // Arrange - Create a channel first
        final channel = TestDataFactories.createChannel();
        await channelDao.createChannel(channel, []);

        // Act - Start watching messages
        final messageStream = chatDao.getMessages(channel: channel).watch();

        // Initially empty
        await expectLater(
          messageStream,
          emits(hasLength(0)),
        );

        // Send a message
        final message = TestDataFactories.createTextMessage(
          text: "Hello, World!",
        );
        await chatDao.sendMessage(message, channel);

        // Should emit updated list
        await expectLater(
          messageStream,
          emits(hasLength(1)),
        );
      });
    });

    group('Message Operations', () {
      test('should send and store messages locally', () async {
        // Arrange
        final channel = TestDataFactories.createChannel();
        await channelDao.createChannel(channel, []);

        // Act - Send messages
        final message1 = TestDataFactories.createTextMessage(text: "Message 1");
        final message2 = TestDataFactories.createTextMessage(text: "Message 2");

        await chatDao.sendMessage(message1, channel);
        await chatDao.sendMessage(message2, channel);

        // Assert - Messages should be stored locally
        final storedMessages = await chatDao.getMessages(channel: channel).get();
        expect(storedMessages, hasLength(2));
        expect((storedMessages[0] as TextMessage).text, equals("Message 1"));
        expect((storedMessages[1] as TextMessage).text, equals("Message 2"));
      });

      test('should handle message state updates', () async {
        // Arrange
        final channel = TestDataFactories.createChannel();
        await channelDao.createChannel(channel, []);

        // Send initial message
        final originalMessage = TestDataFactories.createTextMessage(
          text: "Original message",
          state: MessageState.pending,
        );
        final messageId = await chatDao.sendMessage(originalMessage, channel);

        // Act - Update message state
        final updatedMessage = TestDataFactories.createTextMessage(
          text: "Updated message",
          state: MessageState.sent,
        );
        await chatDao.updateMessage(messageId, updatedMessage);

        // Assert - Message should be updated locally
        final messages = await chatDao.getMessages(channel: channel).get();
        expect(messages, hasLength(1));
        expect((messages.first as TextMessage).text, equals("Updated message"));
        expect(messages.first.state, equals(MessageState.sent));
      });
    });

    group('Performance Tests', () {
      test('should handle rapid database operations efficiently', () async {
        // Arrange
        const operationCount = 20;
        final stopwatch = Stopwatch()..start();

        // Act - Create multiple channels rapidly
        final futures = <Future>[];
        for (int i = 0; i < operationCount; i++) {
          final channel = TestDataFactories.createChannel(
            extraData: {'name': 'Channel $i'},
          );
          futures.add(channelDao.createChannel(channel, []));
        }
        await Future.wait(futures);

        stopwatch.stop();

        // Assert
        final channels = await channelDao.getChannels().get();
        expect(channels, hasLength(operationCount));

        // Performance assertion - should be very fast with in-memory database
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // 1 second max
      });
    });

    group('Error Handling', () {
      test('should gracefully handle invalid data', () async {
        // Act & Assert - Should not throw for channel with missing data
        final invalidChannel = TestDataFactories.createChannel(
          extraData: {}, // Missing name
        );

        // Should still create channel with default values
        final createdChannel = await channelDao.createChannel(invalidChannel, []);
        expect(createdChannel.id, isNotNull);
      });

      test('should handle database operations correctly', () async {
        // Act - Test basic database operations work correctly
        final channel = TestDataFactories.createChannel(id: 1);
        final createdChannel = await channelDao.createChannel(channel, []);

        // Assert - Channel should be created successfully
        expect(createdChannel.id, equals(1));

        final channels = await channelDao.getChannels().get();
        expect(channels, hasLength(1));
      });
    });
  });
}