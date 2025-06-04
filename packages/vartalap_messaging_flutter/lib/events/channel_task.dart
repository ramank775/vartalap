import 'package:drift/drift.dart';
import 'package:taskq/task.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

import '../models/models.dart';

class CreateChannelTask extends VartalapTask<Channel> {
  static const name = 'create-channel';
  CreateChannelTask(
    VartalapChatClient client,
    ChatDatabase db, {
    Channel? payload,
  }) : super(client, db, name, payload: payload);

  @override
  Future<List<Task>> getDependencies() async {
    return [];
  }

  @override
  Future<void> process() async {
    ChannelEntity channel = await (db.select(db.channels)
          ..whereSamePrimaryKey(ChannelsCompanion(id: Value(payload.id!))))
        .getSingle();
    final result = await (db.selectOnly(db.members)
          ..join([
            innerJoin(
                db.contacts, db.members.memberId.equalsExp(db.contacts.id)),
          ])
          ..where(db.members.channelId.equals(channel.id))
          ..addColumns([db.contacts.username, db.members.role]))
        .get();
    final members =
        result.map((row) => row.read<String>(db.contacts.username)!).toList();
    ChannelModel model = ChannelModel()
      ..name = channel.extraData?['name']
      ..profilePic = channel.extraData?['image']
      ..type = channel.type.toString()
      ..members = members;
    final resp = await client.createChannel(model);
    await (db.update(db.channels)
          ..where((channel) => channel.id.equals(payload.id!)))
        .write(ChannelsCompanion(cid: Value(resp.channelId)));
  }

  @override
  void deserializePayload(String rawPayload) async {
    final channelId = int.parse(rawPayload);
    final channel = await (db.select(db.channels)
          ..whereSamePrimaryKey(ChannelsCompanion(id: Value(channelId))))
        .getSingle();
    payload = Channel(channel.type, []);
  }

  @override
  String serializePayload() {
    return payload.id.toString();
  }
}
