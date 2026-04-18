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
}) {
  return pb.Envelope(
    opId: opId,
    channelId: _channelId,
    resourceSeq: fixnum.Int64(deliverySequence),
    clientTimestampMs: fixnum.Int64(serverTimestampMs - 10),
    payload: payload,
    senderUserId: senderUserId,
    serverTimestampMs: fixnum.Int64(serverTimestampMs),
    deliverySequence: fixnum.Int64(deliverySequence),
  );
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
