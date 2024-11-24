import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/converter/map_converter.dart';
import 'package:vartalap_messaging_flutter/entity/channel.dart';

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get state => text()();
  TextColumn get payload => text().map(MapConverter())();

  IntColumn get channelId => integer().references(
        Channels,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get senderId => text()();

  DateTimeColumn get localCreatedAt => dateTime().nullable()();
  DateTimeColumn get remoteCreatedAt => dateTime().nullable()();

  Expression<DateTime> get createdAt => coalesce([
        localCreatedAt,
        remoteCreatedAt,
        currentDateAndTime,
      ]);

  @override
  Set<Column> get primaryKey => {id};
}
