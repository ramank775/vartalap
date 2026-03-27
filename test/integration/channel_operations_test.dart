import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_testing/vartalap_testing.dart';

/// E2E tests for channel operations: create, pin, archive, delete, clear chat.
void main() {
  late MockVartalapChatClient mockClient;
  late VartalapChatClientFlutter client;

  setUp(() async {
    mockClient = MockVartalapChatClient(
      mockUserId: 'uid_me',
      tokenManager: MockTokenManager(),
      initialScenario: ManualTakeoverScenario(),
    );

    client = VartalapChatClientFlutter(
      apiKey: 'test',
      client: mockClient,
      inMemory: true,
    );

    await client.login(
        messaging.Credential(username: 'uid_me', externalAuthToken: 'token')
          ..deviceId = 'dev');
    await client.init();

    // Seed contacts
    await client.db.into(client.db.contacts).insert(
        ContactsCompanion.insert(
            id: const Value(1),
            uid: const Value('uid_me'),
            username: const Value('me'),
            status: ContactStatus.active));
    await client.db.into(client.db.contacts).insert(
        ContactsCompanion.insert(
            id: const Value(2),
            uid: const Value('uid_alice'),
            username: const Value('alice'),
            status: ContactStatus.active));
  });

  tearDown(() {
    client.dispose();
  });

  group('Channel Create', () {
    test('creating a group channel persists it locally with members',
        () async {
      final members = [
        Member(
          user: const Contact(
              id: 1,
              uid: 'uid_me',
              username: 'me',
              status: ContactStatus.active),
          role: 'admin',
          since: DateTime.now(),
        ),
        Member(
          user: const Contact(
              id: 2,
              uid: 'uid_alice',
              username: 'alice',
              status: ContactStatus.active),
          role: 'member',
          since: DateTime.now(),
        ),
      ];

      final channelModel = ChannelModel(
        id: 0,
        type: messaging.ChannelType.group,
        extraData: {'name': 'Test Group'},
        config: {},
        muted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final created = await client.createChannel(channelModel, members);

      final channels = await client.db.channelDao.getChannels().get();
      expect(channels.any((c) => c.id == created.id), isTrue);
      expect(created.displayName, 'Test Group');
    });
  });

  group('Channel Pin', () {
    test('pinning a channel updates its config', () async {
      final channelEntity = await client.db
          .into(client.db.channels)
          .insertReturning(ChannelsCompanion.insert(
              type: messaging.ChannelType.individual,
              cid: const Value('uid_alice'),
              config: const Value({})));

      await client.setChannelPinned(channelEntity.id, true);

      final updated = await (client.db.select(client.db.channels)
            ..where((tbl) => tbl.id.equals(channelEntity.id)))
          .getSingle();
      expect(updated.isPinned, isTrue);
    });

    test('unpinning a channel clears the pin flag', () async {
      final channelEntity = await client.db
          .into(client.db.channels)
          .insertReturning(ChannelsCompanion.insert(
              type: messaging.ChannelType.individual,
              cid: const Value('uid_alice'),
              config: const Value({'pinned': true})));

      await client.setChannelPinned(channelEntity.id, false);

      final updated = await (client.db.select(client.db.channels)
            ..where((tbl) => tbl.id.equals(channelEntity.id)))
          .getSingle();
      expect(updated.isPinned, isFalse);
    });
  });

  group('Channel Archive', () {
    test('archiving a channel updates its config', () async {
      final channelEntity = await client.db
          .into(client.db.channels)
          .insertReturning(ChannelsCompanion.insert(
              type: messaging.ChannelType.individual,
              cid: const Value('uid_alice'),
              config: const Value({})));

      await client.setChannelArchived(channelEntity.id, true);

      final updated = await (client.db.select(client.db.channels)
            ..where((tbl) => tbl.id.equals(channelEntity.id)))
          .getSingle();
      expect(updated.isArchived, isTrue);
    });
  });

  group('Channel Delete', () {
    test('deleting a channel removes it from the DB', () async {
      final channelEntity = await client.db
          .into(client.db.channels)
          .insertReturning(ChannelsCompanion.insert(
              type: messaging.ChannelType.individual,
              cid: const Value('uid_alice'),
              config: const Value({})));

      await client.deleteChannel(channelEntity.id);

      final channels = await client.db.channelDao.getChannels().get();
      expect(channels.any((c) => c.id == channelEntity.id), isFalse);
    });
  });

  group('Clear Chat', () {
    test('clearing chat removes all messages but keeps the channel', () async {
      final channelEntity = await client.db
          .into(client.db.channels)
          .insertReturning(ChannelsCompanion.insert(
              type: messaging.ChannelType.individual,
              cid: const Value('uid_alice'),
              config: const Value({})));

      // Add some messages
      for (var i = 0; i < 3; i++) {
        await client.db.into(client.db.messages).insert(
            MessagesCompanion.insert(
                type: MessageType.text,
                state: MessageState.delivered,
                payload: {'text': 'Message $i'},
                channelId: channelEntity.id,
                senderId: 1));
      }

      var messages = await client.db.chatDao
          .getMessages(channel: channelEntity)
          .get();
      expect(messages, hasLength(3));

      await client.clearChat(channelEntity.id);

      messages = await client.db.chatDao
          .getMessages(channel: channelEntity)
          .get();
      expect(messages, isEmpty);

      // Channel should still exist
      final ch = await (client.db.select(client.db.channels)
            ..where((tbl) => tbl.id.equals(channelEntity.id)))
          .getSingleOrNull();
      expect(ch, isNotNull);
    });
  });
}
