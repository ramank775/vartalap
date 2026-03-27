import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' as messaging;
import 'package:vartalap_messaging_flutter/db/chat_db.dart' hide Task;
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

class SyncMessageTask extends VartalapTask<void> {
  static const name = 'sync-messages';

  SyncMessageTask(
    messaging.VartalapChatClient client,
    ChatDatabase db, {
    int? id,
    TaskStatus state = TaskStatus.pending,
  }) : super(
          client,
          db,
          name,
          id: id,
          state: state,
        );

  @override
  Future<void> process() async {
    final remoteMessages = await client.syncMessages();
    if (remoteMessages.isEmpty) return;

    final myUid = await client.getLoggedInUser();

    for (final remoteMsg in remoteMessages) {
      // Skip duplicates
      final existingMsg = await (db.select(db.messages)
            ..where((tbl) => tbl.rid.equals(remoteMsg.id)))
          .getSingleOrNull();
      if (existingMsg != null) continue;

      // Resolve channel
      ChannelModel? channelRow;
      final isIndividual =
          remoteMsg.head.type == messaging.ChannelType.individual;

      if (isIndividual && remoteMsg.head.to == myUid) {
        // Incoming 1-1: find channel by sender's UID in members
        channelRow = await (db.select(db.channels).join([
          innerJoin(db.members, db.members.channelId.equalsExp(db.channels.id)),
          innerJoin(db.contacts, db.contacts.id.equalsExp(db.members.memberId)),
        ])
              ..where(db.contacts.uid.equals(remoteMsg.head.from) &
                  db.channels.type
                      .equals(messaging.ChannelType.individual.name)))
            .map((row) => row.readTable(db.channels))
            .getSingleOrNull();
      } else {
        // Group message or outgoing 1-1: channel CID matches 'to'
        channelRow = await (db.select(db.channels)
              ..where((tbl) => tbl.cid.equals(remoteMsg.head.to)))
            .getSingleOrNull();
      }

      // Ensure sender contact exists
      var senderRow = await (db.select(db.contacts)
            ..where((tbl) => tbl.uid.equals(remoteMsg.head.from)))
          .getSingleOrNull();

      int localSenderId;
      if (senderRow == null) {
        localSenderId =
            await db.into(db.contacts).insert(ContactsCompanion.insert(
                  uid: Value(remoteMsg.head.from),
                  status: ContactStatus.active,
                ));
      } else {
        localSenderId = senderRow.id;
      }

      // Auto-create 1-1 channel if missing
      if (channelRow == null && isIndividual) {
        channelRow = await db.into(db.channels).insertReturning(
              ChannelsCompanion.insert(
                type: messaging.ChannelType.individual,
                cid: Value(remoteMsg.head.from),
                extraData: Value({
                  'name': senderRow?.displayName ?? remoteMsg.head.from
                }),
                config: Value(<String, dynamic>{}),
              ),
            );
        await db.into(db.members).insert(MembersCompanion.insert(
              channelId: channelRow.id,
              memberId: localSenderId,
            ));
        debugPrint(
            '[SYNC] Auto-created channel for ${remoteMsg.head.from}');
      }

      if (channelRow == null) {
        debugPrint(
            '[SYNC] Channel not found for message ${remoteMsg.id}, skipping');
        continue;
      }

      // Insert message
      await db.into(db.messages).insert(MessagesCompanion.insert(
            rid: Value(remoteMsg.id),
            type: _mapRemoteTypeToLocal(remoteMsg.head.category),
            state: MessageState.delivered,
            payload: remoteMsg.body as Map<String, dynamic>,
            channelId: channelRow.id,
            senderId: localSenderId,
            remoteCreatedAt: Value(DateTime.fromMillisecondsSinceEpoch(
                remoteMsg.meta.createdAt)),
            updatedAt: Value(DateTime.now()),
          ));
    }
  }

  MessageType _mapRemoteTypeToLocal(String category) {
    switch (category) {
      case 'message':
        return MessageType.text;
      case 'image':
        return MessageType.image;
      default:
        return MessageType.text;
    }
  }

  @override
  void deserializePayload(String rawPayload) {}

  @override
  String serializePayload() => '';
}