import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

import '../converter/converter.dart';
import '../entity/entity.dart';
import '../dao/dao.dart';

part 'chat_db.g.dart';

@DriftDatabase(tables: [
  Assests,
  Channels,
  Contacts,
  Members,
  Messages,
], daos: [
  ChatDao,
  ChannelDao,
])
class ChatDatabase extends _$ChatDatabase {
  String userId;
  ChatDatabase({
    required this.userId,
    bool inMemory = false,
  }) : super(_openConnection(userId: userId, isMemory: inMemory));

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection({
    required String userId,
    bool isMemory = false,
  }) {
    if (isMemory) {
      return NativeDatabase.memory();
    }
    return driftDatabase(name: 'db_$userId');
    // return LazyDatabase(() async {
    //   final dbDir = await getApplicationDocumentsDirectory();
    //   final path = join(dbDir.path, 'db_$userId.sqlite');
    //   return NativeDatabase(File(path));
    // });
  }
}
