import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

class SyncMessageTask extends VartalapTask<void> {
  static const name = 'sync-messages';

  SyncMessageTask(super.client, super.db, super.type);

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
