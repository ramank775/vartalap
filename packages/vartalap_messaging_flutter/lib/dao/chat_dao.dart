import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';

import 'package:vartalap_messaging_flutter/entity/entity.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart' show ChannelType;


part 'chat_dao.g.dart';

/// ChatDao - Message and Member Operations
///
/// RESPONSIBILITIES:
/// - All message CRUD operations (create, read, update, delete)
/// - Member management within channels
/// - Message state transitions (pending -> sent -> delivered -> read)
/// - Chat preview generation with last message and unread counts
///
/// DESIGN PRINCIPLES:
/// - Pure database operations - no business logic
/// - All methods are atomic (use transactions when needed)
/// - Return Drift Selectable for reactive queries
/// - Handle optimistic updates with proper state management
///
/// MESSAGE STATE FLOW:
/// pending -> sent -> delivered -> read
///
/// USAGE PATTERN:
/// ```dart
/// // Send message
/// final messageId = await chatDao.sendMessage(message, channel);
///
/// // Watch messages reactively
/// chatDao.getMessages(channel: channel).watch().listen((messages) {
///   // UI updates automatically
/// });
/// ```
@DriftAccessor(tables: [Channels, Contacts, Members, Messages])
class ChatDao extends DatabaseAccessor<ChatDatabase> with _$ChatDaoMixin {
  ChatDao(super.db);

  Selectable<ChatPreview> getChatPreviews({
    required int currentUserId,
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
    ])
      ..where(
        FunctionCallExpression(
            "json_extract", [channels.config, const Constant('\$.isArchived')]).isNull() |
            FunctionCallExpression(
                "json_extract", [channels.config, const Constant('\$.isArchived')]).equalsExp(const Constant(0)),
      );

    query.orderBy([
      OrderingTerm(
        expression: FunctionCallExpression(
            "json_extract", [channels.config, const Constant('\$.isPinned')]),
        mode: OrderingMode.desc,
      ),
      OrderingTerm.desc(
          // Coalesce: Use message.createdAt if exists, else channel.createdAt
          FunctionCallExpression(
              'COALESCE', [messages.createdAt, channels.createdAt]))
    ]);

    return query.asyncMap((row) => _buildChatPreview(row, currentUserId));
  }

  Future<ChatPreview> _buildChatPreview(TypedResult row, int currentUserId) async {
    final channel = row.readTable(channels);
    final sender = row.readTableOrNull(contacts);
    final msgTable = row.readTableOrNull(messages);
    final lastMessage = msgTable?.copyWith(sender: sender);
    final unReadCountExp = messages.id.count().cast<int>();
    final unreadQuery = selectOnly(messages)
      ..addColumns([unReadCountExp])
      ..where(messages.channelId.equals(channel.id) &
          messages.state.isNotValue(MessageState.read.name))
      ..limit(10);
    final unreadCount = await unreadQuery
            .map((row) => row.read(unReadCountExp))
            .getSingleOrNull() ??
        0;

    String? displayImage = channel.displayImage;
    ChannelModel displayChannel = channel;
    if (channel.type == ChannelType.individual) {
      final membersQuery = select(members).join([
        innerJoin(contacts, contacts.id.equalsExp(members.memberId)),
      ])
        ..where(members.channelId.equals(channel.id) &
            members.memberId.isNotValue(currentUserId))
        ..limit(1);

      final otherMemberRow = await membersQuery.getSingleOrNull();
      if (otherMemberRow != null) {
        final otherContact = otherMemberRow.readTable(contacts);
        displayImage = otherContact.photo;
        if (otherContact.displayName.isNotEmpty) {
          displayChannel = ChannelModel(
            id: channel.id,
            type: channel.type,
            cid: channel.cid,
            taskId: channel.taskId,
            extraData: {...?channel.extraData, 'name': otherContact.displayName},
            config: channel.config,
            muted: channel.muted,
            createdAt: channel.createdAt,
            updatedAt: channel.updatedAt,
            deletedAt: channel.deletedAt,
          );
        }
      }
    }

    return ChatPreview(
      channel: displayChannel,
      unreadCount: unreadCount,
      lastMessage: lastMessage,
      displayImage: displayImage,
      isMe: lastMessage?.senderId == currentUserId,
    );
  }

  Selectable<ChatPreview> getArchivedChatPreviews({
    required int currentUserId,
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
    ])
      ..where(
        FunctionCallExpression(
            "json_extract", [channels.config, const Constant('\$.isArchived')]).equalsExp(const Constant(1)),
      );

    query.orderBy([
      OrderingTerm.desc(
          // Coalesce: Use message.createdAt if exists, else channel.createdAt
          FunctionCallExpression(
              'COALESCE', [messages.createdAt, channels.createdAt]))
    ]);

    return query.asyncMap((row) => _buildChatPreview(row, currentUserId));
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
      await (delete(members)
            ..where((tbl) =>
                tbl.channelId.equals(channel.id) &
                tbl.memberId.equals(member.user.id)))
          .go();
    });
  }

  Selectable<ChatMessage> getMessages({
    ChannelModel? channel,
    MessageFilter? filter,
  }) {
    var query = select(messages);

    // Build where conditions properly
    Expression<bool>? whereCondition;

    if (channel != null) {
      whereCondition = messages.channelId.equals(channel.id);
    }

    if (filter != null) {
      if (filter.type != null) {
        final typeCondition = messages.type.equals(filter.type!.name);
        whereCondition = whereCondition == null
            ? typeCondition
            : whereCondition & typeCondition;
      }

      if (filter.state != null) {
        final stateCondition = messages.state.equals(filter.state!.name);
        whereCondition = whereCondition == null
            ? stateCondition
            : whereCondition & stateCondition;
      }

      if (filter.senderId != null) {
        final senderCondition = messages.senderId.equals(filter.senderId!);
        whereCondition = whereCondition == null
            ? senderCondition
            : whereCondition & senderCondition;
      }

      if (filter.messageId != null) {
        final messageIdCondition = messages.id.equals(filter.messageId!);
        whereCondition = whereCondition == null
            ? messageIdCondition
            : whereCondition & messageIdCondition;
      }
    }

    if (whereCondition != null) {
      query.where((tbl) => whereCondition!);
    }

    // Order by timestamp for consistent ordering
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);

    return query;
  }

  Future<int> sendMessage(ChatMessage message, ChannelModel channel) async {
    final companion = MessagesCompanion.insert(
      id: message.id == 0 ? const Value.absent() : Value(message.id),
      type: message.type,
      state: message.state,
      payload: message.payload,
      channelId: channel.id,
      senderId: message.senderId,
      localCreatedAt: Value(message.timestamp),
      updatedAt: Value(message.updatedAt),
    );
    return await into(messages)
        .insertReturning(companion)
        .then((msg) => msg.id);
  }

  Future<void> updateMessage(int messageId, ChatMessage updatedMessage) async {
    await (update(messages)..where((tbl) => tbl.id.equals(messageId))).write(
      MessagesCompanion(
        state: Value(updatedMessage.state),
        payload: Value(updatedMessage.payload),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteMessage(int messageId) async {
    await (delete(messages)..where((tbl) => tbl.id.equals(messageId))).go();
  }

  Future<void> markMessagesAsRead(List<int> messageIds) async {
    if (messageIds.isEmpty) return;
    await (update(messages)..where((tbl) => tbl.id.isIn(messageIds))).write(
      MessagesCompanion(
        state: const Value(MessageState.read),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markChannelAsRead(int channelId) async {
    await (update(messages)..where((tbl) => tbl.channelId.equals(channelId)))
        .write(
      MessagesCompanion(
        state: const Value(MessageState.read),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> clearChannelMessages(int channelId) async {
    await (delete(messages)..where((tbl) => tbl.channelId.equals(channelId)))
        .go();
  }

  Selectable<ChatMessage> searchMessages(String query) {
    return select(messages)
      ..where((tbl) => tbl.payload.like('%$query%'))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
  }
}
