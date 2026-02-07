// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile_dao.dart';

// ignore_for_file: type=lint
mixin _$UserProfileDaoMixin on DatabaseAccessor<ChatDatabase> {
  $UserProfilesTable get userProfiles => attachedDatabase.userProfiles;
  UserProfileDaoManager get managers => UserProfileDaoManager(this);
}

class UserProfileDaoManager {
  final _$UserProfileDaoMixin _db;
  UserProfileDaoManager(this._db);
  $$UserProfilesTableTableManager get userProfiles =>
      $$UserProfilesTableTableManager(_db.attachedDatabase, _db.userProfiles);
}
