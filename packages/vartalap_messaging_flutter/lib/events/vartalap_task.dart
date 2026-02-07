import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart' hide Task;

abstract class VartalapTask<T> extends Task<T> {
  VartalapChatClient client;
  ChatDatabase db;
  VartalapTask(
    this.client,
    this.db,
    String type, {
    T? payload,
    int? id,
    TaskStatus state = TaskStatus.pending,
  }) : super(
          type,
          payload: payload,
          id: id,
          status: state,
        );
}
