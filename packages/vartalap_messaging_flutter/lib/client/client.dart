import 'package:drift/drift.dart';
import 'package:taskq/storage/database.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/client/secure_token_manager.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/entity/messages.dart';
import 'package:vartalap_messaging_flutter/events/channel_task.dart';
import 'package:vartalap_messaging_flutter/events/factory.dart';
import 'package:vartalap_messaging_flutter/events/message_task.dart';
import 'package:vartalap_messaging_flutter/events/remove_member_task.dart';
import 'package:vartalap_messaging_flutter/events/sync_contact_task.dart';
import 'package:vartalap_messaging_flutter/events/sync_message_task.dart';
import 'package:vartalap_messaging_flutter/models/models.dart' hide Contact;

import '../events/add_member_task.dart';

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
    final userId = await client.getLoggedInUser();
    if (userId == null) return null;
    final profile = await client.fetchProfile(userId);
    return Profile(
      userId: profile.userId,
      name: profile.name,
      email: profile.email ?? '',
      image: profile.image ?? '',
    );
  }

  Selectable<Channel> getChannels({
    ChannelFilter? filter,
  }) {
    final query = _db.select(_db.channels);
    if (filter != null) {
      if (filter.type != null) {
        query.where((tbl) => tbl.type.equals(filter.type!.toString()));
      }
      if (filter.name != null) {
        query.where((tbl) => tbl.extraData.like('%${filter.name}%'));
      }
    }
    return query.map<Channel>((row) => Channel.fromDb(row));
  }

  Future<void> createChannel(Channel channel) async {
    await _db.transaction(() async {
      CreateChannelTask task = factory.create(
        CreateChannelTask.name,
        payload: channel,
      ) as CreateChannelTask;
      final taskId = await scheduler.schedule(task);
      final channelComp = ChannelsCompanion.insert(
        type: channel.type,
        taskId: Value(taskId),
        config: Value(Map<String, dynamic>.from({})),
        extraData: Value({
          "name": channel.name,
          "image": channel.image,
        }),
      );
      final insertedChannel =
          await _db.into(_db.channels).insertReturning(channelComp);
      await _db.batch((batch) {
        final rows = channel.members.map(
          (member) => MembersCompanion.insert(
            memberId: member.user.id.toString(),
            channelId: insertedChannel.id,
          ),
        );
        batch.insertAll(_db.members, rows);
      });
      return insertedChannel.id;
    });
    // channel.id = channelId;
    // return channel;
  }

  Future<void> addMembers(List<Member> members, Channel channel) async {
    await _db.transaction(() async {
      AddMembersTask task = factory.create(
        AddMembersTask.name,
        payload: AddMembers(channel, members),
      ) as AddMembersTask;
      await scheduler.schedule(task);
      await _db.batch((batch) {
        final rows = members.map(
          (member) => MembersCompanion.insert(
            memberId: member.user.id.toString(),
            channelId: channel.id!,
          ),
        );
        batch.insertAll(_db.members, rows);
      });
    });
  }

  Future<void> removeMember(Member member, Channel channel) async {
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
              tbl.channelId.equals(channel.id!) &
              tbl.memberId.equals(member.user.id!.toString()));
    });
  }

  Future<void> sendMessage(List<RemoteMessage> msg, Channel channel) async {
    await _db.transaction(() async {
      SendMessageTask task = factory.create<SendMessage>(
        SendMessageTask.name,
        payload: SendMessage(channel.id!, msg),
      ) as SendMessageTask;
      await scheduler.schedule(task);
    });
  }

  Selectable<ChatMessage> getMessages({
    Channel? channel,
    MessageFilter? filter,
  }) {
    final query = _db.select(_db.messages);
    if (channel != null) {
      query.where((tbl) => tbl.channelId.equals(channel.id!));
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
    return query.map((message) => ChatMessage.fromMap(message));
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
      SyncContactsTask task =
          factory.create(SyncContactsTask.name) as SyncContactsTask;
      await scheduler.schedule(task);
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
