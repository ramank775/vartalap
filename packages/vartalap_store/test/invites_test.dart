import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';

// Decisions 219-221: the phone's mirror of invites and connections.

const _me = '0aaaaaaa1';
const _ravi = '0bbbbbbb2';
const _li = '0ccccccc3';
const _dm = 'd0000000000000000000000000000001';
const _group = '01efabcd-7000-8000-8abc-000000000001';

void main() {
  late ChatStore store;

  setUp(() async => store = await ChatStore.open(path: inMemoryDatabasePath));
  tearDown(() async => store.close());

  test('until the server is heard every pair counts as connected', () async {
    expect((await store.peerLink(_me, _ravi)).connected, isTrue);
    expect(await store.connectedUsers(), isNull, reason: 'pickers list everyone');
    await store.replaceConnections(connected: [_li], blocked: [], invites: []);
    expect(await store.connectedUsers(), {_li});
    expect((await store.peerLink(_me, _ravi)).connected, isFalse);
    expect((await store.peerLink(_me, _li)).connected, isTrue);
  });

  test('a snapshot replaces what was there; a group invite is not a 1:1 one',
      () async {
    await store.putInvite(const InviteRow(
        channelId: 'stale', toUser: _me, fromUser: _li, createdAt: 1));
    await store.replaceConnections(
      connected: [_li],
      blocked: [_ravi],
      invites: const [
        InviteRow(channelId: _dm, toUser: _me, fromUser: _ravi, createdAt: 2),
        InviteRow(
            channelId: _group,
            toUser: _li,
            fromUser: _me,
            name: 'Family',
            createdAt: 3),
      ],
    );
    final invites = await store.fetchInvites();
    expect([for (final i in invites) i.channelId], [_dm, _group]);
    expect(invites.last.isGroup, isTrue);
    expect(invites.first.isGroup, isFalse);
    expect(await store.blockedUsers(), {_ravi});
    expect(await store.connectedUsers(), {_li});

    final ravi = await store.peerLink(_me, _ravi);
    expect((ravi.blocked, ravi.inviteReceived, ravi.inviteSent),
        (true, true, false));
    final li = await store.peerLink(_me, _li);
    expect(li.inviteSent, isFalse, reason: 'a group invite, not a 1:1 one');
  });

  test('removeInvites takes one invitee, or the whole channel', () async {
    for (final to in [_ravi, _li]) {
      await store.putInvite(InviteRow(
          channelId: _group, toUser: to, fromUser: _me, createdAt: 1));
    }
    await store.removeInvites(_group, toUser: _ravi);
    expect([for (final i in await store.fetchInvites()) i.toUser], [_li]);
    await store.removeInvites(_group);
    expect(await store.fetchInvites(), isEmpty);
  });

  test('setConnection keeps what it is not given; watchTables re-emits',
      () async {
    final links = store.watchTables(const {'connections'},
        () => store.peerLink(_me, _ravi)).asBroadcastStream();
    expect((await links.first).blocked, isFalse);
    final blocked = links.firstWhere((l) => l.blocked);
    await store.setConnection(_ravi, connected: true);
    await store.setConnection(_ravi, blocked: true);
    final link = await blocked.timeout(const Duration(seconds: 2));
    expect(link.connected, isTrue);
  });
}
