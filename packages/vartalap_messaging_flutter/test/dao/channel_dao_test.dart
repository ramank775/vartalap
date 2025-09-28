import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/dao/dao.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';

import '../utils/database_test_utils.dart';
import '../factories/test_data_factories.dart';

void main() {
  group('ChannelDao Tests - Local-First Functionality', () {
    late ChatDatabase database;
    late ChannelDao channelDao;

    setUpAll(() {
      // Initialize Flutter binding for platform channels and database operations
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      TestDataFactories.resetCounters();
      database = DatabaseTestUtils.createInMemoryDatabase(userId: "test_user");
      await DatabaseTestUtils.verifyDatabaseConnectivity(database);
      channelDao = database.channelDao;
    });

    tearDown(() async {
      await database.close();
    });

    group('Channel Operations', () {
      test('should create channel locally', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(id: 1);
        final members = TestDataFactories.createMembers(2);

        // Act
        final createdChannel = await channelDao.createChannel(channel, members);

        // Assert
        expect(createdChannel.id, equals(channel.id));
        expect(createdChannel.displayName, equals(channel.displayName));

        // Verify channel exists in database
        final channels = await channelDao.getChannels().get();
        expect(channels, hasLength(1));
        expect(channels.first.id, equals(channel.id));
      });

      test('should retrieve channels reactively', () async {
        // Arrange
        final channels = TestDataFactories.createChannels(3);

        // Act - Create channels
        for (final channel in channels) {
          await channelDao.createChannel(channel, []);
        }

        // Assert - Test reactive query
        final stream = channelDao.getChannels().watch();
        
        await expectLater(
          stream,
          emits(hasLength(3)),
        );

        // Add another channel and verify stream updates
        final newChannel = TestDataFactories.createChannel();
        await channelDao.createChannel(newChannel, []);

        await expectLater(
          stream,
          emits(hasLength(4)),
        );
      });

      test('should update channel information', () async {
        // Arrange
        final channel = TestDataFactories.createChannel(
          id: 1,
          extraData: {'name': 'Original Name'},
        );
        await channelDao.createChannel(channel, []);

        // Act - Update channel
        final updatedChannel = TestDataFactories.createChannel(
          id: 1,
          extraData: {'name': 'Updated Name'},
        );
        await channelDao.updateChannel(updatedChannel);

        // Assert
        final channels = await channelDao.getChannels().get();
        expect(channels, hasLength(1));
        expect(channels.first.displayName, equals('Updated Name'));
      });

      test('should filter channels by type', () async {
        // Arrange - Create channels of different types
        final groupChannel = TestDataFactories.createChannel(
          id: 1,
          type: ChannelType.group,
        );
        final individualChannel = TestDataFactories.createChannel(
          id: 2,
          type: ChannelType.individual,
        );

        await channelDao.createChannel(groupChannel, []);
        await channelDao.createChannel(individualChannel, []);

        // Act - Filter by group type
        final groupChannels = await channelDao.getChannels(
          filter: ChannelFilter(type: ChannelType.group),
        ).get();

        // Assert
        expect(groupChannels, hasLength(1));
        expect(groupChannels.first.type, equals(ChannelType.group));
      });
    });

    group('Contact Operations', () {
      test('should sync contacts locally', () async {
        // Arrange
        final contacts = TestDataFactories.createContacts(5);

        // Act
        await channelDao.syncContacts(contacts);

        // Assert
        final syncedContacts = await channelDao.getContacts().get();
        expect(syncedContacts, hasLength(5));
      });

      test('should update existing contacts during sync', () async {
        // Arrange
        final originalContact = TestDataFactories.createContact(
          id: 1,
          name: "Original Name",
        );
        await channelDao.syncContacts([originalContact]);

        // Act - Sync with updated contact
        final updatedContact = TestDataFactories.createContact(
          id: 1,
          name: "Updated Name",
        );
        await channelDao.syncContacts([updatedContact]);

        // Assert
        final contacts = await channelDao.getContacts().get();
        expect(contacts, hasLength(1));
        expect(contacts.first.name, equals("Updated Name"));
      });

      test('should filter contacts by status', () async {
        // Arrange
        final activeContact = TestDataFactories.createContact(
          status: ContactStatus.active,
        );
        final deletedContact = TestDataFactories.createContact(
          status: ContactStatus.deleted,
        );

        await channelDao.syncContacts([activeContact, deletedContact]);

        // Act - Filter by active status
        final activeContacts = await channelDao.getContacts(
          filter: ContactFilter(status: ContactStatus.active),
        ).get();

        // Assert
        expect(activeContacts, hasLength(1));
        expect(activeContacts.first.status, equals(ContactStatus.active));
      });
    });

    group('Performance Tests', () {
      test('should handle large number of channels efficiently', () async {
        // Arrange
        const channelCount = 50;
        final stopwatch = Stopwatch()..start();

        // Act - Create many channels
        for (int i = 0; i < channelCount; i++) {
          final channel = TestDataFactories.createChannel(id: i + 1);
          await channelDao.createChannel(channel, []);
        }

        stopwatch.stop();

        // Assert
        final channels = await channelDao.getChannels().get();
        expect(channels, hasLength(channelCount));
        
        // Performance assertion
        expect(stopwatch.elapsedMilliseconds, lessThan(2000)); // 2 seconds max
      });

      test('should efficiently batch sync contacts', () async {
        // Arrange
        const contactCount = 100;
        final contacts = List.generate(
          contactCount,
          (i) => TestDataFactories.createContact(id: i + 1),
        );

        final stopwatch = Stopwatch()..start();

        // Act - Batch sync contacts
        await channelDao.syncContacts(contacts);

        stopwatch.stop();

        // Assert
        final syncedContacts = await channelDao.getContacts().get();
        expect(syncedContacts, hasLength(contactCount));
        
        // Performance assertion
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // 1 second max
      });
    });
  });
}