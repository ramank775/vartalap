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
    // 1. Fetch missed messages from server
    final remoteMessages = await client.syncMessages();
    if (remoteMessages.isEmpty) return;

    await db.transaction(() async {
      for (final remoteMsg in remoteMessages) {
        // 2. Resolve local channel ID
        final channelRow = await (db.select(db.channels)
              ..where((tbl) => tbl.cid.equals(remoteMsg.head.to)))
            .getSingleOrNull();
        
        if (channelRow == null) {
          // TODO: If channel doesn't exist, we might need to fetch channel info
          // and create it locally first. For now, skip.
          debugPrint('[SYNC] Channel ${remoteMsg.head.to} not found locally, skipping message');
          continue;
        }

        // 3. Resolve local sender ID (Contact)
        final senderRow = await (db.select(db.contacts)
              ..where((tbl) => tbl.uid.equals(remoteMsg.head.from)))
            .getSingleOrNull();

        int localSenderId;
        if (senderRow == null) {
          // Create a placeholder contact if not found
          localSenderId = await db.into(db.contacts).insert(ContactsCompanion.insert(
            uid: Value(remoteMsg.head.from),
            username: Value(remoteMsg.head.from),
            status: ContactStatus.active,
          ));
        } else {
          localSenderId = senderRow.id;
        }

        // 4. Check if message already exists (prevent duplicates)
        final existingMsg = await (db.select(db.messages)
              ..where((tbl) => tbl.rid.equals(remoteMsg.id)))
            .getSingleOrNull();
        
        if (existingMsg != null) continue;

        // 5. Insert message locally
        await db.into(db.messages).insert(MessagesCompanion.insert(
          rid: Value(remoteMsg.id),
          type: _mapRemoteTypeToLocal(remoteMsg.head.category),
          state: MessageState.delivered, // Already on server, so delivered
          payload: remoteMsg.body as Map<String, dynamic>,
          channelId: channelRow.id,
          senderId: localSenderId,
          remoteCreatedAt: Value(DateTime.fromMillisecondsSinceEpoch(remoteMsg.meta.createdAt)),
          updatedAt: Value(DateTime.now()),
        ));
      }
    });
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