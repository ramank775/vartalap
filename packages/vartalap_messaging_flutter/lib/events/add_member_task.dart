import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

class AddMembersPayload {
  final int localChannelId;
  final List<int> localMemberIds;

  AddMembersPayload({required this.localChannelId, required this.localMemberIds});

  Map<String, dynamic> toJson() => {
    'localChannelId': localChannelId,
    'localMemberIds': localMemberIds,
  };

  factory AddMembersPayload.fromJson(Map<String, dynamic> json) => AddMembersPayload(
    localChannelId: json['localChannelId'] as int,
    localMemberIds: List<int>.from(json['localMemberIds'] as List),
  );
}

class AddMembersTask extends VartalapTask<AddMembersPayload> {
  static const name = 'add-members';
  AddMembersTask(
    VartalapChatClient client,
    ChatDatabase db, {
    AddMembersPayload? payload,
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
    payload = AddMembersPayload.fromJson(json.decode(rawPayload));
  }

  @override
  Future<void> process() async {
    final channelRow = await (db.select(db.channels)
          ..where((tbl) => tbl.id.equals(payload.localChannelId)))
        .getSingle();

    final remoteChannelId = channelRow.cid;
    if (remoteChannelId == null) {
      throw Exception('Cannot add members: Channel has no remote ID yet');
    }

    final contactRows = await (db.select(db.contacts)
          ..where((tbl) => tbl.id.isIn(payload.localMemberIds)))
        .get();

    final memberUids = contactRows
        .map((row) => row.uid)
        .whereType<String>()
        .toList();

    if (memberUids.isEmpty) {
      throw Exception('No members with valid remote UIDs to add');
    }

    await client.addChannelMembers(remoteChannelId, memberUids);
  }

  @override
  String serializePayload() {
    return json.encode(payload.toJson());
  }
}