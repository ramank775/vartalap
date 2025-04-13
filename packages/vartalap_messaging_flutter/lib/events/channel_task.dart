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
          ..whereSamePrimaryKey(ChannelsCompanion(id: Value(payload))))
        .getSingle();
    final result = await (db.selectOnly(db.members)
          ..where(db.members.channelId.equals(channel.id))
          ..addColumns([db.members.memberId]))
        .get();
    final members =
        result.map((row) => row.read(db.members.memberId)!).toList();
    ChannelModel model = ChannelModel()
      ..name = channel.extraData?['name']
      ..profilePic = channel.extraData?['image']
      ..type = channel.type
      ..members = members;
    final resp = await client.createChannel(model);
    await (db.update(db.channels)
          ..where((channel) => channel.id.equals(payload)))
        .write(ChannelsCompanion(cid: Value(resp.channelId)));
  }

  @override
  void deserializePayload(String rawPayload) {
    payload = int.parse(rawPayload);
  }

  @override
  String serializePayload() {
    return payload.toString();
  }
}
