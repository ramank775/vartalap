import 'package:vartalap_messaging/client/client.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

class PlaceholderTask extends VartalapTask {
  PlaceholderTask(
    VartalapChatClient client,
    ChatDatabase db, {
    int? id,
  }) : super(
          client,
          db,
          "placeholder",
          id: id,
        );

  @override
  void deserializePayload(String rawPayload) {}

  @override
  Future<void> process() {
    return Future.value();
  }

  @override
  String serializePayload() {
    return '';
  }
}
