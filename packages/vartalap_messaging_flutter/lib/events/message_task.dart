import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart' hide Task;
import 'package:vartalap_messaging_flutter/events/asset_upload_task.dart';
import 'package:vartalap_messaging_flutter/events/factory.dart';
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
  Future<List<Task>> getDependencies() async {
    final assetRows = await (db.select(db.assests).join([
      innerJoin(db.messages, db.messages.id.isIn(payload.messageIds)),
    ])
          ..where(db.assests.id.isNotNull()))
        .get();

    final dependencies = <Task>[];
    for (final row in assetRows) {
      final assetId = row.readTable(db.assests).id;
      final task = VartalapTaskFactory(client, db).create(
        AssetUploadTask.name,
        payload: assetId,
      );
      dependencies.add(task);
    }

    return dependencies;
  }

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
      // 1. Resolve attachments for this message
      final linkedAssetRows = await (db.select(db.assests).join([
        innerJoin(db.messageAssets,
            db.messageAssets.assetId.equalsExp(db.assests.id)),
      ])
            ..where(db.messageAssets.messageId.equals(row.id)))
          .get();

      final attachments =
          linkedAssetRows.map((r) => r.readTable(db.assests)).toList();

      // 2. Map local payload to remote payload
      Map<String, dynamic> remoteBody = Map.from(row.payload);

      // If it's an image, use the remote assetId from the first attachment
      if (row.type == MessageType.image && attachments.isNotEmpty) {
        remoteBody['assetId'] = attachments.first.assetId;
      }

      final head = Head(
        type: channelRow.type,
        to: remoteChannelId,
        from: (await client.getLoggedInUser()) ?? 'unknown',
        category: _mapLocalTypeToRemote(row.type),
      );

      final remoteMsg = RemoteMessage()
        ..id = row.id.toString() // Correlation ID
        ..head = head
        ..meta = Meta(createdAt: row.localCreatedAt.millisecondsSinceEpoch)
        ..body = remoteBody;

      remoteMessages.add(remoteMsg);
    }

    try {
      // Send to server
      await client.sendMessage(remoteMessages, sync: true);

      // Update local state to 'sent'
      await (db.update(db.messages)
            ..where((tbl) => tbl.id.isIn(payload.messageIds)))
          .write(MessagesCompanion(
        state: Value(MessageState.sent),
        updatedAt: Value(DateTime.now()),
      ));
    } catch (e) {
      // Update local state to 'error'
      await (db.update(db.messages)
            ..where((tbl) => tbl.id.isIn(payload.messageIds)))
          .write(MessagesCompanion(
        state: Value(MessageState.error),
        updatedAt: Value(DateTime.now()),
      ));
      rethrow;
    }
  }

  String _mapLocalTypeToRemote(MessageType type) {
    switch (type) {
      case MessageType.text:
        return 'message';
      case MessageType.image:
        return 'image';
      default:
        return 'message';
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
