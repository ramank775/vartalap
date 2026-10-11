/// v2 chats are not imported into v3, but they are kept: on launch v2's
/// DB moves into v3's documents dir as is, and the user can save a copy of
/// it from the relaunch screen or Settings.
library vartalap.services.v2_archive;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _v2DbName = 'Chat';
const _sidecars = ['', '-journal', '-wal', '-shm'];

Future<File> _archivedDb() async {
  final docs = await getApplicationDocumentsDirectory();
  return File('${docs.path}/v2_archive/$_v2DbName');
}

/// Moves v2's DB (`getDatabasesPath()/Chat`: the app's `databases/` dir on
/// Android, a sibling of path_provider's `app_flutter/`; Documents on iOS)
/// into `<documents>/v2_archive/`. Sidecars keep their names so a hot
/// journal still matches its DB. Safe to call on every launch.
Future<void> archiveV2Data() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final src =
        Platform.isAndroid ? '${docs.parent.path}/databases' : docs.path;
    final dest = (await _archivedDb()).parent;
    for (final s in _sidecars) {
      final f = File('$src/$_v2DbName$s');
      if (!await f.exists()) continue;
      await dest.create(recursive: true);
      await f.rename('${dest.path}/$_v2DbName$s');
    }
  } catch (_) {}
}

/// True only when a v2 install left chats behind.
Future<bool> hasV2Data() async {
  try {
    return await (await _archivedDb()).exists();
  } catch (_) {
    return false;
  }
}

/// Asks where to save a copy of the v2 DB (the system "Save as" picker)
/// and reports the outcome in a snackbar.
Future<void> saveV2Chats(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final archived = await _archivedDb();
    // VACUUM INTO writes one consistent file, so changes still sitting in
    // a -wal or journal sidecar make it into the copy.
    final snapshot = File('${archived.parent.path}/export.db');
    if (await snapshot.exists()) await snapshot.delete();
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      archived.path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await db.execute('VACUUM INTO ?', [snapshot.path]);
    } finally {
      await db.close();
    }
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: 'Save your v2 chats',
      fileName: 'vartalap-v2-chats.db',
      bytes: await snapshot.readAsBytes(),
    );
    await snapshot.delete();
    if (saved != null) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Saved your v2 chats')));
    }
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('Could not save your v2 chats: $e')));
  }
}
