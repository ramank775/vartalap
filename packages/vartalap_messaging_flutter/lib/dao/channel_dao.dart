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
    final query = select(channels);
    if (filter != null) {
      if (filter.type != null) {
        query.where((tbl) => tbl.type.equals(filter.type!.toString()));
      }
      if (filter.name != null) {
        query.where((tbl) => tbl.extraData.like('%${filter.name}%'));
      }
    }
    return query.map((row) => row.toModel());
  }
}
