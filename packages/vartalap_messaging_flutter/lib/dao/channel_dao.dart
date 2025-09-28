import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/entity/entity.dart';
import 'package:vartalap_messaging_flutter/mapper/mapper.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

part 'channel_dao.g.dart';

/// ChannelDao - Channel and Contact Operations
/// 
/// RESPONSIBILITIES:
/// - All channel CRUD operations (create, read, update, delete)
/// - Contact management and synchronization
/// - Channel filtering and querying
/// - Batch operations for performance
/// 
/// DESIGN PRINCIPLES:
/// - NO hardcoded data - all data comes from parameters
/// - Atomic operations with proper transaction handling
/// - Efficient batch operations for bulk inserts
/// - Clean separation from business logic
/// 
/// CONTACT SYNC PATTERN:
/// - UI layer provides contacts (from device, server, or manual input)
/// - DAO layer handles database operations only
/// - Supports both full sync and incremental updates
/// 
/// USAGE EXAMPLES:
/// ```dart
/// // Create channel with members
/// final channel = await channelDao.createChannel(channelModel, members);
/// 
/// // Sync contacts from UI layer
/// final deviceContacts = await getDeviceContacts(); // UI responsibility
/// await channelDao.syncContacts(deviceContacts);
/// 
/// // Watch channels reactively
/// channelDao.getChannels().watch().listen((channels) {
///   // UI updates automatically
/// });
/// ```
@DriftAccessor(tables: [Channels, Contacts, Members])
class ChannelDao extends DatabaseAccessor<ChatDatabase> with _$ChannelDaoMixin {
  ChannelDao(super.db);

  Selectable<ChannelModel> getChannels({
    ChannelFilter? filter,
  }) {
    var query = select(channels);

    if (filter != null) {
      // Build where conditions
      Expression<bool>? whereCondition;

      if (filter.type != null) {
        whereCondition = channels.type.equals(filter.type!.name);
      }

      if (filter.name != null) {
        final nameCondition = channels.extraData.like('%${filter.name}%');
        whereCondition = whereCondition == null ? nameCondition : whereCondition & nameCondition;
      }

      if (filter.memberIds != null && filter.memberIds!.isNotEmpty) {
        // For member filtering, we need a subquery approach
        final memberSubquery = selectOnly(members)
          ..addColumns([members.channelId])
          ..where(members.memberId.isIn(filter.memberIds!));

        final memberCondition = channels.id.isInQuery(memberSubquery);
        whereCondition = whereCondition == null ? memberCondition : whereCondition & memberCondition;
      }

      if (whereCondition != null) {
        query.where((tbl) => whereCondition!);
      }
    }

    return query.map((row) => row.toModel());
  }

  Future<ChannelModel> createChannel(ChannelModel channel, List<Member> channelMembers) async {
    return await transaction(() async {
      final channelComp = ChannelsCompanion.insert(
        type: channel.type,
        config: const Value({}),
        extraData: Value(channel.extraData),
      );
      final insertedChannel = await into(channels).insertReturning(channelComp);
      
      await batch((batch) {
        final rows = channelMembers.map(
          (member) => MembersCompanion.insert(
            memberId: member.user.id,
            channelId: insertedChannel.id,
          ),
        );
        if (rows.isNotEmpty) {
          batch.insertAll(members, rows);
        }
      });
      
      return insertedChannel.toModel();
    });
  }

  Future<void> updateChannel(ChannelModel channel) async {
    await (update(channels)..where((tbl) => tbl.id.equals(channel.id))).write(
      ChannelsCompanion(
        extraData: Value(channel.extraData),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteChannel(int channelId) async {
    await (delete(channels)..where((tbl) => tbl.id.equals(channelId))).go();
  }

  Selectable<Contact> getContacts({ContactFilter? filter}) {
    var query = select(contacts);

    if (filter != null) {
      // Build where conditions properly
      Expression<bool>? whereCondition;

      if (filter.name != null) {
        whereCondition = contacts.extraData.like('%${filter.name}%');
      }

      if (filter.phone != null) {
        final phoneCondition = contacts.phone.like('%${filter.phone}%');
        whereCondition = whereCondition == null ? phoneCondition : whereCondition & phoneCondition;
      }

      if (filter.status != null) {
        final statusCondition = contacts.status.equals(filter.status!.name);
        whereCondition = whereCondition == null ? statusCondition : whereCondition & statusCondition;
      }

      if (filter.username != null) {
        final usernameCondition = contacts.username.like('%${filter.username}%');
        whereCondition = whereCondition == null ? usernameCondition : whereCondition & usernameCondition;
      }

      if (whereCondition != null) {
        query.where((tbl) => whereCondition!);
      }
    }

    return query;
  }

  Future<void> addContacts(List<Contact> contactList) async {
    await transaction(() async {
      await batch((batch) {
        final companions = contactList.map(
          (contact) => ContactsCompanion.insert(
            id: Value(contact.id),
            name: Value(contact.name),
            phone: Value(contact.phone),
            username: Value(contact.username),
            status: contact.status,
            extraData: Value(contact.extraData),
            photo: Value(contact.photo),
          ),
        );
        batch.insertAll(contacts, companions);
      });
    });
  }

  Future<void> syncContacts(List<Contact> contactList) async {
    await transaction(() async {
      // Use insertAll with onConflict to handle updates properly
      await batch((batch) {
        final companions = contactList.map(
          (contact) => ContactsCompanion.insert(
            id: Value(contact.id),
            name: Value(contact.name),
            phone: Value(contact.phone),
            username: Value(contact.username),
            status: contact.status,
            extraData: Value(contact.extraData),
            photo: Value(contact.photo),
          ),
        );
        batch.insertAll(contacts, companions, mode: InsertMode.insertOrReplace);
      });
    });
  }
}
