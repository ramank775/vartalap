/// One local database per account (AUTH_CONTRACT §8.4): the file naming
/// and moves in `account_db.dart`, and the swap `AppServices` makes at
/// login and logout.
library vartalap.services.account_db_test;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/main.dart';
import 'package:vartalap/services/account_db.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const alice = 'a11ce0001';
const bob = 'b0b000002';

void main() {
  // The file moves are about files, so a scratch dir with placeholder
  // files — no SQLite ever opens one.
  late Directory dir;
  setUp(() async =>
      dir = await Directory.systemTemp.createTemp('vartalap_accounts'));
  tearDown(() => dir.delete(recursive: true));

  Set<String> files() =>
      dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
  void touch(String name) => File('${dir.path}/$name').writeAsStringSync('');

  group('account files', () {
    test('one file per user_id, which cannot leave the dir', () {
      expect(accountDbPath('/d', alice), '/d/vartalap_v3_a11ce0001.db');
      expect(accountDbPath('/d', '../x'), '/d/vartalap_v3____x.db');
    });

    test('the legacy file and its siblings become the restored user\'s',
        () async {
      touch('vartalap_v3.db');
      touch('vartalap_v3.db-wal');
      await migrateLegacyDb(dir.path, alice);
      expect(files(), {'vartalap_v3_$alice.db', 'vartalap_v3_$alice.db-wal'});
    });

    test('with no one signed in the legacy file is deleted', () async {
      touch('vartalap_v3.db');
      touch('vartalap_v3.db-shm');
      await migrateLegacyDb(dir.path, null);
      expect(files(), isEmpty);
    });

    test('nothing to migrate is not an error', () async {
      await migrateLegacyDb(dir.path, alice);
      expect(files(), isEmpty);
    });

    test('deleting an account removes its file and siblings only', () async {
      touch('vartalap_v3_$alice.db');
      touch('vartalap_v3_$alice.db-wal');
      touch('vartalap_v3_$bob.db');
      await deleteAccountDb(dir.path, alice);
      expect(files(), {'vartalap_v3_$bob.db'});
    });
  });

  group('AppServices accounts', () {
    late AppServices services;
    // Each account's database is a `memdb` one named by its path, which
    // every connection in the process shares; the keeper connection holds
    // it across the close and reopen a logout and a later login make, as
    // the file would. The empty file at the path stands in for that file
    // (and spares sqflite creating a parent dir for the URI).
    final keepers = <String, Database>{};
    final opened = <String>[];

    setUp(() {
      final client = AuthClient(baseUrl: Uri.parse('http://127.0.0.1:9'));
      services = AppServices(
        authClient: client,
        authService: AuthService(client: client, storage: _NoStorage()),
        wsTransport:
            WsTransport(endpoint: Uri.parse('ws://127.0.0.1:9'), auth: client),
        restTransport: RestTransport(baseUrl: client.baseUrl, auth: client),
        pushService: PushService(authClient: client),
        consentAccepted: true,
        pushPromptSeen: true,
        dbDir: dir.path,
        openDb: (path) async {
          opened.add(path);
          File(path).createSync();
          final uri = 'file:$path?vfs=memdb';
          keepers[path] ??= await databaseFactoryFfi.openDatabase(uri,
              options: OpenDatabaseOptions(singleInstance: false));
          return ChatStore.open(path: uri);
        },
      );
    });

    tearDown(() async {
      await services.closeAccount();
      for (final k in keepers.values) {
        await k.close();
      }
      keepers.clear();
      opened.clear();
    });

    Future<void> addContact() => services.store!
        .upsertContact(userId: 'c0ffee003', username: 'carol', nowMs: 1);
    Future<List<String?>> contacts() async =>
        (await services.store!.fetchContacts()).map((c) => c.username).toList();

    test('logout keeps the store; the same user finds it again', () async {
      await services.openAccount(alice, adoptGroups: false);
      await addContact();
      final first = services.store!;

      await services.closeAccount();
      expect(first.db.isOpen, isFalse);
      expect([services.store, services.scheduler, services.inboundReceiver],
          everyElement(isNull),
          reason: 'nothing is left to write to the closed store');
      expect(files(), {'vartalap_v3_$alice.db'});

      await services.openAccount(alice, adoptGroups: false);
      expect(await contacts(), ['carol']);
      expect(opened, everyElement(accountDbPath(dir.path, alice)));
    });

    test('another user gets an empty store of their own', () async {
      await services.openAccount(alice, adoptGroups: false);
      await addContact();
      await services.closeAccount();

      await services.openAccount(bob, adoptGroups: false);
      expect(await contacts(), isEmpty);
      expect(opened.last, accountDbPath(dir.path, bob));
    });

    test('deleting the account erases its file', () async {
      await services.openAccount(alice, adoptGroups: false);
      touch('vartalap_v3_$alice.db-wal');
      touch('vartalap_v3_$bob.db');

      await services.closeAccount(erase: true);
      expect(files(), {'vartalap_v3_$bob.db'});
    });
  });
}

class _NoStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}
