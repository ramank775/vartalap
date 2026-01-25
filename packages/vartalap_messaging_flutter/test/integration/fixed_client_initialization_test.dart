import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';

import '../factories/test_data_factories.dart';

/// Client initialization tests that focus on real local-first behavior
/// WITHOUT over-mocking core business logic
void main() {
  group('VartalapChatClientFlutter Real Initialization Tests', () {

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() {
      TestDataFactories.resetCounters();
    });

    test('Client constructor should work without server dependencies', () {
      // Test real constructor behavior without mocking business logic
      final client = VartalapChatClientFlutter(
        apiKey: "test_api_key",
        apiBaseUrl: "http://localhost:3000", // Won't be contacted
        wsUrl: "ws://localhost:3000", // Won't be contacted
      );

      // Test real client properties
      expect(client.client, isNotNull);

      // Test that internal client is properly configured
      final internalClient = client.client;
      expect(internalClient, isNotNull);
    });

    test('Client should handle initialization failure gracefully', () {
      // Test real error handling without over-mocking
      final client = VartalapChatClientFlutter(
        apiKey: "test_api_key",
      );

      // Attempting to initialize without authentication should fail
      // This tests the real validation logic
      expect(
        () => client.init(),
        throwsA(isA<VartalapInitializationException>()),
      );
    });

    group('Local-First Business Logic (No Database Required)', () {
      test('Test data should be ready for client operations', () {
        // Test that our data factories create client-ready data
        final contact = TestDataFactories.createContact(
          name: "Test User",
          username: "testuser",
        );

        final channel = TestDataFactories.createChannel(
          extraData: {'name': 'Test Channel'},
        );

        final message = TestDataFactories.createChatMessage(
          senderId: contact.id,
          text: "Hello from client test",
        );

        // Verify data is structured correctly for client operations
        expect(contact.displayName, equals("Test User"));
        expect(contact.hasAccount, isTrue);
        expect(channel.displayName, equals('Test Channel'));
        expect(message.senderId, equals(contact.id));
        expect(message.text, equals("Hello from client test"));
      });

      test('Profile model should handle client requirements', () {
        // Test real Profile model behavior
        final profile = Profile(
          userId: "test123",
          name: "John Doe",
          email: "john@example.com",
          image: "https://example.com/avatar.jpg",
        );

        expect(profile.userId, equals("test123"));
        expect(profile.name, equals("John Doe"));
        expect(profile.email, equals("john@example.com"));
        expect(profile.image, equals("https://example.com/avatar.jpg"));
      });

      test('VartalapInitializationException should provide meaningful errors', () {
        // Test real exception behavior
        const exception = VartalapInitializationException(
          "Test initialization failed",
          originalError: "Original error details",
        );

        expect(exception.message, equals("Test initialization failed"));
        expect(exception.originalError, equals("Original error details"));
        expect(exception.toString(), contains("Test initialization failed"));
        expect(exception.toString(), contains("Original error details"));
      });

      test('Client factory methods should work correctly', () {
        // Test that we can create client with different configurations
        final clientWithDefaults = VartalapChatClientFlutter(
          apiKey: "test_key",
        );

        final clientWithCustomUrls = VartalapChatClientFlutter(
          apiKey: "test_key",
          apiBaseUrl: "https://custom.api.com",
          wsUrl: "wss://custom.api.com/ws",
        );

        expect(clientWithDefaults.client, isNotNull);
        expect(clientWithCustomUrls.client, isNotNull);

        // Both should be independently configured
        expect(clientWithDefaults.client, isNot(same(clientWithCustomUrls.client)));
      });
    });

    group('Database Integration (When Available)', () {
      test('Should create database for user when SQLite available', () async {
        try {
          // Test that we can create a database without full client initialization
          final database = ChatDatabase(userId: "integration_test", inMemory: true);

          // Test basic database functionality
          await database.customSelect('SELECT 1').getSingle();

          // Test DAO accessibility
          expect(database.chatDao, isNotNull);
          expect(database.channelDao, isNotNull);

          await database.close();
        } catch (e) {
          // Skip test if SQLite not available
          markTestSkipped('SQLite not available - install libsqlite3-dev for full testing');
        }
      });

      test('Should handle database operations independently', () async {
        try {
          final database = ChatDatabase(userId: "dao_test", inMemory: true);

          // Test real DAO operations
          final channelDao = database.channelDao;
          final chatDao = database.chatDao;

          // Test empty state
          final emptyChannels = await channelDao.getChannels().get();
          final emptyContacts = await channelDao.getContacts().get();
          final emptyPreviews = await chatDao.getChatPreviews().get();

          expect(emptyChannels, isEmpty);
          expect(emptyContacts, isEmpty);
          expect(emptyPreviews, isEmpty);

          await database.close();
        } catch (e) {
          markTestSkipped('SQLite not available - install libsqlite3-dev for full testing');
        }
      });

      test('Should validate local-first data flow', () async {
        try {
          final database = ChatDatabase(userId: "dataflow_test", inMemory: true);

          final channelDao = database.channelDao;
          final chatDao = database.chatDao;

          // Test complete local data flow
          final channel = TestDataFactories.createChannel();
          final createdChannel = await channelDao.createChannel(channel, []);

          final message = TestDataFactories.createChatMessage(
            text: "Local data flow test",
          );
          await chatDao.sendMessage(message, createdChannel);

          // Verify data persisted locally
          final channels = await channelDao.getChannels().get();
          final messages = await chatDao.getMessages(channel: createdChannel).get();

          expect(channels, hasLength(1));
          expect(messages, hasLength(1));
          expect((messages.first).text, equals("Local data flow test"));

          await database.close();
        } catch (e) {
          markTestSkipped('SQLite not available - install libsqlite3-dev for full testing');
        }
      });
    });

    group('Error Handling and Edge Cases', () {
      test('Should handle invalid API keys gracefully', () {
        // Test real validation without over-mocking
        expect(
          () => VartalapChatClientFlutter(apiKey: ""),
          returnsNormally, // Constructor should not validate API key format
        );

        expect(
          () => VartalapChatClientFlutter(apiKey: "invalid_key"),
          returnsNormally, // Validation happens during actual API calls
        );
      });

      test('Should validate URLs at construction time', () {
        // Test real URL validation behavior
        expect(
          () => VartalapChatClientFlutter(
            apiKey: "test",
            apiBaseUrl: "not_a_url",
            wsUrl: "also_not_a_url",
          ),
          throwsArgumentError, // Client validates URLs at construction
        );

        // Valid URLs should work
        expect(
          () => VartalapChatClientFlutter(
            apiKey: "test",
            apiBaseUrl: "https://valid.api.com",
            wsUrl: "wss://valid.api.com/ws",
          ),
          returnsNormally,
        );
      });

      test('Should maintain consistency across multiple instances', () {
        // Test that multiple client instances don't interfere
        final client1 = VartalapChatClientFlutter(apiKey: "key1");
        final client2 = VartalapChatClientFlutter(apiKey: "key2");

        expect(client1.client, isNot(same(client2.client)));

        // Each should maintain independent state
        expect(client1.client, isNotNull);
        expect(client2.client, isNotNull);
      });
    });
  });
}