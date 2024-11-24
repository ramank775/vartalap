import 'dart:convert';

import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/placeholder_task.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

class SendMessage {
  int channelId;
  List<RemoteMessage> messages;

  SendMessage(this.channelId, this.messages);

  Map<String, dynamic> toJson() {
    return {
      "channelId": channelId,
      "messages": messages,
    };
  }

  static SendMessage fromJson(Map<String, dynamic> json) {
    final channel = json["channelId"];
    final messages =
        json["messages"].map((item) => RemoteMessage.fromJson(item)).toList();
    return SendMessage(channel, messages);
  }
}

class SendMessageTask extends VartalapTask<SendMessage> {
  static const name = 'send-message';
  SendMessageTask(
    VartalapChatClient client,
    ChatDatabase db, {
    SendMessage? payload,
    int? id,
    TaskState state = TaskState.pending,
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
    final channelRow = await (db.selectOnly(db.channels)
          ..addColumns([db.channels.cid, db.channels.taskId])
          ..where(db.channels.id.equals(payload.channelId)))
        .getSingle();

    final cid = channelRow.read(db.channels.cid);
    List<Task> dependencies = [];
    if (cid == null) {
      final taskId = channelRow.read(db.channels.taskId)!;
      dependencies.add(PlaceholderTask(client, db, id: taskId));
    }
    // Decode the message and convert into remote message here
    // If message contains attachments upload those attachment
    // Add dependency task for those attachments
    // On Attachment upload task successfully update attachment ids
    // So that on process messages can be recontructed from database
    // At the time of reconstruction all the dependencies will be
    // Available as all the dependent task are completed.
    await db.batch((batch) {
      final rows = payload.messages.map(
        (m) => MessagesCompanion.insert(
          id: m.id,
          type: m.head.type.toString(),
          state: '',
          payload: m.body,
          channelId: payload.channelId,
          senderId: m.head.from,
        ),
      );
      batch.insertAll(db.messages, rows);
    });
    return dependencies;
  }

  @override
  Future<void> process() async {
    await client.sendMessage(payload.messages);
  }

  @override
  void deserializePayload(String rawPayload) {
    final rawJsons = json.decode(rawPayload) as Map<String, dynamic>;
    payload = SendMessage.fromJson(rawJsons);
  }

  @override
  String serializePayload() {
    return json.encode(payload);
  }
}
