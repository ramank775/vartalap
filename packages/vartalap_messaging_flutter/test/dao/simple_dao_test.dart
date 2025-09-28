import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';

import '../utils/test_database_helper.dart';
import '../factories/test_data_factories.dart';

void main() {
  group('Simple DAO Tests - Local-First Functionality', () {
    late ChatDatabase database;

    setUpAll(() {
      TestDatabaseHelper.setupTestEnvironment();
    });

    setUp(() async {
      TestDataFactories.resetCounters();
      database = await TestDatabaseHelper.createAndSetupDatabase();
    });

    tearDown(() async {
      await database.close();
    });

    test('should create and verify database DAOs', () async {
      // Arrange & Act
      final chatDao = database.chatDao;
      final channelDao = database.channelDao;

      // Assert
      expect(chatDao, isNotNull);
      expect(channelDao, isNotNull);
    });

    test('should handle empty queries gracefully', () async {
      // Arrange
      final channelDao = database.channelDao;
      final chatDao = database.chatDao;

      // Act - Query empty database
      final channels = await channelDao.getChannels().get();
      final contacts = await channelDao.getContacts().get();
      final chatPreviews = await chatDao.getChatPreviews().get();

      // Assert - Should return empty lists, not throw errors
      expect(channels, isEmpty);
      expect(contacts, isEmpty);
      expect(chatPreviews, isEmpty);
    });

    test('should create test data without database operations', () {
      // Arrange & Act
      final channel = TestDataFactories.createChannel();
      final contact = TestDataFactories.createContact();
      final message = TestDataFactories.createTextMessage();
      final member = TestDataFactories.createMember();

      // Assert - Data should be created correctly
      expect(channel.id, isNotNull);
      expect(channel.displayName, isNotEmpty);
      expect(contact.id, isNotNull);
      expect(contact.displayName, isNotEmpty);
      expect(message.text, isNotEmpty);
      expect(member.user, isNotNull);
    });

    test('should handle test data factories consistently', () {
      // Arrange
      TestDataFactories.resetCounters();

      // Act - Create multiple items
      final channels = TestDataFactories.createChannels(3);
      final contacts = TestDataFactories.createContacts(5);

      // Assert - Should have incremental IDs
      expect(channels, hasLength(3));
      expect(contacts, hasLength(5));

      expect(channels[0].id, equals(1));
      expect(channels[1].id, equals(2));
      expect(channels[2].id, equals(3));

      expect(contacts[0].id, equals(1));
      expect(contacts[1].id, equals(2));
      expect(contacts[4].id, equals(5));
    });

    test('should demonstrate local-first architecture readiness', () async {
      // Arrange
      final database = TestDatabaseHelper.createTestDatabase(userId: "demo_user");

      // Act - Verify components are properly initialized
      await TestDatabaseHelper.verifyBasicFunctionality(database);

      // Assert - All components should be accessible
      expect(database.userId, equals("demo_user"));
      expect(database.channelDao, isNotNull);
      expect(database.chatDao, isNotNull);

      // Cleanup
      await database.close();
    });
  });
}