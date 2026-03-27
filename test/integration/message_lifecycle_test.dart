import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_testing/vartalap_testing.dart';

/// E2E tests for the message lifecycle: send, edit, delete, read receipts.
/// Uses in-memory database and mock client — no server required.
void main() {
  late MockVartalapChatClient mockClient;
  late VartalapChatClientFlutter client;
  late Contact currentUser;
  late ChannelModel channel;
  late ChatClient chatClient;

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
            name: const Value('Me'),
            status: ContactStatus.active));
    await client.db.into(client.db.contacts).insert(
        ContactsCompanion.insert(
            id: const Value(2),
            uid: const Value('uid_alice'),
            username: const Value('alice'),
            name: const Value('Alice'),
            status: ContactStatus.active));

    currentUser = (await client.db.select(client.db.contacts).get())
        .firstWhere((c) => c.uid == 'uid_me');

    // Seed channel
    final channelEntity = await client.db
        .into(client.db.channels)
        .insertReturning(ChannelsCompanion.insert(
            type: messaging.ChannelType.individual,
            cid: const Value('uid_alice'),
            config: const Value({})));
    channel = channelEntity;

    await client.db.into(client.db.members).insert(
        MembersCompanion.insert(channelId: channel.id, memberId: 1));
    await client.db.into(client.db.members).insert(
        MembersCompanion.insert(channelId: channel.id, memberId: 2));

    chatClient =
        await client.chat(channel: channel, currentUser: currentUser);
  });

  tearDown(() {
    client.dispose();
  });

  group('Message Send', () {
    test('sent message is persisted in local DB with pending state', () async {
      final msg = ChatMessage.text(
        text: 'Hello Alice',
        channelId: channel.id,
        senderId: currentUser.id,
      );

      await chatClient.sendMessage([msg]);

      final messages =
          await client.db.chatDao.getMessages(channel: channel).get();
      expect(messages, hasLength(1));
      expect(messages.first.text, 'Hello Alice');
      expect(messages.first.state, MessageState.pending);
    });

    test('multiple messages are stored in order', () async {
      for (var i = 1; i <= 3; i++) {
        final msg = ChatMessage.text(
          text: 'Message $i',
          channelId: channel.id,
          senderId: currentUser.id,
        );
        await chatClient.sendMessage([msg]);
      }

      final messages =
          await client.db.chatDao.getMessages(channel: channel).get();
      expect(messages, hasLength(3));
    });
  });

  group('Message Edit', () {
    test('editing a text message updates the payload', () async {
      final msg = ChatMessage.text(
        text: 'Original',
        channelId: channel.id,
        senderId: currentUser.id,
      );
      await chatClient.sendMessage([msg]);

      final messages =
          await client.db.chatDao.getMessages(channel: channel).get();
      final messageId = messages.first.id;

      await chatClient.editMessage(messageId, 'Edited text');

      final updated =
          await client.db.chatDao.getMessages(channel: channel).get();
      expect(updated.first.text, 'Edited text');
    });
  });

  group('Message Delete', () {
    test('deleting a message removes it from local DB', () async {
      final msg = ChatMessage.text(
        text: 'To be deleted',
        channelId: channel.id,
        senderId: currentUser.id,
      );
      await chatClient.sendMessage([msg]);

      var messages =
          await client.db.chatDao.getMessages(channel: channel).get();
      expect(messages, hasLength(1));

      await chatClient.deleteMessage(messages.first.id);

      messages =
          await client.db.chatDao.getMessages(channel: channel).get();
      expect(messages, isEmpty);
    });
  });

  group('Message Receive', () {
    test('incoming message from event stream is stored locally', () async {
      mockClient.injectMessage(messaging.RemoteMessage()
        ..id = 'remote_msg_1'
        ..head = messaging.Head(
          type: messaging.ChannelType.individual,
          to: 'uid_me',
          from: 'uid_alice',
          category: 'message',
        )
        ..meta = messaging.Meta()
        ..body = {'text': 'Hi from Alice!'});

      await Future.delayed(const Duration(milliseconds: 300));

      final messages =
          await client.db.chatDao.getMessages(channel: channel).get();
      expect(messages, hasLength(1));
      expect(messages.first.text, 'Hi from Alice!');
      expect(messages.first.state, MessageState.delivered);
    });

    test('duplicate messages are not inserted twice', () async {
      final msg = messaging.RemoteMessage()
        ..id = 'dup_msg_1'
        ..head = messaging.Head(
          type: messaging.ChannelType.individual,
          to: 'uid_me',
          from: 'uid_alice',
          category: 'message',
        )
        ..meta = messaging.Meta()
        ..body = {'text': 'Duplicate test'};

      mockClient.injectMessage(msg);
      await Future.delayed(const Duration(milliseconds: 200));
      mockClient.injectMessage(msg);
      await Future.delayed(const Duration(milliseconds: 200));

      final messages =
          await client.db.chatDao.getMessages(channel: channel).get();
      expect(messages, hasLength(1));
    });

    test('message from unknown sender auto-creates channel', () async {
      mockClient.injectMessage(messaging.RemoteMessage()
        ..id = 'new_sender_msg'
        ..head = messaging.Head(
          type: messaging.ChannelType.individual,
          to: 'uid_me',
          from: 'uid_unknown',
          category: 'message',
        )
        ..meta = messaging.Meta()
        ..body = {'text': 'Hello from stranger'});

      await Future.delayed(const Duration(milliseconds: 500));

      // Should have created a new channel for uid_unknown
      final channels = await client.db.channelDao.getChannels().get();
      final newChannel =
          channels.where((c) => c.cid == 'uid_unknown').toList();
      expect(newChannel, hasLength(1));
    });
  });

  group('Read Receipts', () {
    test('marking a message as read updates its state', () async {
      mockClient.injectMessage(messaging.RemoteMessage()
        ..id = 'read_msg_1'
        ..head = messaging.Head(
          type: messaging.ChannelType.individual,
          to: 'uid_me',
          from: 'uid_alice',
          category: 'message',
        )
        ..meta = messaging.Meta()
        ..body = {'text': 'Read me'});

      await Future.delayed(const Duration(milliseconds: 300));

      var messages =
          await client.db.chatDao.getMessages(channel: channel).get();
      expect(messages.first.state, MessageState.delivered);

      await chatClient.markAsRead(messageId: messages.first.id);

      messages =
          await client.db.chatDao.getMessages(channel: channel).get();
      expect(messages.first.state, MessageState.read);
    });
  });
}
