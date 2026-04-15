import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';

/// Covers the UI-facing reactive-query methods added to [ChatStore]
/// for the v3 scaffold (SPIKE_A_SCHEMA.md §13.1, §13.2, §10).
void main() {
  group('fetchChannelList', () {
    test('orders by last_activity_ms DESC and returns preview fields',
        () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      // Channel A: older, one message
      await store.insertChannel(
        channelId: 'c-a',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 1000,
        name: 'Alice',
      );
      await _insertSentMessage(
        store: store,
        channelId: 'c-a',
        messageId: 'm-a1',
        body: 'from alice',
        authorUserId: 'u-alice',
        clientTimestampMs: 1100,
        deliverySequence: 1,
      );
      await store.db.update(
        'channels',
        {'last_activity_ms': 1100, 'last_message_id': 'm-a1'},
        where: 'channel_id = ?',
        whereArgs: ['c-a'],
      );

      // Channel B: newer activity → should come first
      await store.insertChannel(
        channelId: 'c-b',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 2000,
        name: 'Team',
      );
      await _insertSentMessage(
        store: store,
        channelId: 'c-b',
        messageId: 'm-b1',
        body: 'from bob',
        authorUserId: 'u-bob',
        clientTimestampMs: 2100,
        deliverySequence: 7,
      );
      await store.db.update(
        'channels',
        {
          'last_activity_ms': 2100,
          'last_message_id': 'm-b1',
          'unread_count': 3,
        },
        where: 'channel_id = ?',
        whereArgs: ['c-b'],
      );

      final list = await store.fetchChannelList();
      expect(list, hasLength(2));
      expect(list[0].channelId, 'c-b');
      expect(list[0].kind, 'group');
      expect(list[0].name, 'Team');
      expect(list[0].lastMessagePreview, 'from bob');
      expect(list[0].lastMessageAuthor, 'u-bob');
      expect(list[0].unreadCount, 3);
      expect(list[0].lastMessageTombstoned, isFalse);

      expect(list[1].channelId, 'c-a');
      expect(list[1].lastMessagePreview, 'from alice');
    });

    test('hides tombstoned channels and surfaces tombstoned preview',
        () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'c-gone',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
      );
      await store.db.update(
        'channels',
        {'tombstoned': 1},
        where: 'channel_id = ?',
        whereArgs: ['c-gone'],
      );

      await store.insertChannel(
        channelId: 'c-live',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 200,
        name: 'Carol',
      );
      await _insertSentMessage(
        store: store,
        channelId: 'c-live',
        messageId: 'm-deleted',
        body: null,
        authorUserId: 'u-carol',
        clientTimestampMs: 220,
        deliverySequence: 1,
        tombstoned: true,
      );
      await store.db.update(
        'channels',
        {'last_activity_ms': 220, 'last_message_id': 'm-deleted'},
        where: 'channel_id = ?',
        whereArgs: ['c-live'],
      );

      final list = await store.fetchChannelList();
      expect(list.map((e) => e.channelId), ['c-live']);
      expect(list.single.lastMessageTombstoned, isTrue);
      expect(list.single.lastMessagePreview, isNull);
    });
  });

  group('watchChannelList', () {
    test('emits initial value and re-emits on channel/message changes',
        () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      final emissions = <List<ChannelListEntry>>[];
      final sub = store.watchChannelList().listen(emissions.add);

      // Initial emission.
      await _pumpEventLoop();
      expect(emissions, hasLength(1));
      expect(emissions.first, isEmpty);

      // Inserting a channel → re-emit.
      await store.insertChannel(
        channelId: 'c-1',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
      );
      await _pumpEventLoop();
      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last.map((e) => e.channelId), ['c-1']);

      // Enqueueing a message → messages table change → re-emit.
      await store.enqueueLocalMessage(
        message: const MessageRow(
          messageId: 'm-1',
          channelId: 'c-1',
          authorUserId: 'u-self',
          body: 'hi',
          contentType: 'text/plain',
          replyToMessageId: null,
          clientTimestampMs: 150,
          serverTimestampMs: null,
          deliverySequence: null,
          state: MessageState.pending,
          stateUpdatedAt: 150,
          isEdited: false,
          lastEditMs: null,
          tombstoned: false,
          tombstonePendingUntil: null,
        ),
        op: const OutboundOpRow(
          opId: 'op-1',
          transport: OpTransport.ws,
          kind: OpKind.chatPayload,
          restMethod: null,
          restPath: null,
          resourceId: 'c-1',
          resourceSeq: 1,
          payload: [0x01],
          status: OpStatus.pending,
          attempts: 0,
          nextRetryAt: 150,
          dispatchedAt: null,
          lastError: null,
          acknowledgedAt: null,
          createdAt: 150,
          targetMessageId: 'm-1',
          targetChannelId: 'c-1',
        ),
        nowMs: 150,
      );
      await _pumpEventLoop();
      // We've had at minimum one emission after the insert; the exact
      // count depends on how table-change notifications coalesce.
      final latest = emissions.last;
      expect(latest, hasLength(1));
      expect(latest.single.lastMessagePreview, 'hi');

      await sub.cancel();
    });
  });

  group('fetchChannelMessages', () {
    test('pending (null delivery_sequence) sorts to the top', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'c-1',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
      );
      // An old acked message
      await _insertSentMessage(
        store: store,
        channelId: 'c-1',
        messageId: 'm-old',
        body: 'old',
        authorUserId: 'u-self',
        clientTimestampMs: 100,
        deliverySequence: 1,
      );
      // A brand-new pending one
      await store.enqueueLocalMessage(
        message: const MessageRow(
          messageId: 'm-new',
          channelId: 'c-1',
          authorUserId: 'u-self',
          body: 'new',
          contentType: 'text/plain',
          replyToMessageId: null,
          clientTimestampMs: 200,
          serverTimestampMs: null,
          deliverySequence: null,
          state: MessageState.pending,
          stateUpdatedAt: 200,
          isEdited: false,
          lastEditMs: null,
          tombstoned: false,
          tombstonePendingUntil: null,
        ),
        op: const OutboundOpRow(
          opId: 'op-new',
          transport: OpTransport.ws,
          kind: OpKind.chatPayload,
          restMethod: null,
          restPath: null,
          resourceId: 'c-1',
          resourceSeq: 1,
          payload: [0x01],
          status: OpStatus.pending,
          attempts: 0,
          nextRetryAt: 200,
          dispatchedAt: null,
          lastError: null,
          acknowledgedAt: null,
          createdAt: 200,
          targetMessageId: 'm-new',
          targetChannelId: 'c-1',
        ),
        nowMs: 200,
      );

      final msgs = await store.fetchChannelMessages('c-1');
      expect(msgs.map((m) => m.messageId), ['m-new', 'm-old']);
    });
  });

  group('markChannelRead', () {
    test('clears unread_count and points last_read_message_id at newest',
        () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'c-1',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
      );
      await store.db.update(
        'channels',
        {'unread_count': 7},
        where: 'channel_id = ?',
        whereArgs: ['c-1'],
      );

      // Three messages with ascending delivery_sequence.
      for (var i = 1; i <= 3; i++) {
        await _insertSentMessage(
          store: store,
          channelId: 'c-1',
          messageId: 'm-$i',
          body: 'msg $i',
          authorUserId: 'u-other',
          clientTimestampMs: 100 + i,
          deliverySequence: i,
        );
      }

      await store.markChannelRead('c-1', 1000);

      final row = (await store.db.query(
        'channels',
        where: 'channel_id = ?',
        whereArgs: ['c-1'],
        limit: 1,
      ))
          .single;
      expect(row['unread_count'], 0);
      expect(row['last_read_message_id'], 'm-3');
    });

    test('leaves last_read_message_id untouched when channel is empty',
        () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'c-empty',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
      );
      await store.db.update(
        'channels',
        {'unread_count': 2},
        where: 'channel_id = ?',
        whereArgs: ['c-empty'],
      );

      await store.markChannelRead('c-empty', 500);

      final row = (await store.db.query(
        'channels',
        where: 'channel_id = ?',
        whereArgs: ['c-empty'],
        limit: 1,
      ))
          .single;
      expect(row['unread_count'], 0);
      expect(row['last_read_message_id'], isNull);
    });
  });
}

/// Inserts a `sent` (server-acked) message directly. Used to seed chat
/// history the tests need without routing through the optimistic-send
/// flow (which also writes to `outbound_ops`).
Future<void> _insertSentMessage({
  required ChatStore store,
  required String channelId,
  required String messageId,
  required String? body,
  required String authorUserId,
  required int clientTimestampMs,
  required int deliverySequence,
  bool tombstoned = false,
}) async {
  await store.db.insert('messages', {
    'message_id': messageId,
    'channel_id': channelId,
    'author_user_id': authorUserId,
    'body': body,
    'content_type': body == null ? null : 'text/plain',
    'reply_to_message_id': null,
    'attachments': null,
    'forward_source': null,
    'client_timestamp_ms': clientTimestampMs,
    'server_timestamp_ms': clientTimestampMs + 10,
    'delivery_sequence': deliverySequence,
    'message_state': MessageState.sent.wire,
    'state_updated_at': clientTimestampMs,
    'is_edited': 0,
    'last_edit_ms': null,
    'tombstoned': tombstoned ? 1 : 0,
    'tombstone_pending_until': null,
  });
}

/// Gives stream controllers a turn to deliver events.
Future<void> _pumpEventLoop() =>
    Future<void>.delayed(const Duration(milliseconds: 10));
