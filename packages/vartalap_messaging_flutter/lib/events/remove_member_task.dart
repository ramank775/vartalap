import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

import '../models/models.dart';

class RemoveMember {
  ChannelModel channel;
  Member members;
  RemoveMember(this.channel, this.members);
}

class RemoveMemberTask extends VartalapTask<RemoveMember> {
  static const name = 'remove-member';
  RemoveMemberTask(super.client, super.db, super.type);

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
