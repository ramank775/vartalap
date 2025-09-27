import 'package:drift/drift.dart';
import 'package:taskq/storage/database.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart'
    show VartalapChatClient;
import 'package:vartalap_messaging_flutter/client/chat.dart';
import 'package:vartalap_messaging_flutter/client/secure_token_manager.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/events.dart';
import 'package:vartalap_messaging_flutter/mapper/mapper.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

class VartalapChatClientFlutter {
  late VartalapChatClient client;
  late TaskScheduler scheduler;
  late VartalapTaskFactory factory;
  late ChatDatabase _db;
  VartalapChatClientFlutter({
    required String apiKey,
    String? apiBaseUrl,
    String? wsUrl,
    VartalapChatClient? client,
  }) {
    this.client = client ??
        VartalapChatClient(
          apiKey: apiKey,
          apiBaseUrl: apiBaseUrl,
          wsUrl: wsUrl,
          tokenManager: SecureStorageTokenManager(),
        );
  }

  Future<void> init() async {
    final userId = await client.getLoggedInUser();
    if (userId == null) {
      throw Exception("User not logged in");
    }
    _db = ChatDatabase(userId: userId);
    factory = VartalapTaskFactory(client, _db);
    final taskDb = TaskQDatabase.withQueryExectutor(_db.executor);
    scheduler = TaskScheduler(factory, db: taskDb);
    client.eventStream.listen((msg) {});
  }

  Future<Profile?> getLoggedInUser() async {
    // final userId = await client.getLoggedInUser();
    // if (userId == null) return null;
    // final profile = await client.fetchProfile(userId);
    // return Profile(
    //   userId: profile.userId,
    //   name: profile.name,
    //   email: profile.email ?? '',
    //   image: profile.image ?? '',
    // );
    final user = await client.getLoggedInUser();
    if (user == null) return null;
    return Profile(
      userId: '123',
      name: 'Raman',
      email: '',
      image: '',
    );
  }

  Selectable<ChatPreview> getChatPreviews({
    ChannelFilter? filter,
  }) {
    return _db.chatDao.getChatPreviews(filter: filter);
  }

  Future<ChatClient> chat({
    required ChannelModel channel,
    required Contact currentUser,
  }) async {
    final chatClient = ChatClient(
      channel: channel,
      client: this,
      chatDao: _db.chatDao,
      currentUser: currentUser,
    );
    await chatClient.init();
    return chatClient;
  }

  Selectable<ChannelModel> getChannels({
    ChannelFilter? filter,
  }) {
    return _db.channelDao.getChannels(filter: filter);
  }

  Future<ChannelModel> createChannel(
      ChannelModel channel, List<Member> members) async {
    final channelEntity = await _db.transaction(() async {
      // CreateChannelTask task = factory.create(
      //   CreateChannelTask.name,
      //   payload: channel,
      // ) as CreateChannelTask;
      // final taskId = await scheduler.schedule(task);
      const taskId = 1;
      final channelComp = ChannelsCompanion.insert(
        type: channel.type,
        taskId: const Value(taskId),
        config: const Value({}),
        extraData: Value(channel.extraData),
      );
      final insertedChannel =
          await _db.into(_db.channels).insertReturning(channelComp);
      await _db.batch((batch) {
        final rows = members.map(
          (member) => MembersCompanion.insert(
            memberId: member.user.id,
            channelId: insertedChannel.id,
          ),
        );
        if (rows.isEmpty) return;
        batch.insertAll(_db.members, rows);
      });
      return insertedChannel;
    });
    // channel.id = channelId;
    return channelEntity.toModel();
  }

  Selectable<Contact> getContacts({
    ContactFilter? filter,
  }) {
    final query = _db.select(_db.contacts);
    if (filter != null) {
      if (filter.name != null) {
        query.where((tbl) => tbl.extraData.like('%${filter.name}%'));
      }
      if (filter.phone != null) {
        query.where((tbl) => tbl.phone.like('%${filter.phone}%'));
      }
      if (filter.status != null) {
        query.where((tbl) => tbl.status.equals(filter.status.toString()));
      }
      if (filter.username != null) {
        query.where((tbl) => tbl.username.like('%${filter.username}%'));
      }
    }
    return query;
  }

  Future<void> syncChannels() async {
    return;
    // final channels = await client.queryChannels();
    // await _db.transaction(() async {
    //   await _db.delete(_db.channels).go();
    //   await _db.batch((batch) {
    //     batch.insertAll(
    //       _db.channels,
    //       channels.items
    //           .map((channel) => ChannelsCompanion.insert(
    //                 type: ChannelType.values.byName(channel.type),
    //                 config: Value(Map<String, dynamic>.from({})),
    //                 extraData: Value({
    //                   "name": channel.name,
    //                   "image": channel.profilePic,
    //                 }),
    //               ))
    //           .toList(),
    //     );
    //   });
    // });
  }

  Future<void> syncContacts() async {
    await _db.transaction(() async {
      final contacts = [
        const Contact(
          id: 2,
          name: 'Raman',
          phone: '1234567890',
          username: 'raman123',
          status: ContactStatus.active,
        ),
        const Contact(
          id: 3,
          name: 'Ravi',
          phone: '0987654321',
          username: 'ravi456',
          status: ContactStatus.active,
        ),
      ];
      final count = await _db.contacts.count().getSingle();
      if (count > 0) {
        return;
      }
      await _db.contacts.insertAll(
        contacts.map(
          (contact) => ContactsCompanion.insert(
            id: Value(contact.id),
            name: Value(contact.name),
            phone: Value(contact.phone),
            username: Value(contact.username),
            status: contact.status,
            extraData: Value(contact.extraData),
            photo: Value(contact.photo),
          ),
        ),
      );
      // SyncContactsTask task =
      //     factory.create(SyncContactsTask.name) as SyncContactsTask;
      // await scheduler.schedule(task);
    });
  }

  Future<void> syncMessages() async {
    await _db.transaction(() async {
      // SyncMessageTask task =
      //     factory.create(SyncMessageTask.name) as SyncMessageTask;
      // await scheduler.schedule(task);
    });
  }
}
