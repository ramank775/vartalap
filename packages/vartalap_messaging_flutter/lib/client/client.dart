import 'package:drift/drift.dart';
import 'package:taskq/storage/database.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/client/secure_token_manager.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/events/channel_task.dart';
import 'package:vartalap_messaging_flutter/events/factory.dart';
import 'package:vartalap_messaging_flutter/events/message_task.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

class VartalapChatClientFlutter {
  late VartalapChatClient client;
  late TaskScheduler scheduler;
  late VartalapTaskFactory factory;
  late ChatDatabase _db;
  VartalapChatClientFlutter({
    required String apiKey,
    VartalapChatClient? client,
  }) {
    this.client = client ??
        VartalapChatClient(
          apiKey: apiKey,
          tokenManager: SecureStorageTokenManager(),
        );
    _db = ChatDatabase(userId: '1');
    factory = VartalapTaskFactory(this.client, _db);
    final taskDb = TaskQDatabase.withQueryExectutor(_db.executor);
    scheduler = TaskScheduler(factory, db: taskDb);
  }

  void init() {
    client.eventStream.listen((msg) {});
  }

  Future<ChannelModel> createChannel(Channel channel) async {
    final channelId = await _db.transaction(() async {
      CreateChannelTask task = factory.create(
        CreateChannelTask.name,
        payload: channel,
      ) as CreateChannelTask;
      final taskId = await scheduler.schedule(task);
      final channelComp = ChannelsCompanion.insert(
        type: channel.type,
        taskId: Value(taskId),
        config: Value(Map<String, dynamic>.from({})),
        extraData: Value({
          "name": channel.name,
          "image": channel.image,
        }),
      );
      final insertedChannel =
          await _db.into(_db.channels).insertReturning(channelComp);
      await _db.batch((batch) {
        final rows = channel.members.map(
          (member) => MembersCompanion.insert(
            memberId: member.memberId,
            channelId: insertedChannel.id,
          ),
        );
        batch.insertAll(_db.members, rows);
      });
      return insertedChannel.id;
    });
    channel.channelId = channelId.toString();
    return channel;
  }

  Future<void> sendMessage(List<RemoteMessage> msg, Channel channel) async {
    await _db.transaction(() async {
      SendMessageTask task = factory.create<SendMessage>(
        SendMessageTask.name,
        payload: SendMessage(channel.id!, msg),
      ) as SendMessageTask;
      await scheduler.schedule(task);
    });
  }
}
