import 'package:flutter/foundation.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart'
    show VartalapChatClient;
import 'package:vartalap_messaging_flutter/db/chat_db.dart' hide Task;
import 'package:vartalap_messaging_flutter/events/message_task.dart';
import 'package:vartalap_messaging_flutter/events/sync_message_task.dart';
import 'package:vartalap_messaging_flutter/events/asset_upload_task.dart';
import 'package:vartalap_messaging_flutter/events/sync_contact_task.dart';
import 'package:vartalap_messaging_flutter/events/api_request_task.dart';

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
        final channelId = payload is ChannelModel ? payload.id : payload as int?;
        return CreateChannelTask(
          client,
          db,
          payload: channelId,
        );
      case SendMessageTask.name:
        return SendMessageTask(
          client,
          db,
          payload: payload as SendMessage?,
          id: id,
          state: state,
        );
      case SyncMessageTask.name:
        return SyncMessageTask(
          client,
          db,
          id: id,
          state: state,
        );
      case SyncContactsTask.name:
        return SyncContactsTask(
          client,
          db,
          id: id,
          state: state,
        );
      case AssetUploadTask.name:
        return AssetUploadTask(
          client,
          db,
          payload: payload as int?,
          id: id,
          state: state,
        );
      case VartalapApiRequestTask.name:
        return VartalapApiRequestTask(
          client,
          db,
          payload: payload as ApiRequestPayload?,
          id: id,
          state: state,
        );
      default:
        throw ErrorDescription('Unkown task type');
    }
  }
}
