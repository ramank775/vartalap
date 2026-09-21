import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';

/// Covers the UI-facing reactive-query methods added to [ChatStore]
/// for the v3 scaffold (SPIKE_A_SCHEMA.md §13.1, §13.2, §10).
void main() {
  group('ChannelListEntry.title (AUTH_CONTRACT §2.4)', () {
    Future<ChatStore> dmWith({
      String? contactBookName,
      String? username,
      String? displayName,
      bool withContact = true,
      String? channelName,
    }) async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.insertChannel(
        channelId: 'c-dm',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 1000,
        name: channelName,
      );
      await store.insertChannelMember(
        channelId: 'c-dm',
        userId: 'u-peer',
        role: 'member',
        joinedAt: 1000,
      );
      if (withContact) {
        await store.upsertContact(
          userId: 'u-peer',
          username: username,
          displayName: displayName,
          contactBookName: contactBookName,
          nowMs: 1000,
        );
      }
      await _insertSentMessage(
        store: store,
        channelId: 'c-dm',
        messageId: 'm-1',
        body: 'hi',
        authorUserId: 'u-peer',
        clientTimestampMs: 1100,
        deliverySequence: 1,
      );
      await store.db.update(
        'channels',
        {'last_activity_ms': 1100, 'last_message_id': 'm-1'},
        where: 'channel_id = ?',
        whereArgs: ['c-dm'],
      );
      return store;
    }

    test('contact-book name wins over the handle', () async {
      final store = await dmWith(
        contactBookName: 'Kavya Menon',
        username: 'kavya_m',
        channelName: 'stale snapshot',
      );
      final list = await store.fetchChannelList();
      expect(list.single.title, 'Kavya Menon');
    });

    test('no contact-book entry falls to @username, not the snapshot',
        () async {
      final store = await dmWith(
        username: 'kavya_m',
        displayName: 'Kavya Menon',
        channelName: 'stale snapshot',
      );
      final list = await store.fetchChannelList();
      expect(
        list.single.title,
        '@kavya_m',
        reason: '§2.4: the required public identifier is the fallback, '
            'ahead of whatever displayName the server volunteered.',
      );
    });

    test('an undiscovered peer falls back to the name, never the channel_id',
        () async {
      final store = await dmWith(withContact: false, channelName: 'Kavya');
      final list = await store.fetchChannelList();
      expect(list.single.title, 'Kavya');

      final anon = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(anon.close);
      expect(
        const ChannelListEntry(
          channelId: 'c-xyz',
          kind: 'one_to_one',
          name: null,
          avatarUrl: null,
          lastActivityMs: 0,
          unreadCount: 0,
          lastMessagePreview: null,
          lastMessageAuthor: null,
          lastMessageTombstoned: false,
        ).title,
        'Unknown',
      );
    });

    test('a group keeps its own name and ignores the peer subqueries',
        () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.insertChannel(
        channelId: 'c-g',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 1000,
        name: 'Pune Trek Crew',
      );
      await store.insertChannelMember(
        channelId: 'c-g',
        userId: 'u-peer',
        role: 'member',
        joinedAt: 1000,
      );
      await store.upsertContact(
        userId: 'u-peer',
        contactBookName: 'Kavya Menon',
        nowMs: 1000,
      );
      final list =
          await store.fetchMemberChannels(userId: 'u-peer', kind: 'group');
      expect(list.single.title, 'Pune Trek Crew');
      expect(list.single.peerContact, isNull);
    });
  });

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

      // Inserting a channel → re-emit, but an empty channel does NOT
      // appear on the chat list (it lives in the Groups tab until it
      // has at least one message).
      await store.insertChannel(
        channelId: 'c-1',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
      );
      await _pumpEventLoop();
      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last, isEmpty);

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

    test('tombstoned rows stay in the chat view, with their reactions',
        () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.insertChannel(
        channelId: 'c-1',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
      );
      await _insertSentMessage(
        store: store,
        channelId: 'c-1',
        messageId: 'm-live',
        body: 'still here',
        authorUserId: 'u-peer',
        clientTimestampMs: 100,
        deliverySequence: 1,
      );
      await _insertSentMessage(
        store: store,
        channelId: 'c-1',
        messageId: 'm-gone',
        body: null,
        authorUserId: 'u-peer',
        clientTimestampMs: 200,
        deliverySequence: 2,
        tombstoned: true,
      );
      await store.applyInboundReactionAdd(
        channelId: 'c-1',
        opId: 'op-r1',
        messageId: 'm-live',
        senderUserId: 'u-peer',
        emoji: '\u{1F44D}',
        nowMs: 300,
      );

      final msgs = await store.fetchChannelMessages('c-1');
      expect(
        msgs.map((m) => m.messageId),
        ['m-gone', 'm-live'],
        reason: 'V3_ARCHITECTURE decision 11: a deleted message keeps its '
            'place as "This message was deleted".',
      );
      expect(msgs.first.tombstoned, isTrue);
      final live = msgs.last;
      expect(live.reactions, hasLength(1));
      expect(live.reactions.single.emoji, '\u{1F44D}');
      expect(live.reactions.single.userId, 'u-peer');
    });

    test('a MessageWindow grows the live query in place', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.insertChannel(
        channelId: 'c-1',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
      );
      for (var i = 0; i < 5; i++) {
        await _insertSentMessage(
          store: store,
          channelId: 'c-1',
          messageId: 'm-$i',
          body: 'msg $i',
          authorUserId: 'u-peer',
          clientTimestampMs: 100 + i,
          deliverySequence: i + 1,
        );
      }

      final window = MessageWindow(limit: 2);
      final seen = <int>[];
      final sub = store
          .watchChannelMessages('c-1', window: window)
          .listen((rows) => seen.add(rows.length));
      addTearDown(sub.cancel);
      await _pumpEventLoop();
      expect(seen.last, 2);

      window.grow(3);
      await _pumpEventLoop();
      expect(
        seen.last,
        5,
        reason: 'Load-older must re-run the one live query with a bigger '
            'page, not open a second stream.',
      );
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

  group('clearChannelMessages', () {
    test('wipes messages, drops channel from chat list, leaves channel row',
        () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'c-1',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Team',
      );
      await _insertSentMessage(
        store: store,
        channelId: 'c-1',
        messageId: 'm-1',
        body: 'hello',
        authorUserId: 'u-other',
        clientTimestampMs: 200,
        deliverySequence: 1,
      );
      await store.db.update(
        'channels',
        {'last_activity_ms': 200, 'last_message_id': 'm-1', 'unread_count': 5},
        where: 'channel_id = ?',
        whereArgs: ['c-1'],
      );

      // Sanity: channel is on the list before clearing.
      expect(
        (await store.fetchChannelList()).map((e) => e.channelId),
        ['c-1'],
      );

      await store.clearChannelMessages('c-1');

      // Chat list now empty.
      expect(await store.fetchChannelList(), isEmpty);

      // Messages gone.
      final msgs = await store.db.query(
        'messages',
        where: 'channel_id = ?',
        whereArgs: ['c-1'],
      );
      expect(msgs, isEmpty);

      // Channel row still present, last_message_id and unread cleared.
      final ch = (await store.db.query(
        'channels',
        where: 'channel_id = ?',
        whereArgs: ['c-1'],
      ))
          .single;
      expect(ch['last_message_id'], isNull);
      expect(ch['last_read_message_id'], isNull);
      expect(ch['unread_count'], 0);
    });
  });

  group('leaveGroupLocal', () {
    test('drops the group channel and cascades members + messages',
        () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'g-1',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Team',
      );
      await store.insertChannelMember(
        channelId: 'g-1',
        userId: 'u-self',
        role: 'member',
        joinedAt: 100,
      );
      await _insertSentMessage(
        store: store,
        channelId: 'g-1',
        messageId: 'm-1',
        body: 'hi',
        authorUserId: 'u-self',
        clientTimestampMs: 110,
        deliverySequence: 1,
      );

      await store.leaveGroupLocal('g-1');

      expect(
        await store.db.query('channels', where: 'channel_id = ?',
            whereArgs: ['g-1']),
        isEmpty,
      );
      expect(
        await store.db.query('channel_members', where: 'channel_id = ?',
            whereArgs: ['g-1']),
        isEmpty,
      );
      expect(
        await store.db.query('messages', where: 'channel_id = ?',
            whereArgs: ['g-1']),
        isEmpty,
      );
    });

    test('refuses to delete a DM channel', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'dm-1',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
      );

      expect(
        () => store.leaveGroupLocal('dm-1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('fetchMemberChannels', () {
    test('returns groups the user is a member of, sorted by name',
        () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'g-zeta',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Zeta',
      );
      await store.insertChannelMember(
        channelId: 'g-zeta',
        userId: 'u-self',
        role: 'member',
        joinedAt: 100,
      );

      await store.insertChannel(
        channelId: 'g-alpha',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Alpha',
      );
      await store.insertChannelMember(
        channelId: 'g-alpha',
        userId: 'u-self',
        role: 'member',
        joinedAt: 100,
      );

      // A group I'm not in — shouldn't appear.
      await store.insertChannel(
        channelId: 'g-other',
        kind: 'group',
        ownerUserId: 'u-other',
        createdAt: 100,
        name: 'Other',
      );

      // A DM — filtered out by kind='group'.
      await store.insertChannel(
        channelId: 'dm-1',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Bob',
      );
      await store.insertChannelMember(
        channelId: 'dm-1',
        userId: 'u-self',
        role: 'member',
        joinedAt: 100,
      );

      final groups = await store.fetchMemberChannels(
        userId: 'u-self',
        kind: 'group',
      );
      expect(
        groups.map((c) => c.channelId),
        ['g-alpha', 'g-zeta'],
      );
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
