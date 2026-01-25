import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

class SendMessage {
  int channelId;
  List<int> messageIds;

  SendMessage(this.channelId, this.messageIds);

  Map<String, dynamic> toJson() {
    return {
      "channelId": channelId,
      "messageIds": messageIds,
    };
  }

  static SendMessage fromJson(Map<String, dynamic> json) {
    return SendMessage(
      json["channelId"] as int,
      List<int>.from(json["messageIds"] as List),
    );
  }
}

class SendMessageTask extends VartalapTask<SendMessage> {
  static const name = 'send-message';
  SendMessageTask(
    VartalapChatClient client,
    ChatDatabase db, {
    SendMessage? payload,
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
  Future<void> process() async {
    final channelRow = await (db.select(db.channels)
          ..where((tbl) => tbl.id.equals(payload.channelId)))
        .getSingle();
    
    final remoteChannelId = channelRow.cid;
    if (remoteChannelId == null) {
      throw Exception('Cannot send message: Channel has no remote ID yet');
    }

    final messageRows = await (db.select(db.messages)
          ..where((tbl) => tbl.id.isIn(payload.messageIds)))
        .get();

    final remoteMessages = <RemoteMessage>[];
    for (var row in messageRows) {
      final head = Head(
        type: channelRow.type,
        to: remoteChannelId,
        from: (await client.getLoggedInUser()) ?? 'unknown',
        category: 'message',
      );

      final remoteMsg = RemoteMessage()
        ..id = row.id.toString() // Use local ID as correlation ID
        ..head = head
        ..meta = Meta(createdAt: row.localCreatedAt.millisecondsSinceEpoch)
        ..body = row.payload;
      
      remoteMessages.add(remoteMsg);
    }

    try {
      // Send to server
      await client.sendMessage(remoteMessages, sync: true);

      // Update local state to 'sent'
      await (db.update(db.messages)
            ..where((tbl) => tbl.id.isIn(payload.messageIds)))
          .write(MessagesCompanion(
        state: const Value(MessageState.sent),
        updatedAt: Value(DateTime.now()),
      ));
    } catch (e) {
      // Update local state to 'error'
      await (db.update(db.messages)
            ..where((tbl) => tbl.id.isIn(payload.messageIds)))
          .write(MessagesCompanion(
        state: const Value(MessageState.error),
        updatedAt: Value(DateTime.now()),
      ));
      rethrow;
    }
  }

  @override
  void deserializePayload(String rawPayload) {
    final rawJsons = json.decode(rawPayload) as Map<String, dynamic>;
    payload = SendMessage.fromJson(rawJsons);
  }

  @override
  String serializePayload() {
    return json.encode(payload.toJson());
  }
}