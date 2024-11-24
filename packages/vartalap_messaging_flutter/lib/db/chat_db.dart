import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../converter/converter.dart';
import '../entity/entity.dart';

part 'chat_db.g.dart';

@DriftDatabase(tables: [Channels, Contacts, Members, Messages])
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
    return LazyDatabase(() async {
      final dbDir = await getApplicationDocumentsDirectory();
      final path = join(dbDir.path, 'db_$userId.sqlite');
      return NativeDatabase(File(path));
    });
  }
}
