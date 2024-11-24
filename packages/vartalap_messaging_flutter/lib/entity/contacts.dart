import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/converter/map_converter.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

@UseRowClass(Contact, constructor: 'fromDb')
class Contacts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().nullable()();
  // Remote User Id
  TextColumn get uid => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get name => text().nullable()();
  BlobColumn get thumbnail => blob().nullable()();
  TextColumn get photo => text()();
  TextColumn get extraData => text().nullable().map(NullableMapConverter())();
  TextColumn get status => textEnum<ContactStatus>()();

  Expression<String> get displayName => coalesce([
        name,
        phone,
        username,
        const Constant(''),
      ]);
  Expression<bool> get hasAccount => coalesce([
        username.isNotNull(),
        const Constant(false),
      ]);
}
