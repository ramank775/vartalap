import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

import 'mocks/mock_vartalap_chat_client.dart';
import 'factories/test_data_factories.dart';

void main() {
  group('Simple Local-First Tests', () {
    test('MockVartalapChatClient should work without server', () async {
      // Arrange
      final mockClient = MockVartalapChatClient(mockUserId: "test_123");

      // Act - Test basic mock functionality
      final userId = await mockClient.getLoggedInUser();
      final profile = await mockClient.fetchProfile("test_123");

      // Assert
      expect(userId, equals("test_123"));
      expect(profile.userId, equals("test_123"));
      expect(profile.name, equals("Test User"));

      // Cleanup
      mockClient.dispose();
    });

    test('TestDataFactories should create consistent test data', () {
      // Arrange & Act
      TestDataFactories.resetCounters();

      final contact1 = TestDataFactories.createContact();
      final contact2 = TestDataFactories.createContact();
      final channel = TestDataFactories.createChannel();
      final message = TestDataFactories.createChatMessage();

      // Assert
      expect(contact1.id, equals(1));
      expect(contact2.id, equals(2));
      expect(contact1.name, contains("Test User"));
      expect(channel.displayName, contains("Test Channel"));
      expect(message.text, contains("Test message"));
    });

    test('VartalapChatClientFlutter should initialize with mock', () async {
      // Arrange
      final mockClient = MockVartalapChatClient(mockUserId: "test_123");
      final client = VartalapChatClientFlutter(
        apiKey: "test_api_key",
        client: mockClient,
      );

      // Act - This should work as it bypasses server authentication
      final userId = await client.client.getLoggedInUser();

      // Assert
      expect(userId, equals("test_123"));
      expect(client.client, isNotNull);

      // Cleanup
      mockClient.dispose();
    });

    test('Mock client should handle empty message sending', () async {
      // Arrange
      final mockClient = MockVartalapChatClient();

      // Act - Test that mock client can handle basic operations
      await mockClient.sendMessage([], ack: false);
      await mockClient.syncMessages();
      final contacts = await mockClient.syncContactBook(['contact1', 'contact2']);

      // Assert — returns map of phone→uid (in mock, uid == phone)
      expect(contacts, equals({'contact1': 'contact1', 'contact2': 'contact2'}));

      // Cleanup
      mockClient.dispose();
    });

    test('Test data should be self-consistent', () {
      // Arrange
      TestDataFactories.resetCounters();

      // Act - Create a complete dataset
      final dataset = TestDataFactories.createCompleteDataSet(
        contactCount: 3,
        channelCount: 2,
        messagesPerChannel: 5,
      );

      // Assert
      expect(dataset.contacts, hasLength(3));
      expect(dataset.channels, hasLength(2));
      expect(dataset.messages, hasLength(10)); // 2 channels * 5 messages
      expect(dataset.members, hasLength(6)); // 2 channels * 3 members

      // Verify relationships
      final channelIds = dataset.channels.map((c) => c.id).toSet();
      expect(channelIds, hasLength(2)); // Unique channel IDs

      final contactIds = dataset.contacts.map((c) => c.id).toSet();
      expect(contactIds, hasLength(3)); // Unique contact IDs
    });
  });
}