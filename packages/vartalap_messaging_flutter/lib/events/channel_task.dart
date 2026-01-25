import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';
import 'package:vartalap_messaging_flutter/mapper/mapper.dart';

class CreateChannelTask extends VartalapTask<int> {
  static const name = 'create-channel';
  CreateChannelTask(
    messaging.VartalapChatClient client,
    ChatDatabase db, {
    int? payload,
    int? id,
    TaskStatus state = TaskStatus.pending,
  }) : super(
          client,
          db,
          name,
          payload: payload,
          id: id,
          state: state,
        );

  @override
  Future<List<Task>> getDependencies() async {
    return [];
  }

  @override
  Future<void> process() async {
    // 0. Fetch Channel Model locally using the ID (payload)
    final channel = await (db.select(db.channels)
          ..whereSamePrimaryKey(ChannelsCompanion(id: Value(payload))))
        .getSingle();

    // 1. Fetch channel members from local DB
    final memberRows = await (db.select(db.members).join([
      innerJoin(db.contacts, db.contacts.id.equalsExp(db.members.memberId)),
    ])..where(db.members.channelId.equals(payload))).get();

    final memberUids = memberRows
        .map((row) => row.readTable(db.contacts).uid)
        .whereType<String>()
        .toList();

    if (memberUids.isEmpty) {
      throw Exception('Cannot create channel: No members with valid remote UIDs');
    }

    // 2. Call backend to create channel
    final response = await client.createChannel(messaging.ChannelPayload()
      ..type = channel.type.name
      ..name = (channel.extraData?['name'] as String?) ?? ''
      ..members = memberUids);

    // 3. Update local channel with remote ID (cid)
    await (db.update(db.channels)
          ..where((tbl) => tbl.id.equals(payload)))
        .write(ChannelsCompanion(
      cid: Value(response.channelId),
      updatedAt: Value(DateTime.now()),
    ));

    debugPrint('[SYNC] Created remote channel: ${response.channelId}');
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
