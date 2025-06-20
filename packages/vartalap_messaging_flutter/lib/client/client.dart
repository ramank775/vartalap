import 'package:drift/drift.dart';
import 'package:taskq/storage/database.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart'
    show VartalapChatClient, ChannelType;
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

  Selectable<ChannelModel> getChannels({
    ChannelFilter? filter,
  }) {
    return _db.channelDao.getChannels(filter: filter);
  }

  Future<ChannelModel> createChannel(ChannelModel channel) async {
    final channelId = await _db.transaction(() async {
      CreateChannelTask task = factory.create(
        CreateChannelTask.name,
        payload: channel,
      ) as CreateChannelTask;
      final taskId = await scheduler.schedule(task);
      final channelComp = ChannelsCompanion.insert(
        type: channel.type,
        taskId: Value(taskId),
        config: Value(Map<String, dynamic>.from({})),
        extraData: Value(channel.extraData),
      );
      final insertedChannel =
          await _db.into(_db.channels).insertReturning(channelComp);
      await _db.batch((batch) {
        final rows = channel.members?.map(
          (member) => MembersCompanion.insert(
            memberId: member.user.id,
            channelId: insertedChannel.id,
          ),
        );
        if (rows == null) return;
        batch.insertAll(_db.members, rows);
      });
      return insertedChannel.id;
    });
    // channel.id = channelId;
    return channel;
  }

  Future<void> addMembers(List<Member> members, ChannelModel channel) async {
    await _db.transaction(() async {
      AddMembersTask task = factory.create(
        AddMembersTask.name,
        payload: AddMembers(channel, members),
      ) as AddMembersTask;
      await scheduler.schedule(task);
      await _db.batch((batch) {
        final rows = members.map(
          (member) => MembersCompanion.insert(
            memberId: member.user.id,
            channelId: channel.id,
          ),
        );
        batch.insertAll(_db.members, rows);
      });
    });
  }

  Future<void> removeMember(Member member, ChannelModel channel) async {
    await _db.transaction(() async {
      RemoveMemberTask task = factory.create(
        RemoveMemberTask.name,
        payload: RemoveMember(channel, member),
      ) as RemoveMemberTask;
      await scheduler.schedule(task);
      _db
          .delete(
            _db.members,
          )
          .where((tbl) =>
              tbl.channelId.equals(channel.id) &
              tbl.memberId.equals(member.user.id));
    });
  }

  Future<void> sendMessage(List<ChatMessage> msg, ChannelModel channel) async {
    await _db.transaction(() async {
      SendMessageTask task = factory.create<SendMessage>(
        SendMessageTask.name,
        payload: SendMessage(channel.id, msg),
      ) as SendMessageTask;
      await scheduler.schedule(task);
    });
  }

  Selectable<ChatMessage> getMessages({
    ChannelModel? channel,
    MessageFilter? filter,
  }) {
    final query = _db.select(_db.messages);
    if (channel != null) {
      query.where((tbl) => tbl.channelId.equals(channel.id));
    }
    if (filter != null) {
      if (filter.type != null) {
        query.where((tbl) => tbl.type.equals(filter.type.toString()));
      }
      if (filter.state != null) {
        query.where((tbl) => tbl.state.equals(filter.state.toString()));
      }
      if (filter.senderId != null) {
        query.where((tbl) => tbl.senderId.equals(filter.senderId!));
      }
    }
    return query.map((message) => message.toModel());
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
    final channels = await client.queryChannels();
    await _db.transaction(() async {
      await _db.delete(_db.channels).go();
      await _db.batch((batch) {
        batch.insertAll(
          _db.channels,
          channels.items
              .map((channel) => ChannelsCompanion.insert(
                    type: ChannelType.values.byName(channel.type),
                    config: Value(Map<String, dynamic>.from({})),
                    extraData: Value({
                      "name": channel.name,
                      "image": channel.profilePic,
                    }),
                  ))
              .toList(),
        );
      });
    });
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
      ];
      _db.contacts.insertAll(
        contacts.map(
          (contact) => ContactsCompanion.insert(
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
      SyncMessageTask task =
          factory.create(SyncMessageTask.name) as SyncMessageTask;
      await scheduler.schedule(task);
    });
  }
}
