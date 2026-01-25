import 'package:drift/drift.dart';
import 'package:vartalap_messaging_flutter/entity/assests.dart';
import 'package:vartalap_messaging_flutter/entity/messages.dart';

class MessageAssets extends Table {
  IntColumn get messageId => integer().references(Messages, #id, onDelete: KeyAction.cascade)();
  IntColumn get assetId => integer().references(Assests, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {messageId, assetId};
}
