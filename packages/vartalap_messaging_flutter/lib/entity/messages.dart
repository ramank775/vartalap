import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/converter/map_converter.dart';
import 'package:vartalap_messaging_flutter/entity/entity.dart';
import 'package:vartalap_messaging_flutter/models/message.dart';

@UseRowClass(ChatMessage)
class Messages extends Table {
  IntColumn get id => integer()();
  TextColumn get rid => text().nullable()();
  TextColumn get type => textEnum<MessageType>()();
  TextColumn get state => textEnum<MessageState>()();
  TextColumn get payload => text().map(MapConverter())();

  IntColumn get channelId => integer().references(
        Channels,
        #id,
        onDelete: KeyAction.cascade,
      )();
  IntColumn get senderId => integer().references(
        Contacts,
        #id,
        onDelete: KeyAction.cascade,
      )();

  DateTimeColumn get localCreatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get remoteCreatedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  Expression<DateTime> get createdAt => coalesce([
        localCreatedAt,
        remoteCreatedAt,
        currentDateAndTime,
      ]);

  @override
  Set<Column> get primaryKey => {id};
}
