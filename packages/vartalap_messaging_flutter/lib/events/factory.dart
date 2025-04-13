import 'package:flutter/foundation.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/message_task.dart';

import '../models/channel.dart';
import 'channel_task.dart';

class VartalapTaskFactory implements TaskFactory {
  VartalapChatClient client;
  ChatDatabase db;
  VartalapTaskFactory(this.client, this.db);
  @override
  Task create<T>(
    String taskType, {
    T? payload,
    int? id,
    TaskStatus state = TaskStatus.pending,
    List<Task> dependentOn = const [],
  }) {
    switch (taskType) {
      case CreateChannelTask.name:
        return CreateChannelTask(
          client,
          db,
          payload: payload as Channel?,
        );
      case SendMessageTask.name:
        return SendMessageTask(
          client,
          db,
          payload: payload as SendMessage?,
        );
      default:
        throw ErrorDescription('Unkown task type');
    }
  }
}
