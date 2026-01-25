import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/client/client.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

import '../models/models.dart';

class RemoveMember {
  ChannelModel channel;
  Member members;
  RemoveMember(this.channel, this.members);
}

class RemoveMemberTask extends VartalapTask<RemoveMember> {
  static const name = 'remove-member';
  RemoveMemberTask(
    VartalapChatClient client,
    ChatDatabase db, {
    RemoveMember? payload,
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
    // TODO: implement deserializePayload
  }

  @override
  Future<void> process() {
    // TODO: implement process
    throw UnimplementedError();
  }

  @override
  String serializePayload() {
    // TODO: implement serializePayload
    throw UnimplementedError();
  }
}
