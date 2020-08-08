import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DB {
  final dbName = "Chat";
  final version = 1;
  static Database _db;

  Future<String> _getDatabasePath(String dbName) async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, dbName);

    final dbDirectory = Directory(dirname(path));
    final isDirectoryExists = await dbDirectory.exists();
    print("Directory exists $isDirectoryExists");
    if (!isDirectoryExists) {
      await dbDirectory.create(recursive: true);
    }
    return path;
  }

  Future<void> initDatabase() async {
    final path = await _getDatabasePath(dbName);
    print("DB  path: $path");

    _db = await openDatabase(path, version: version, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, dynamic version) async {
    var batch = db.batch();
    batch.execute("PRAGMA foreign_keys = OFF;");
    batch.execute("""CREATE TABLE user (
      username TEXT PRIMARY KEY,
      name TEXT,
      pic TEXT,
      hasAccount NUMBER
    );""");

    batch.execute("""CREATE TABLE chat (
      id TEXT PRIMARY KEY,
      text TEXT,
      pic TEXT,
      type NUMBER DEFAULT 1,
      createdOn int
     );""");

    batch.execute("""CREATE TABLE chat_user (
      id TEXT PRIMARY KEY,
      chatid TEXT,
      role NUMBER DEFAULT 1,
      FOREIGN KEY(chatid) REFERENCES chat(id)
    );""");

    batch.execute("""CREATE TABLE message (
      id TEXT PRIMARY KEY,
      chatid TEXT,
      senderid TEXT,
      text TEXT,
      state NUMBER DEFAULT 1,
      type NUMBER DEFAULT 1,
      ts NUMBER,
      FOREIGN KEY(chatid) REFERENCES chat(id),
      FOREIGN KEY(senderid) REFERENCES chat_user(username)
    );""");
    batch.execute("PRAGMA foreign_keys = ON;");
    batch.commit();
  }

  Future<Database> getDb() async {
    if (_db == null) {
      await initDatabase();
    }
    return _db;
  }
}
