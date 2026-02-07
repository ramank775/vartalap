import 'dart:convert';

import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

enum VartalapApiMethod {
  addMembers,
  removeMember,
  updateProfile,
  updateChannel,
}

class ApiRequestPayload {
  final VartalapApiMethod method;
  final Map<String, dynamic> data;

  ApiRequestPayload({required this.method, required this.data});

  Map<String, dynamic> toJson() => {
    'method': method.name,
    'data': data,
  };

  factory ApiRequestPayload.fromJson(Map<String, dynamic> json) => ApiRequestPayload(
    method: VartalapApiMethod.values.byName(json['method'] as String),
    data: json['data'] as Map<String, dynamic>,
  );
}

class VartalapApiRequestTask extends VartalapTask<ApiRequestPayload> {
  static const name = 'api-request';
  
  VartalapApiRequestTask(
    VartalapChatClient client,
    ChatDatabase db, {
    ApiRequestPayload? payload,
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
    payload = ApiRequestPayload.fromJson(json.decode(rawPayload));
  }

  @override
  Future<void> process() async {
    switch (payload.method) {
      case VartalapApiMethod.addMembers:
        final channelId = payload.data['channelId'] as String;
        final memberIds = List<String>.from(payload.data['memberIds'] as List);
        await client.addChannelMembers(channelId, memberIds);
        break;
      case VartalapApiMethod.removeMember:
        final channelId = payload.data['channelId'] as String;
        final memberId = payload.data['memberId'] as String;
        await client.removeChannelMember(channelId, memberId);
        break;
      case VartalapApiMethod.updateProfile:
        // Placeholder for future profile update implementation
        break;
      case VartalapApiMethod.updateChannel:
        // Placeholder for future channel update implementation
        break;
    }
  }

  @override
  String serializePayload() {
    return json.encode(payload.toJson());
  }
}
