import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/entity/entity.dart';
import 'package:vartalap_messaging_flutter/mapper/mapper.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

part 'channel_dao.g.dart';

@DriftAccessor(tables: [Channels, Contacts, Members])
class ChannelDao extends DatabaseAccessor<ChatDatabase> with _$ChannelDaoMixin {
  ChannelDao(super.db);

  Selectable<ChannelModel> getChannels({
    ChannelFilter? filter,
  }) {
    var query = select(channels).join([]);
    if (filter != null) {
      if (filter.type != null) {
        query.where(channels.type.equals(filter.type!.toString()));
      }
      if (filter.name != null) {
        query.where(channels.extraData.like('%${filter.name}%'));
      }
      if (filter.memberIds != null && filter.memberIds!.isNotEmpty) {
        query = query.join([
          innerJoin(
            members,
            members.channelId.equalsExp(channels.id),
          ),
        ])
          ..where(members.memberId.isIn(filter.memberIds!));
      }
    }
    return query.map((row) => row.readTable(channels).toModel());
  }
}
