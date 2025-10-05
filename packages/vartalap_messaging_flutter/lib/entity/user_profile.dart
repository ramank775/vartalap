import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

@UseRowClass(Profile, constructor: 'fromDb')
class UserProfiles extends Table {
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get email => text()();
  TextColumn get image => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId};
}
