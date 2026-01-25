import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

class RemoveMemberPayload {
  final int localChannelId;
  final int localMemberId;

  RemoveMemberPayload({required this.localChannelId, required this.localMemberId});

  Map<String, dynamic> toJson() => {
    'localChannelId': localChannelId,
    'localMemberId': localMemberId,
  };

  factory RemoveMemberPayload.fromJson(Map<String, dynamic> json) => RemoveMemberPayload(
    localChannelId: json['localChannelId'] as int,
    localMemberId: json['localMemberId'] as int,
  );
}

class RemoveMemberTask extends VartalapTask<RemoveMemberPayload> {
  static const name = 'remove-member';
  RemoveMemberTask(
    VartalapChatClient client,
    ChatDatabase db, {
    RemoveMemberPayload? payload,
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
  void deserializePayload(String rawPayload) {
    payload = RemoveMemberPayload.fromJson(json.decode(rawPayload));
  }

  @override
  Future<void> process() async {
    final channelRow = await (db.select(db.channels)
          ..where((tbl) => tbl.id.equals(payload.localChannelId)))
        .getSingle();

    final remoteChannelId = channelRow.cid;
    if (remoteChannelId == null) {
      throw Exception('Cannot remove member: Channel has no remote ID yet');
    }

    final contactRow = await (db.select(db.contacts)
          ..where((tbl) => tbl.id.equals(payload.localMemberId)))
        .getSingle();

    final memberUid = contactRow.uid;
    if (memberUid == null) {
      throw Exception('Cannot remove member: Member has no remote UID');
    }

    await client.removeChannelMember(remoteChannelId, memberUid);
  }

  @override
  String serializePayload() {
    return json.encode(payload.toJson());
  }
}