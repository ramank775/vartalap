// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'channel_dao.dart';

// ignore_for_file: type=lint
mixin _$ChannelDaoMixin on DatabaseAccessor<ChatDatabase> {
  $ChannelsTable get channels => attachedDatabase.channels;
  $ContactsTable get contacts => attachedDatabase.contacts;
  $MembersTable get members => attachedDatabase.members;
  ChannelDaoManager get managers => ChannelDaoManager(this);
}

class ChannelDaoManager {
  final _$ChannelDaoMixin _db;
  ChannelDaoManager(this._db);
  $$ChannelsTableTableManager get channels =>
      $$ChannelsTableTableManager(_db.attachedDatabase, _db.channels);
  $$ContactsTableTableManager get contacts =>
      $$ContactsTableTableManager(_db.attachedDatabase, _db.contacts);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db.attachedDatabase, _db.members);
}
