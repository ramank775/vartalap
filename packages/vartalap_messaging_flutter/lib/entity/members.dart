import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/entity/channel.dart';
import 'package:vartalap_messaging_flutter/entity/contacts.dart';

@DataClassName("MemberEntity")
class Members extends Table {
  TextColumn get memberId => text().references(
        Contacts,
        #username,
        onUpdate: KeyAction.cascade,
      )();
  Column<int> get channelId => integer().references(
        Channels,
        #id,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get role => text().nullable()();
  DateTimeColumn get since => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {channelId, memberId};
}
