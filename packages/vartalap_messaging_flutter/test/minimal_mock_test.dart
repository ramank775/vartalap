import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

import 'factories/test_data_factories.dart';

/// Tests using minimal strategic mocking - only mock external dependencies
/// Test REAL business logic and local-first behavior
void main() {
  group('Minimal Strategic Mocking Tests', () {

    test('Test data factories should create realistic data', () {
      // Test the data generation without any mocking
      TestDataFactories.resetCounters();

      final contact = TestDataFactories.createContact(
        name: "John Doe",
        phone: "+1234567890",
      );

      final channel = TestDataFactories.createChannel(
        extraData: {'name': 'Family Chat'},
      );

      final message = TestDataFactories.createChatMessage(
        text: "Hello family!",
        senderId: contact.id,
      );

      // Assert realistic data structure
      expect(contact.displayName, equals("John Doe"));
      expect(contact.phone, equals("+1234567890"));
      expect(contact.hasAccount, isTrue); // Has username

      expect(channel.displayName, equals('Family Chat'));
      expect(channel.type, equals(ChannelType.group));

      expect(message.text, equals("Hello family!"));
      expect(message.senderId, equals(contact.id));
      expect(message.type, equals(MessageType.text));
    });

    test('Contact model should handle real-world data correctly', () {
      // Test real model behavior without mocking
      final contactWithImage = TestDataFactories.createContact(
        name: "Alice Smith",
        photo: "https://example.com/avatar.jpg",
      );

      final contactWithoutImage = TestDataFactories.createContact(
        name: "Bob Johnson",
        photo: null,
      );

      // Test real getter logic
      expect(contactWithImage.displayName, equals("Alice Smith"));
      expect(contactWithoutImage.displayName, equals("Bob Johnson"));

      // Test display image logic (this is real business logic)
      expect(contactWithImage.displayImage, isNotNull);
      expect(contactWithoutImage.displayImage, isNotNull); // Should fallback
    });

    test('Message model should handle state transitions correctly', () {
      // Test real message state logic
      final message = TestDataFactories.createChatMessage(
        state: MessageState.pending,
      );

      // Test real state update logic
      bool canUpdateToSent = message.updateState(MessageState.sent);
      expect(canUpdateToSent, isTrue);
      expect(message.state, equals(MessageState.sent));

      bool canUpdateToDelivered = message.updateState(MessageState.delivered);
      expect(canUpdateToDelivered, isTrue);
      expect(message.state, equals(MessageState.delivered));

      bool canUpdateToRead = message.updateState(MessageState.read);
      expect(canUpdateToRead, isTrue);
      expect(message.state, equals(MessageState.read));

      // Test that we can't go backwards in state
      bool canGoBackToPending = message.updateState(MessageState.pending);
      expect(canGoBackToPending, isFalse);
      expect(message.state, equals(MessageState.read)); // Should remain read
    });

    test('Channel model should handle member display correctly', () {
      // Test real channel business logic
      final individualChannel = TestDataFactories.createChannel(
        type: ChannelType.individual,
        extraData: {}, // No explicit name
      );

      final groupChannel = TestDataFactories.createChannel(
        type: ChannelType.group,
        extraData: {'name': 'Team Chat'},
      );

      // Test real display name logic
      expect(groupChannel.displayName, equals('Team Chat'));

      // Individual channels should handle member-based naming
      // (This would need members to be fully tested)
      expect(individualChannel.type, equals(ChannelType.individual));
    });

    test('Attachment model should handle file operations', () {
      // Test real attachment logic without mocking file system
      final imageAttachment = TestDataFactories.createAttachment(
        name: "vacation.jpg",
        type: "image",
        path: "/local/path/vacation.jpg",
      );

      final documentAttachment = TestDataFactories.createAttachment(
        name: "report.pdf",
        type: "document",
        path: "/local/path/report.pdf",
      );

      // Test real properties
      expect(imageAttachment.name, equals("vacation.jpg"));
      expect(imageAttachment.type, equals("image"));
      expect(imageAttachment.path, startsWith("/local/path"));

      expect(documentAttachment.name, equals("report.pdf"));
      expect(documentAttachment.type, equals("document"));

      // Test that creation timestamps are reasonable
      expect(imageAttachment.createdAt, isNotNull);
      expect(imageAttachment.updatedAt, isNotNull);
      expect(
        imageAttachment.createdAt.isBefore(DateTime.now().add(Duration(seconds: 1))),
        isTrue,
      );
    });

    test('Member model should handle role and permissions', () {
      // Test real member business logic
      final adminMember = TestDataFactories.createMember(
        role: "admin",
        since: DateTime.now().subtract(Duration(days: 30)),
      );

      final regularMember = TestDataFactories.createMember(
        role: "member",
        since: DateTime.now().subtract(Duration(days: 5)),
      );

      // Test real member properties
      expect(adminMember.role, equals("admin"));
      expect(regularMember.role, equals("member"));

      // Test temporal logic
      expect(adminMember.since.isBefore(regularMember.since), isTrue);
      expect(adminMember.user, isNotNull);
      expect(regularMember.user, isNotNull);
    });

    test('Dataset consistency should be maintained across operations', () {
      // Test real data relationships without mocking
      TestDataFactories.resetCounters();

      final dataset = TestDataFactories.createCompleteDataSet(
        contactCount: 5,
        channelCount: 2,
        messagesPerChannel: 3,
      );

      // Test real relationships
      expect(dataset.contacts, hasLength(5));
      expect(dataset.channels, hasLength(2));
      expect(dataset.messages, hasLength(6)); // 2 * 3

      // Test that IDs are unique and consistent
      final contactIds = dataset.contacts.map((c) => c.id).toSet();
      expect(contactIds, hasLength(5)); // All unique

      final channelIds = dataset.channels.map((c) => c.id).toSet();
      expect(channelIds, hasLength(2)); // All unique

      // Test helper methods work correctly
      final firstTwoContacts = dataset.getContactsByIds([1, 2]);
      expect(firstTwoContacts, hasLength(2));
      expect(firstTwoContacts.first.id, equals(1));
      expect(firstTwoContacts.last.id, equals(2));

      // Test channel member relationships
      final channel1Members = dataset.getMembersForChannel(1);
      expect(channel1Members, isNotEmpty);
    });
  });
}