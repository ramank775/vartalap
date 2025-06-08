import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';

import 'package:vartalap_messaging_flutter/entity/entity.dart';
import 'package:vartalap_messaging_flutter/mapper/mapper.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

part 'chat_dao.g.dart';

@DriftAccessor(tables: [Channels, Contacts, Members, Messages])
class ChatDao extends DatabaseAccessor<ChatDatabase> with _$ChatDaoMixin {
  ChatDao(super.db);

  Selectable<ChatPreview> getChatPreviews({
    ChannelFilter? filter,
  }) {
    final query = select(channels).join([
      innerJoin(
        messages,
        messages.id.isInQuery(select(messages)
          ..where((tbl) => tbl.channelId.equalsExp(channels.id))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.localCreatedAt)])
          ..limit(1)),
      ),
      leftOuterJoin(
        contacts,
        contacts.id.equalsExp(messages.senderId),
      ),
    ]);

    return query.asyncMap((row) async {
      final channel = row.readTable(channels).toModel();
      final sender = row.readTable(contacts);
      final lastMessage = row.readTable(messages).toModel(sender: sender);
      final unReadCountExp = messages.id.count().cast<int>();
      final unreadQuery = selectOnly(messages)
        ..addColumns([unReadCountExp])
        ..where(messages.channelId.equals(channel.id))
        ..limit(10);
      final unreadCount = await unreadQuery
              .map((row) => row.read(unReadCountExp))
              .getSingleOrNull() ??
          0;

      return ChatPreview(
        channel: channel,
        unreadCount: unreadCount,
        lastMessage: lastMessage,
      );
    });
  }
}
