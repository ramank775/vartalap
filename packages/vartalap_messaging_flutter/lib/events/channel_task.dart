import 'package:drift/drift.dart';
import 'package:taskq/task.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart'
    show VartalapChatClient;
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';
import 'package:vartalap_messaging_flutter/mapper/mapper.dart';

import '../models/models.dart';

class CreateChannelTask extends VartalapTask<ChannelModel> {
  static const name = 'create-channel';
  CreateChannelTask(
    VartalapChatClient client,
    ChatDatabase db, {
    ChannelModel? payload,
  }) : super(client, db, name, payload: payload);

  @override
  Future<List<Task>> getDependencies() async {
    return [];
  }

  @override
  Future<void> process() async {
    ChannelEntity channel = await (db.select(db.channels)
          ..whereSamePrimaryKey(ChannelsCompanion(id: Value(payload.id))))
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

    // final resp = await client.createChannel(
    //   ChannelModel(
    //     id: payload.id,
    //     type: payload.type,
    //     displayName: payload.displayName,
    //     members: members.map((m) => Member(user: m, role: 'member')).toList(),
    //   ),
    // );
    final cid = '';
    await (db.update(db.channels)
          ..where((channel) => channel.id.equals(payload.id)))
        .write(ChannelsCompanion(cid: Value(cid)));
  }

  @override
  void deserializePayload(String rawPayload) async {
    final channelId = int.parse(rawPayload);
    final channel = await (db.select(db.channels)
          ..whereSamePrimaryKey(ChannelsCompanion(id: Value(channelId))))
        .getSingle();
    payload = channel.toModel();
  }

  @override
  String serializePayload() {
    return payload.id.toString();
  }
}
