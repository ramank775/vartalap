// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_dao.dart';

// ignore_for_file: type=lint
mixin _$ChatDaoMixin on DatabaseAccessor<ChatDatabase> {
  $ChannelsTable get channels => attachedDatabase.channels;
  $ContactsTable get contacts => attachedDatabase.contacts;
  $MembersTable get members => attachedDatabase.members;
  $MessagesTable get messages => attachedDatabase.messages;
  ChatDaoManager get managers => ChatDaoManager(this);
}

class ChatDaoManager {
  final _$ChatDaoMixin _db;
  ChatDaoManager(this._db);
  $$ChannelsTableTableManager get channels =>
      $$ChannelsTableTableManager(_db.attachedDatabase, _db.channels);
  $$ContactsTableTableManager get contacts =>
      $$ContactsTableTableManager(_db.attachedDatabase, _db.contacts);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db.attachedDatabase, _db.members);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db.attachedDatabase, _db.messages);
}
