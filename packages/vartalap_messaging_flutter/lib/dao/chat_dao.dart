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
        messages.id.isInQuery(selectOnly(messages)
          ..addColumns([messages.id])
          ..where(messages.channelId.equalsExp(channels.id))
          ..orderBy([
            OrderingTerm.desc(messages.createdAt),
          ])
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

  Selectable<Member> getMembers({
    required int channelId,
  }) {
    final query = select(members).join([
      innerJoin(
        contacts,
        contacts.id.equalsExp(members.memberId),
      ),
    ])
      ..where(members.channelId.equals(channelId))
      ..orderBy([
        OrderingTerm.asc(members.since),
      ]);
    return query.map((row) => Member(
          user: row.readTable(contacts),
          role: row.readTable(members).role,
          since: row.readTable(members).since,
          updatedAt: row.readTable(members).updatedAt,
        ));
  }

  Future<void> addMembers(List<Member> members, ChannelModel channel) async {
    await transaction(() async {
      await batch((batch) {
        final rows = members.map(
          (member) => MembersCompanion.insert(
            memberId: member.user.id,
            channelId: channel.id,
          ),
        );
        batch.insertAll(this.members, rows);
      });
    });
  }

  Future<void> removeMember(Member member, ChannelModel channel) async {
    await transaction(() async {
      delete(
        members,
      ).where((tbl) =>
          tbl.channelId.equals(channel.id) &
          tbl.memberId.equals(member.user.id));
    });
  }

  Selectable<ChatMessage> getMessages({
    ChannelModel? channel,
    MessageFilter? filter,
  }) {
    final query = select(messages);
    if (channel != null) {
      query.where((tbl) => tbl.channelId.equals(channel.id));
    }
    if (filter != null) {
      if (filter.type != null) {
        query.where((tbl) => tbl.type.equals(filter.type.toString()));
      }
      if (filter.state != null) {
        query.where((tbl) => tbl.state.equals(filter.state.toString()));
      }
      if (filter.senderId != null) {
        query.where((tbl) => tbl.senderId.equals(filter.senderId!));
      }
    }
    return query.map((message) => message.toModel());
  }
}
