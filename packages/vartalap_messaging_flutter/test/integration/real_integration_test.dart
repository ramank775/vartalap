import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

import '../factories/test_data_factories.dart';

/// Integration tests that focus on real local-first behavior
/// WITHOUT over-mocking the core business logic
void main() {
  group('Real Integration Tests - Local-First Focus', () {

    setUpAll(() {
      // Initialize Flutter binding for any platform channel usage
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('VartalapChatClientFlutter constructor should work without server', () {
      // Test that we can create the client without any server dependencies
      // This tests the constructor and basic setup, not the full initialization

      final client = VartalapChatClientFlutter(
        apiKey: "test_api_key",
        apiBaseUrl: "http://localhost:3000", // Won't be called
        wsUrl: "ws://localhost:3000", // Won't be called
      );

      // Assert basic client properties are set
      expect(client.client, isNotNull);
    });

    test('Test data should integrate properly across components', () {
      // Test that our test data factories create properly integrated data
      // This validates our test setup without mocking business logic

      TestDataFactories.resetCounters();

      final dataset = TestDataFactories.createCompleteDataSet(
        contactCount: 3,
        channelCount: 2,
        messagesPerChannel: 4,
      );

      // Test cross-component relationships
      expect(dataset.contacts, hasLength(3));
      expect(dataset.channels, hasLength(2));
      expect(dataset.messages, hasLength(8)); // 2 channels * 4 messages
      expect(dataset.members, hasLength(6)); // 2 channels * 3 members each

      // Test that relationships are meaningful
      final channel1 = dataset.channels[0];
      final channel2 = dataset.channels[1];
      expect(channel1.id, isNot(equals(channel2.id)));

      // Test that messages have proper structure for database operations
      final messagesForChannel1 = dataset.messages.where((m) =>
        dataset.messages.indexOf(m) < 4 // First 4 messages belong to channel1
      ).toList();
      expect(messagesForChannel1, hasLength(4));

      // Verify messages have required fields for real operations
      for (final message in messagesForChannel1) {
        expect(message.id, isNotNull);
        expect(message.senderId, isNotNull);
        expect(message.text, isNotEmpty);
        expect(message.type, equals(MessageType.text));
        expect(message.timestamp, isNotNull);
      }
    });

    test('Message state transitions should follow business rules', () {
      // Test real state transition logic without mocking

      final message = TestDataFactories.createTextMessage(
        state: MessageState.pending,
        text: "Integration test message",
      );

      // Test forward transitions (should work)
      expect(message.updateState(MessageState.sent), isTrue);
      expect(message.state, equals(MessageState.sent));

      expect(message.updateState(MessageState.delivered), isTrue);
      expect(message.state, equals(MessageState.delivered));

      expect(message.updateState(MessageState.read), isTrue);
      expect(message.state, equals(MessageState.read));

      // Test backward transition (should not work)
      expect(message.updateState(MessageState.sent), isFalse);
      expect(message.state, equals(MessageState.read)); // Should remain read

      // Test invalid transition
      expect(message.updateState(MessageState.pending), isFalse);
      expect(message.state, equals(MessageState.read));
    });

    test('Channel display logic should handle different configurations', () {
      // Test real channel business logic across different scenarios

      final groupChannelWithName = TestDataFactories.createChannel(
        type: ChannelType.group,
        extraData: {'name': 'Family Group'},
      );

      final groupChannelWithoutName = TestDataFactories.createChannel(
        type: ChannelType.group,
        extraData: {}, // No name
      );

      final individualChannel = TestDataFactories.createChannel(
        type: ChannelType.individual,
        extraData: {'name': 'Should be ignored for individual'},
      );

      // Test real display name logic
      expect(groupChannelWithName.displayName, equals('Family Group'));
      expect(groupChannelWithoutName.displayName, isNotEmpty); // Should have fallback
      expect(individualChannel.type, equals(ChannelType.individual));
    });

    test('Contact model should handle various data scenarios', () {
      // Test real contact logic with different data combinations

      final contactWithAllData = TestDataFactories.createContact(
        name: "John Doe",
        username: "johndoe",
        phone: "+1234567890",
        photo: "https://example.com/photo.jpg",
        status: ContactStatus.active,
      );

      final contactWithMinimalData = TestDataFactories.createContact(
        name: null,
        username: "minimal",
        phone: "+9876543210",
        photo: null,
        status: ContactStatus.unknown,
      );

      // Test real display logic
      expect(contactWithAllData.displayName, equals("John Doe"));
      expect(contactWithAllData.hasAccount, isTrue);
      expect(contactWithAllData.status, equals(ContactStatus.active));

      // Minimal contact should still work
      expect(contactWithMinimalData.displayName, isNotEmpty); // Should fallback to phone or username
      expect(contactWithMinimalData.hasAccount, isTrue); // Has username
      expect(contactWithMinimalData.status, equals(ContactStatus.unknown));
    });

    test('Attachment handling should work with different file types', () {
      // Test real attachment logic without mocking file system

      final imageAttachment = TestDataFactories.createAttachment(
        name: "photo.jpg",
        type: "image",
        path: "/local/storage/photo.jpg",
      );

      final documentAttachment = TestDataFactories.createAttachment(
        name: "document.pdf",
        type: "document",
        path: "/local/storage/document.pdf",
      );

      final videoAttachment = TestDataFactories.createAttachment(
        name: "video.mp4",
        type: "video",
        path: "/local/storage/video.mp4",
      );

      // Test that all attachment types are handled correctly
      final attachments = [imageAttachment, documentAttachment, videoAttachment];

      for (final attachment in attachments) {
        expect(attachment.id, isNotNull);
        expect(attachment.name, isNotEmpty);
        expect(attachment.type, isNotEmpty);
        expect(attachment.path, startsWith("/local/"));
        expect(attachment.createdAt, isNotNull);
        expect(attachment.updatedAt, isNotNull);

        // Test temporal consistency
        expect(
          attachment.createdAt.isBefore(DateTime.now().add(Duration(seconds: 1))),
          isTrue,
        );
        expect(
          attachment.updatedAt.isAfter(attachment.createdAt.subtract(Duration(seconds: 1))),
          isTrue,
        );
      }
    });

    test('Member role and permission logic should be consistent', () {
      // Test real member business logic

      final adminMember = TestDataFactories.createMember(
        role: "admin",
        since: DateTime.now().subtract(Duration(days: 30)),
      );

      final moderatorMember = TestDataFactories.createMember(
        role: "moderator",
        since: DateTime.now().subtract(Duration(days: 15)),
      );

      final regularMember = TestDataFactories.createMember(
        role: "member",
        since: DateTime.now().subtract(Duration(days: 5)),
      );

      final members = [adminMember, moderatorMember, regularMember];

      // Test member properties
      for (final member in members) {
        expect(member.user, isNotNull);
        expect(member.role, isNotEmpty);
        expect(member.since, isNotNull);
        expect(member.since.isBefore(DateTime.now()), isTrue);
      }

      // Test role hierarchy by join date (admins typically join first)
      expect(adminMember.since.isBefore(moderatorMember.since), isTrue);
      expect(moderatorMember.since.isBefore(regularMember.since), isTrue);

      // Test that different members have different users
      final userIds = members.map((m) => m.user.id).toSet();
      expect(userIds, hasLength(3)); // All unique users
    });

    test('Error handling should be robust without external dependencies', () {
      // Test error scenarios that don't require external systems

      // Test with invalid message state
      final message = TestDataFactories.createTextMessage(state: MessageState.read);

      // Try invalid state transitions
      expect(message.updateState(MessageState.pending), isFalse);
      expect(message.updateState(MessageState.sent), isFalse);
      expect(message.updateState(MessageState.delivered), isFalse);

      // State should remain unchanged
      expect(message.state, equals(MessageState.read));

      // Test empty/null data handling
      final emptyChannel = TestDataFactories.createChannel(
        extraData: {},
      );

      // Should handle empty data gracefully
      expect(emptyChannel.displayName, isNotEmpty); // Should have fallback
      expect(emptyChannel.type, isNotNull);
      expect(emptyChannel.extraData, isNotNull);
    });
  });
}