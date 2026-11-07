/// Last seen by labels (SYNC_PROTOCOL §22, decision 226): the phone
/// resolves the picked labels to user ids, the server gets only those,
/// and gets them again whenever a label's people change.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const _self = 'abcdef012';
const _asha = '00000000b';
const _ravi = '00000000c';

Future<(ChatService, List<Map<String, dynamic>>, void Function(bool))>
    _rig() async {
  SharedPreferences.setMockInitialValues({});
  final patches = <Map<String, dynamic>>[];
  var offline = false;
  final client = MockClient((req) async {
    if (offline) throw http.ClientException('offline');
    if (req.method == 'PATCH' && req.url.path == '/v3.0/users/me') {
      patches.add(jsonDecode(req.body) as Map<String, dynamic>);
    }
    return http.Response('{}', 200);
  });
  final store = await ChatStore.open(path: inMemoryDatabasePath);
  addTearDown(store.close);
  final chat = ChatService(
    store: store,
    scheduler: SyncScheduler(
      store: store,
      wsTransport: _Offline(),
      restTransport: _Offline(),
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
    ),
    authClient: AuthClient(
        baseUrl: Uri.parse('http://api.invalid'), httpClient: client)
      ..restoreSession(accesskey: 'sk', userId: _self),
    wsTransport: WsTransport(
      endpoint: Uri.parse('ws://example.invalid/wss'),
      auth: AuthClient(baseUrl: Uri.parse('http://example.invalid')),
    ),
    uuidGen: Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(_self)),
    clock: Clock.system,
  );
  addTearDown(chat.stopPresence);
  return (chat, patches, (bool v) => offline = v);
}

/// Let the change feed's listener run its query and request.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  setUpAll(sqfliteFfiInit);

  test('only: the labels go to the server as their people, never a name',
      () async {
    final (chat, patches, _) = await _rig();
    final labels = await chat.fetchLabels();
    final family = labels.firstWhere((l) => l.name == 'Family');
    final close = labels.firstWhere((l) => l.name == 'Close');
    await chat.setLabelMembers(family.labelId, {_ravi, _asha});
    await chat.setLabelMembers(close.labelId, {_asha});
    await _settle();
    expect(patches, isEmpty, reason: 'no label setting yet: nothing to send');

    await chat.setPresence('only', {family.labelId, close.labelId});
    expect(patches.single, {
      'presence': 'only',
      'presenceUsers': [_asha, _ravi],
    });
    expect(jsonEncode(patches), isNot(contains('Family')));
    final saved = await chat.presenceLabels();
    expect(saved?.mode, 'only');
    expect(saved?.labels, {family.labelId, close.labelId});
  });

  test("a label's people change: the new list goes; a rename sends nothing",
      () async {
    final (chat, patches, setOffline) = await _rig();
    final family =
        (await chat.fetchLabels()).firstWhere((l) => l.name == 'Family');
    await chat.setPresence('except', {family.labelId});
    expect(patches.single['presenceUsers'], isEmpty);

    await chat.setLabelMembers(family.labelId, {_asha});
    await _settle();
    expect(patches.last, {
      'presence': 'except',
      'presenceUsers': [_asha],
    });

    await chat.renameLabel(family.labelId, 'Home');
    await _settle();
    expect(patches, hasLength(2), reason: 'same people, nothing to send');

    setOffline(true);
    await chat.setLabelMembers(family.labelId, {_asha, _ravi});
    await _settle();
    expect(patches, hasLength(2));
    setOffline(false);
    await chat.renameLabel(family.labelId, 'Family');
    await _settle();
    expect(patches.last['presenceUsers'], [_asha, _ravi],
        reason: 'the failed send is retried on the next change');

    await chat.setPresence('contacts');
    expect(patches.last, {'presence': 'contacts'});
    expect(await chat.presenceLabels(), isNull);
    await chat.setLabelMembers(family.labelId, {});
    await _settle();
    expect(patches.last, {'presence': 'contacts'},
        reason: 'a plain setting follows no label');
  });

  test('offline: setPresence throws and keeps the old labels', () async {
    final (chat, _, setOffline) = await _rig();
    final family =
        (await chat.fetchLabels()).firstWhere((l) => l.name == 'Family');
    await chat.setPresence('only', {family.labelId});
    setOffline(true);
    await expectLater(chat.setPresence('nobody'), throwsA(anything));
    expect((await chat.presenceLabels())?.labels, {family.labelId});
  });
}

class _Offline implements Transport {
  @override
  Future<void> send(OutboundFrame frame) async {}
  @override
  Stream<AckFrame> get acks => const Stream.empty();
  @override
  Stream<TransportState> get state => const Stream.empty();
  @override
  TransportState get currentState => TransportState.disconnected;
}
