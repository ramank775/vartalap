import 'package:drift/drift.dart';

class Assests extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text().nullable()();
  TextColumn get path => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}
