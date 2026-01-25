import 'package:drift/drift.dart';
import 'package:vartalap_messaging/core/models/event.dart';
import 'package:vartalap_messaging_flutter/converter/map_converter.dart';
import 'package:vartalap_messaging_flutter/models/channel.dart';

@UseRowClass(ChannelModel)
class Channels extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<ChannelType>()();
  // Remote Channel ID
  TextColumn get cid => text().nullable()();
  IntColumn get taskId => integer().nullable()();
  TextColumn get extraData => text().nullable().map(NullableMapConverter())();
  TextColumn get config =>
      text().withDefault(const Constant('{}')).map(MapConverter())();
  BoolColumn get muted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}
