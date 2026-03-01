import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:taskq/taskq.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart' hide Task;
import 'package:vartalap_messaging_flutter/events/vartalap_task.dart';

class SyncContactsTask extends VartalapTask<void> {
  static const name = 'sync-contacts';

  SyncContactsTask(
    VartalapChatClient client,
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
    // 1. Get all local contacts
    final localContacts = await db.select(db.contacts).get();
    if (localContacts.isEmpty) return;

    // 2. Extract phone numbers for sync
    final phoneNumbers = localContacts
        .where((c) => c.phone != null)
        .map((c) => c.phone!)
        .toList();

    if (phoneNumbers.isEmpty) return;

    // 3. Sync with backend — returns { phone: uid } for onboarded contacts
    final phoneToUid = await client.syncContactBook(phoneNumbers);

    // 4. Update local contacts with real server UIDs
    await db.transaction(() async {
      for (final entry in phoneToUid.entries) {
        final phone = entry.key;
        final uid = entry.value;
        await (db.update(db.contacts)
              ..where((tbl) => tbl.phone.equals(phone)))
            .write(ContactsCompanion(
          uid: Value(uid),
          username: Value(uid), // username defaults to uid until profile fetch
        ));
      }
    });

    debugPrint('[SYNC] Synchronized ${phoneToUid.length} contacts with real UIDs');
  }

  @override
  void deserializePayload(String rawPayload) {}

  @override
  String serializePayload() => '';
}
