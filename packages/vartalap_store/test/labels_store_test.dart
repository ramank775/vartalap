/// Labels on the phone (decision 223): the v9 migration, label upkeep,
/// and who a timeline post to some labels reaches.
library;

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';

const _self = '00000000a';
const _asha = '00000000b';
const _ravi = '00000000c';
const _meena = '00000000d';

Future<ChatStore> _store() async {
  final store = await ChatStore.open(path: inMemoryDatabasePath);
  addTearDown(store.close);
  return store;
}

/// A chat with [members] besides us.
Future<void> _chat(
    ChatStore store, String id, String kind, List<String> members) async {
  await store.insertChannel(
      channelId: id, kind: kind, ownerUserId: _self, createdAt: 1);
  for (final u in [_self, ...members]) {
    await store.insertChannelMember(
        channelId: id, userId: u, role: 'member', joinedAt: 1);
  }
}

void main() {
  test('a new database starts with Family, Friends and Close', () async {
    final store = await _store();
    expect([for (final l in await store.fetchLabels()) l.name],
        ['Family', 'Friends', 'Close']);
  });

  test('a v8 database migrates to v9: rows kept, the defaults seeded once',
      () async {
    final dir = await Directory.systemTemp.createTemp('vartalap_v8');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v8.db';
    sqfliteFfiInit();
    final v8 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, _) => db.execute('''
            CREATE TABLE contacts (user_id TEXT PRIMARY KEY, username TEXT,
              display_name TEXT, avatar_url TEXT, status_text TEXT,
              phone_hash TEXT, contact_book_name TEXT,
              last_refreshed_ms INTEGER NOT NULL)'''),
        ));
    await v8.insert('contacts', {'user_id': _asha, 'last_refreshed_ms': 1});
    await v8.close();

    var store = await ChatStore.open(path: path);
    expect((await store.fetchContacts()).single.userId, _asha);
    final labels = await store.fetchLabels();
    expect([for (final l in labels) l.name], ['Family', 'Friends', 'Close']);

    // The user deletes a default; reopening must not bring it back.
    await store.deleteLabel(labels.first.labelId);
    await store.close();
    store = await ChatStore.open(path: path);
    addTearDown(store.close);
    expect([for (final l in await store.fetchLabels()) l.name],
        ['Friends', 'Close']);
  });

  test('labels: add, rename, delete; members set from either side', () async {
    final store = await _store();
    final emitted = <List<String>>[];
    final sub = store.watchLabels().listen(
        (ls) => emitted.add([for (final l in ls) '${l.name}:${l.userIds}']));
    addTearDown(sub.cancel);

    final cousins = await store.createLabel('Cousins');
    await store.renameLabel(cousins, 'Cousins (Pune)');
    final family = (await store.fetchLabels()).first.labelId;
    await store.setLabelMembers(family, {_asha, _ravi});
    await store.setContactLabels(_asha, {cousins});

    final byName = {
      for (final l in await store.fetchLabels()) l.name: l.userIds
    };
    expect(byName['Family'], {_ravi}, reason: 'Asha left Family');
    expect(byName['Cousins (Pune)'], {_asha});

    await store.deleteLabel(cousins);
    expect([for (final l in await store.fetchLabels()) l.name],
        ['Family', 'Friends', 'Close']);
    expect(await store.db.query('label_members'), hasLength(1),
        reason: 'a deleted label takes its tags with it');
    await Future<void>.delayed(Duration.zero);
    expect(emitted.last.first, 'Family:{$_ravi}');
  });

  test('the audience is the label members we have a 1:1 chat with', () async {
    final store = await _store();
    await _chat(store, 'd-asha', 'one_to_one', [_asha]);
    await _chat(store, 'd-ravi', 'one_to_one', [_ravi]);
    // Meena shares only a group with us: no 1:1 chat, not reachable.
    await _chat(store, 'g-1', 'group', [_meena, _asha]);
    final ids = {for (final l in await store.fetchLabels()) l.name: l.labelId};
    await store.setLabelMembers(ids['Family']!, {_asha, _meena});
    await store.setLabelMembers(ids['Friends']!, {_ravi, _asha});

    expect(await store.timelineAudience(selfUserId: _self), [_asha, _ravi]);
    expect(
        await store
            .timelineAudience(selfUserId: _self, labelIds: {ids['Family']!}),
        [_asha]);
    expect(
        await store.timelineAudience(
            selfUserId: _self, labelIds: {ids['Family']!, ids['Friends']!}),
        [_asha, _ravi],
        reason: 'one person in two labels gets the post once');
    expect(
        await store
            .timelineAudience(selfUserId: _self, labelIds: {ids['Close']!}),
        isEmpty);
  });
}
