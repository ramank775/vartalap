import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DB {
  final dbName = "Chat";
  final version = 2;
  late Future<Database> _db = initDatabase();

  static final DB _singleton = DB._internal();

  factory DB() {
    return _singleton;
  }

  DB._internal();

  Future<String> _getDatabasePath(String dbName) async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, dbName);

    final dbDirectory = Directory(dirname(path));
    final isDirectoryExists = await dbDirectory.exists();
    if (!isDirectoryExists) {
      await dbDirectory.create(recursive: true);
    }
    return path;
  }

  Future<Database> initDatabase() async {
    final path = await _getDatabasePath(dbName);
    var db = await openDatabase(
      path,
      version: version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return db;
  }

  Future<void> _onCreate(Database db, dynamic version) async {
    var batch = db.batch();
    batch.execute("PRAGMA foreign_keys = ON;");
    batch.execute("""CREATE TABLE user (
      username TEXT PRIMARY KEY,
      name TEXT,
      pic TEXT,
      hasAccount NUMBER,
      status NUMBER DEFAULT 0
    );""");

    batch.execute("""CREATE TABLE chat (
      id TEXT PRIMARY KEY,
      title TEXT,
      pic TEXT,
      type NUMBER DEFAULT 1,
      createdOn int
     );""");

    batch.execute("""CREATE TABLE chat_user (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userid TEXT,
      chatid TEXT,
      role NUMBER DEFAULT 1,
      FOREIGN KEY(chatid) REFERENCES chat(id),
      FOREIGN KEY(userid) REFERENCES user(username)
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
      FOREIGN KEY(senderid) REFERENCES user(username)
    );""");

    batch.execute("""CREATE TABLE out_message (
      id int PRIMARY KEY,
      messageId TEXT,
      message TEXT,
      sent NUMBER,
      created_ts NUMBER,
      sent_ts NUMBER,
      retry_count NUMBER DEFAULT 0
    );""");
    batch.commit();
  }

  Future<void> _onUpgrade(Database db, int current, int next) async {
    if (next == 2) {
      await db.execute("""
        ALTER TABLE user
          ADD status NUMBER DEFAULT 0;
      """);
    }
  }

  Future<Database> getDb() async {
    return _db;
  }
}
