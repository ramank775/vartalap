import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';

const _channelId = 'c-inbound-1';
const _selfUserId = '0abcdef12';
const _peerUserId = '0aabbccdd';
const _thirdUserId = '0a1b2c3d4';

void main() {
  late ChatStore store;
  late StreamController<pb.Envelope> pushes;
  late InboundReceiver receiver;
  late FakeClock clock;

  setUp(() async {
    store = await ChatStore.open(path: inMemoryDatabasePath);
    await store.insertChannel(
      channelId: _channelId,
      kind: 'one_to_one',
      ownerUserId: _selfUserId,
      createdAt: 1,
    );
    pushes = StreamController<pb.Envelope>.broadcast();
    clock = FakeClock(1000);
    receiver = InboundReceiver(
      store: store,
      pushes: pushes.stream,
      localUserId: _selfUserId,
      clock: clock,
    );
    await receiver.start();
  });

  tearDown(() async {
    await receiver.stop();
    await pushes.close();
    await store.close();
  });

  test('TYPE_MESSAGE_CREATE applies and chat list re-emits preview', () async {
    final listStream =
        store.watchChannelList().asBroadcastStream();
    // First emission is the initial empty-preview state.
    final first = await listStream.first;
    expect(first.single.lastMessagePreview, isNull);

    final nextEmit = listStream.firstWhere(
      (entries) => entries.single.lastMessagePreview == 'hi there',
    );

    pushes.add(_makeEnvelope(
      opId: 'op-create-1',
      senderUserId: _peerUserId,
      payload: _chatPayload(
        type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
        messageId: 'm-1',
        body: 'hi there',
      ),
      serverTimestampMs: 5000,
      deliverySequence: 1,
    ));

    final entries = await nextEmit.timeout(const Duration(seconds: 2));
    expect(entries.single.lastMessagePreview, 'hi there');
    expect(entries.single.lastMessageAuthor, _peerUserId);
    expect(entries.single.unreadCount, 1);

    final row = await store.fetchMessage('m-1');
    expect(row, isNotNull);
    expect(row!.body, 'hi there');
    expect(row.state, MessageState.sent);
    expect(row.serverTimestampMs, 5000);
    expect(row.deliverySequence, 1);
  });

  test('duplicate op_id is deduped (§7.2)', () async {
    final env = _makeEnvelope(
      opId: 'op-dup',
      senderUserId: _peerUserId,
      payload: _chatPayload(
        type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
        messageId: 'm-dup',
        body: 'once',
      ),
      serverTimestampMs: 6000,
      deliverySequence: 2,
    );
    pushes.add(env);
    await _settle(store, 'm-dup', present: true);

    pushes.add(env);
    await _pumpQueue();

    // Still exactly one row, exactly one op_id_seen record, unread_count
    // still 1 (not bumped twice).
    final rows = await store.db.rawQuery(
      'SELECT COUNT(*) c FROM messages WHERE message_id = ?',
      ['m-dup'],
    );
    expect(rows.single['c'], 1);
    final seen = await store.db.rawQuery(
      'SELECT COUNT(*) c FROM op_id_seen WHERE channel_id = ? AND op_id = ?',
      [_channelId, 'op-dup'],
    );
    expect(seen.single['c'], 1);
    final chan = await store.db.query(
      'channels',
      columns: const ['unread_count'],
      where: 'channel_id = ?',
      whereArgs: [_channelId],
    );
    expect(chan.single['unread_count'], 1);
  });

  test(
    'TYPE_MESSAGE_UPDATE from non-author is silently dropped '
    'but op_id_seen is recorded (§6a.4)',
    () async {
      // Seed a message authored by _peerUserId.
      pushes.add(_makeEnvelope(
        opId: 'op-seed',
        senderUserId: _peerUserId,
        payload: _chatPayload(
          type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
          messageId: 'm-gate',
          body: 'original',
        ),
        serverTimestampMs: 7000,
        deliverySequence: 3,
      ));
      await _settle(store, 'm-gate', present: true);

      // Attempt an update from _thirdUserId — gate should reject.
      pushes.add(_makeEnvelope(
        opId: 'op-bad-update',
        senderUserId: _thirdUserId,
        payload: _chatPayload(
          type: pb.ChatPayloadType.TYPE_MESSAGE_UPDATE,
          messageId: 'm-gate',
          body: 'hijacked',
        ),
        serverTimestampMs: 7100,
        deliverySequence: 4,
      ));
      await _pumpQueue();

      final row = await store.fetchMessage('m-gate');
      expect(row!.body, 'original',
          reason: 'non-author update must be silently dropped');
      expect(row.isEdited, isFalse);

      final seen = await store.db.rawQuery(
        'SELECT COUNT(*) c FROM op_id_seen '
        'WHERE channel_id = ? AND op_id = ?',
        [_channelId, 'op-bad-update'],
      );
      expect(seen.single['c'], 1,
          reason:
              'op_id_seen must record even on gate drop so re-fanout is a no-op');
    },
  );

  test('TYPE_MESSAGE_DELETE with matching authorship tombstones', () async {
    pushes.add(_makeEnvelope(
      opId: 'op-seed-del',
      senderUserId: _peerUserId,
      payload: _chatPayload(
        type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
        messageId: 'm-del',
        body: 'soon to die',
      ),
      serverTimestampMs: 8000,
      deliverySequence: 5,
    ));
    await _settle(store, 'm-del', present: true);

    pushes.add(_makeEnvelope(
      opId: 'op-del',
      senderUserId: _peerUserId,
      payload: _chatPayload(
        type: pb.ChatPayloadType.TYPE_MESSAGE_DELETE,
        messageId: 'm-del',
      ),
      serverTimestampMs: 8100,
      deliverySequence: 6,
    ));

    // Poll for tombstone flip.
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final r = await store.db.query(
        'messages',
        columns: const ['tombstoned', 'body'],
        where: 'message_id = ?',
        whereArgs: ['m-del'],
      );
      if ((r.single['tombstoned'] as int) == 1) {
        expect(r.single['body'], isNull);
        return;
      }
    }
    fail('message was not tombstoned within timeout');
  });

  test(
    'TYPE_REACTION_ADD against a missing message is silently dropped',
    () async {
      pushes.add(_makeEnvelope(
        opId: 'op-react-miss',
        senderUserId: _peerUserId,
        payload: _chatPayload(
          type: pb.ChatPayloadType.TYPE_REACTION_ADD,
          messageId: 'm-nonexistent',
          emoji: 'thumbsup',
        ),
        serverTimestampMs: 9000,
        deliverySequence: 7,
      ));
      await _pumpQueue();

      final reactions = await store.db.rawQuery(
        'SELECT COUNT(*) c FROM reactions WHERE message_id = ?',
        ['m-nonexistent'],
      );
      expect(reactions.single['c'], 0);

      final seen = await store.db.rawQuery(
        'SELECT COUNT(*) c FROM op_id_seen '
        'WHERE channel_id = ? AND op_id = ?',
        [_channelId, 'op-react-miss'],
      );
      expect(seen.single['c'], 1,
          reason: 'op_id_seen recorded even on gate drop');
    },
  );

  // --- ServerEventPayload (§10.2) -----------------------------------------

  test(
    'TYPE_CHANNEL_CREATED inserts channel + members, marks creator as owner',
    () async {
      const newChannel = 'c-grp-1';
      pushes.add(_makeEnvelope(
        channelId: newChannel,
        opId: 'op-cc-1',
        senderUserId: _peerUserId,
        payload: _serverEventChannelCreated(
          channelId: newChannel,
          kind: 'group',
          name: 'Trip',
          members: [_peerUserId, _selfUserId, _thirdUserId],
          creator: _peerUserId,
          createdAtMs: 1000,
        ),
        serverTimestampMs: 1000,
        deliverySequence: 1,
      ));
      await _settleChannel(store, newChannel, present: true);

      final chans = await store.db.query(
        'channels',
        where: 'channel_id = ?',
        whereArgs: [newChannel],
      );
      expect(chans.single['kind'], 'group');
      expect(chans.single['name'], 'Trip');
      expect(chans.single['owner_user_id'], _peerUserId);
      expect(chans.single['tombstoned'], 0);

      final members = await store.db.query(
        'channel_members',
        where: 'channel_id = ?',
        whereArgs: [newChannel],
        orderBy: 'user_id',
      );
      expect(members.length, 3);
      final byUser = {for (final m in members) m['user_id']: m};
      expect(byUser[_peerUserId]!['role'], 'owner');
      expect(byUser[_selfUserId]!['role'], 'member');
      expect(byUser[_thirdUserId]!['role'], 'member');
      for (final m in members) {
        expect(m['removed_at'], isNull);
        expect(m['joined_at'], 1000);
      }

      final seen = await store.db.rawQuery(
        'SELECT COUNT(*) c FROM op_id_seen '
        'WHERE channel_id = ? AND op_id = ?',
        [newChannel, 'op-cc-1'],
      );
      expect(seen.single['c'], 1);
    },
  );

  test('TYPE_CHANNEL_CREATED is idempotent — duplicate op_id is deduped',
      () async {
    const newChannel = 'c-grp-dup';
    final env = _makeEnvelope(
      channelId: newChannel,
      opId: 'op-cc-dup',
      senderUserId: _peerUserId,
      payload: _serverEventChannelCreated(
        channelId: newChannel,
        kind: 'group',
        name: 'Once',
        members: [_peerUserId, _selfUserId],
        creator: _peerUserId,
        createdAtMs: 1500,
      ),
      serverTimestampMs: 1500,
      deliverySequence: 1,
    );
    pushes.add(env);
    await _settleChannel(store, newChannel, present: true);

    pushes.add(env);
    await _pumpQueue();

    final chans = await store.db.rawQuery(
      'SELECT COUNT(*) c FROM channels WHERE channel_id = ?',
      [newChannel],
    );
    expect(chans.single['c'], 1);
    final members = await store.db.rawQuery(
      'SELECT COUNT(*) c FROM channel_members WHERE channel_id = ?',
      [newChannel],
    );
    expect(members.single['c'], 2);
    final seen = await store.db.rawQuery(
      'SELECT COUNT(*) c FROM op_id_seen '
      'WHERE channel_id = ? AND op_id = ?',
      [newChannel, 'op-cc-dup'],
    );
    expect(seen.single['c'], 1);
  });

  test(
    'TYPE_CHANNEL_CREATED for already-existing channel skips insert '
    'but records op_id_seen',
    () async {
      const newChannel = 'c-grp-pre';
      // Pre-insert the channel as if the local optimistic creator path had
      // already materialized it. The fanout echo must not duplicate rows.
      await store.insertChannel(
        channelId: newChannel,
        kind: 'group',
        ownerUserId: _selfUserId,
        createdAt: 100,
        name: 'Pre',
      );
      await store.insertChannelMember(
        channelId: newChannel,
        userId: _selfUserId,
        role: 'owner',
        joinedAt: 100,
      );

      pushes.add(_makeEnvelope(
        channelId: newChannel,
        opId: 'op-cc-echo',
        senderUserId: _selfUserId,
        payload: _serverEventChannelCreated(
          channelId: newChannel,
          kind: 'group',
          name: 'Pre',
          members: [_selfUserId, _peerUserId],
          creator: _selfUserId,
          createdAtMs: 100,
        ),
        serverTimestampMs: 100,
        deliverySequence: 1,
      ));
      await _settleOpSeen(store, newChannel, 'op-cc-echo');

      final chans = await store.db.rawQuery(
        'SELECT COUNT(*) c FROM channels WHERE channel_id = ?',
        [newChannel],
      );
      expect(chans.single['c'], 1);
      // Members were NOT touched — only the local user is present, not
      // the peer from the echo's roster.
      final members = await store.db.query(
        'channel_members',
        where: 'channel_id = ?',
        whereArgs: [newChannel],
      );
      expect(members.length, 1);
      expect(members.single['user_id'], _selfUserId);
    },
  );

  test(
    'TYPE_CHANNEL_MEMBER_ADDED appends rows; '
    'INSERT OR IGNORE makes re-add a no-op',
    () async {
      // Existing group with self as a member.
      const grp = 'c-grp-add';
      await store.insertChannel(
        channelId: grp,
        kind: 'group',
        ownerUserId: _selfUserId,
        createdAt: 200,
      );
      await store.insertChannelMember(
        channelId: grp,
        userId: _selfUserId,
        role: 'owner',
        joinedAt: 200,
      );

      pushes.add(_makeEnvelope(
        channelId: grp,
        opId: 'op-add-1',
        senderUserId: _selfUserId,
        payload: _serverEventMemberAdded(
          channelId: grp,
          members: [_peerUserId, _selfUserId],
          addedAtMs: 250,
        ),
        serverTimestampMs: 250,
        deliverySequence: 1,
      ));
      await _settleMember(store, grp, _peerUserId, present: true);

      // INSERT OR IGNORE on the already-present self row leaves
      // joined_at=200 (the original), not 250.
      final selfRow = await store.db.query(
        'channel_members',
        where: 'channel_id = ? AND user_id = ?',
        whereArgs: [grp, _selfUserId],
      );
      expect(selfRow.single['role'], 'owner');
      expect(selfRow.single['joined_at'], 200);

      final peerRow = await store.db.query(
        'channel_members',
        where: 'channel_id = ? AND user_id = ?',
        whereArgs: [grp, _peerUserId],
      );
      expect(peerRow.single['role'], 'member');
      expect(peerRow.single['joined_at'], 250);
    },
  );

  test(
    'TYPE_CHANNEL_MEMBER_ADDED for unknown channel is silently dropped '
    '(op_id_seen still recorded)',
    () async {
      const ghost = _channelId; // op_id_seen needs a real channel for FK;
      // simulate "unknown channel" by targeting an envelope at the existing
      // _channelId but referencing a different channel inside the payload.
      pushes.add(_makeEnvelope(
        channelId: ghost,
        opId: 'op-add-ghost',
        senderUserId: _peerUserId,
        payload: _serverEventMemberAdded(
          channelId: 'c-does-not-exist',
          members: [_peerUserId],
          addedAtMs: 300,
        ),
        serverTimestampMs: 300,
        deliverySequence: 1,
      ));
      await _settleOpSeen(store, ghost, 'op-add-ghost');

      // No member rows for the bogus channel.
      final mem = await store.db.rawQuery(
        'SELECT COUNT(*) c FROM channel_members WHERE channel_id = ?',
        ['c-does-not-exist'],
      );
      expect(mem.single['c'], 0);
    },
  );

  test(
    'TYPE_CHANNEL_MEMBER_REMOVED soft-deletes the membership; '
    'channel remains for other members',
    () async {
      const grp = 'c-grp-rm';
      await store.insertChannel(
        channelId: grp,
        kind: 'group',
        ownerUserId: _selfUserId,
        createdAt: 400,
      );
      await store.insertChannelMember(
        channelId: grp,
        userId: _selfUserId,
        role: 'owner',
        joinedAt: 400,
      );
      await store.insertChannelMember(
        channelId: grp,
        userId: _peerUserId,
        role: 'member',
        joinedAt: 400,
      );

      pushes.add(_makeEnvelope(
        channelId: grp,
        opId: 'op-rm-1',
        senderUserId: _selfUserId,
        payload: _serverEventMemberRemoved(
          channelId: grp,
          member: _peerUserId,
          removedAtMs: 450,
        ),
        serverTimestampMs: 450,
        deliverySequence: 1,
      ));
      await _settleOpSeen(store, grp, 'op-rm-1');

      final peerRow = await store.db.query(
        'channel_members',
        where: 'channel_id = ? AND user_id = ?',
        whereArgs: [grp, _peerUserId],
      );
      expect(peerRow.single['removed_at'], 450);

      final chan = await store.db.query(
        'channels',
        where: 'channel_id = ?',
        whereArgs: [grp],
      );
      expect(chan.single['tombstoned'], 0,
          reason: 'channel must remain for the other members');
    },
  );

  test(
    'TYPE_CHANNEL_MEMBER_REMOVED of localUserId tombstones the channel '
    'locally',
    () async {
      const grp = 'c-grp-self-rm';
      await store.insertChannel(
        channelId: grp,
        kind: 'group',
        ownerUserId: _peerUserId,
        createdAt: 500,
      );
      await store.insertChannelMember(
        channelId: grp,
        userId: _selfUserId,
        role: 'member',
        joinedAt: 500,
      );
      await store.insertChannelMember(
        channelId: grp,
        userId: _peerUserId,
        role: 'owner',
        joinedAt: 500,
      );

      pushes.add(_makeEnvelope(
        channelId: grp,
        opId: 'op-rm-self',
        senderUserId: _peerUserId,
        payload: _serverEventMemberRemoved(
          channelId: grp,
          member: _selfUserId,
          removedAtMs: 550,
        ),
        serverTimestampMs: 550,
        deliverySequence: 1,
      ));
      await _settleOpSeen(store, grp, 'op-rm-self');

      final chan = await store.db.query(
        'channels',
        where: 'channel_id = ?',
        whereArgs: [grp],
      );
      expect(chan.single['tombstoned'], 1);
      final selfRow = await store.db.query(
        'channel_members',
        where: 'channel_id = ? AND user_id = ?',
        whereArgs: [grp, _selfUserId],
      );
      expect(selfRow.single['removed_at'], 550);
    },
  );
}

// --- helpers ---------------------------------------------------------------

/// Poll the store for [messageId]'s presence/absence, with a bounded wait.
/// Pushes are applied asynchronously via the broadcast stream, so tests
/// need to yield before asserting.
Future<void> _settle(
  ChatStore store,
  String messageId, {
  required bool present,
}) async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final row = await store.fetchMessage(messageId);
    if ((row != null) == present) return;
  }
  fail(
    'message $messageId '
    '${present ? 'did not appear' : 'did not disappear'} within timeout',
  );
}

/// Drain a handful of microtasks so the receiver's async apply runs
/// even when we don't have a specific row to poll on.
Future<void> _pumpQueue() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

pb.Envelope _makeEnvelope({
  required String opId,
  required String senderUserId,
  required List<int> payload,
  required int serverTimestampMs,
  required int deliverySequence,
  String channelId = _channelId,
}) {
  return pb.Envelope(
    opId: opId,
    channelId: channelId,
    resourceSeq: fixnum.Int64(deliverySequence),
    clientTimestampMs: fixnum.Int64(serverTimestampMs - 10),
    payload: payload,
    senderUserId: senderUserId,
    serverTimestampMs: fixnum.Int64(serverTimestampMs),
    deliverySequence: fixnum.Int64(deliverySequence),
  );
}

/// Build a ServerEventPayload-bearing payload by serializing the proto
/// and PREPENDING the 0x53 wire distinguisher (§10.2). The proto's
/// natural first byte is the tag for `version` (0x08), so the
/// distinguisher must be added explicitly — that's the server's job
/// in production; tests mirror it here.
List<int> _serverEventChannelCreated({
  required String channelId,
  required String kind,
  required String name,
  required List<String> members,
  required String creator,
  required int createdAtMs,
}) {
  final sep = pb.ServerEventPayload(
    version: 1,
    type: pb.ServerEventType.CHANNEL_CREATED,
    channelCreated: pb.ChannelCreated(
      channelId: channelId,
      kind: kind,
      name: name,
      members: members,
      creator: creator,
      createdAtMs: fixnum.Int64(createdAtMs),
    ),
  );
  return _withDistinguisher(sep.writeToBuffer());
}

List<int> _serverEventMemberAdded({
  required String channelId,
  required List<String> members,
  required int addedAtMs,
}) {
  final sep = pb.ServerEventPayload(
    version: 1,
    type: pb.ServerEventType.CHANNEL_MEMBER_ADDED,
    memberAdded: pb.ChannelMemberAdded(
      channelId: channelId,
      members: members,
      addedAtMs: fixnum.Int64(addedAtMs),
    ),
  );
  return _withDistinguisher(sep.writeToBuffer());
}

List<int> _serverEventMemberRemoved({
  required String channelId,
  required String member,
  required int removedAtMs,
}) {
  final sep = pb.ServerEventPayload(
    version: 1,
    type: pb.ServerEventType.CHANNEL_MEMBER_REMOVED,
    memberRemoved: pb.ChannelMemberRemoved(
      channelId: channelId,
      member: member,
      removedAtMs: fixnum.Int64(removedAtMs),
    ),
  );
  return _withDistinguisher(sep.writeToBuffer());
}

Uint8List _withDistinguisher(List<int> protoBytes) {
  final out = Uint8List(protoBytes.length + 1);
  out[0] = 0x53;
  out.setRange(1, out.length, protoBytes);
  return out;
}

Future<void> _settleChannel(
  ChatStore store,
  String channelId, {
  required bool present,
}) async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final rows = await store.db.query(
      'channels',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    if (rows.isNotEmpty == present) return;
  }
  fail('channel $channelId '
      '${present ? 'did not appear' : 'did not disappear'} within timeout');
}

Future<void> _settleMember(
  ChatStore store,
  String channelId,
  String userId, {
  required bool present,
}) async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final rows = await store.db.query(
      'channel_members',
      where: 'channel_id = ? AND user_id = ?',
      whereArgs: [channelId, userId],
      limit: 1,
    );
    if (rows.isNotEmpty == present) return;
  }
  fail('member $userId '
      '${present ? 'did not appear' : 'did not disappear'} in $channelId');
}

Future<void> _settleOpSeen(
  ChatStore store,
  String channelId,
  String opId,
) async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final rows = await store.db.query(
      'op_id_seen',
      where: 'channel_id = ? AND op_id = ?',
      whereArgs: [channelId, opId],
      limit: 1,
    );
    if (rows.isNotEmpty) return;
  }
  fail('op_id_seen for $opId in $channelId did not appear within timeout');
}

List<int> _chatPayload({
  required pb.ChatPayloadType type,
  required String messageId,
  String? body,
  String? emoji,
}) {
  final chat = pb.ChatPayload(
    version: 1,
    type: type,
    messageId: messageId,
    body: body,
    contentType: body == null ? null : 'text/plain',
    emoji: emoji,
  );
  final bytes = chat.writeToBuffer();
  // Sanity: ChatPayload bytes must never start with 0x53 (that byte is
  // reserved for ServerEventPayload envelopes, §10.2). Field 1 (version)
  // encodes as 0x08 as the first byte, so we're safe — this assert
  // would fire loudly if the schema shifted.
  assert(bytes.isEmpty || bytes[0] != 0x53);
  return Uint8List.fromList(bytes);
}
