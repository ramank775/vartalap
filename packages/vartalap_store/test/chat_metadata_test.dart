import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';

/// Local-only chat metadata — V3_ARCHITECTURE decision 3 offline
/// matrix (pin / mute never leave the device) and the
/// V3_RELEASE_PLAN §6 rule that delete chat is not leave group.
void main() {
  group('deleteChatLocal', () {
    test('hides the chat, keeps membership and the Groups listing', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'g-1',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Kothrud Flat 3B',
      );
      await store.insertChannelMember(
        channelId: 'g-1',
        userId: 'u-self',
        role: 'owner',
        joinedAt: 100,
      );
      await _seedMessage(store, channelId: 'g-1', messageId: 'm-1');

      expect(await store.fetchChannelList(), hasLength(1));

      await store.deleteChatLocal('g-1');

      // Gone from Chats...
      expect(await store.fetchChannelList(), isEmpty);
      // ...but the channel row, the membership and the Groups listing
      // all survive. This is what separates it from leaveGroupLocal.
      expect(
        await store.db
            .query('channels', where: 'channel_id = ?', whereArgs: ['g-1']),
        hasLength(1),
      );
      expect(
        await store.db.query('channel_members',
            where: 'channel_id = ?', whereArgs: ['g-1']),
        hasLength(1),
      );
      final groups =
          await store.fetchMemberChannels(userId: 'u-self', kind: 'group');
      expect(groups.map((c) => c.channelId), ['g-1']);
      // History is erased.
      expect(
        await store.db
            .query('messages', where: 'channel_id = ?', whereArgs: ['g-1']),
        isEmpty,
      );
    });

    test('the next inbound message brings the chat back', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'g-1',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Kothrud Flat 3B',
      );
      await _seedMessage(store, channelId: 'g-1', messageId: 'm-1');
      await store.deleteChatLocal('g-1');
      expect(await store.fetchChannelList(), isEmpty);

      await store.applyInboundMessage(
        localUserId: 'u-self',
        channelId: 'g-1',
        opId: 'op-in-1',
        messageId: 'm-2',
        senderUserId: 'u-vikram',
        body: 'Maintenance meeting moved to Sunday 11am',
        contentType: 'text/plain',
        attachments: null,
        forwardSource: null,
        replyToMessageId: null,
        clientTimestampMs: 500,
        serverTimestampMs: 510,
        deliverySequence: 2,
        nowMs: 520,
      );

      final list = await store.fetchChannelList();
      expect(list.map((c) => c.channelId), ['g-1']);
      expect(list.single.unreadCount, 1);
    });
  });

  group('applyInboundMessage dedup', () {
    test('a message_id we already hold is a complete no-op', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'g-1',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Kothrud Flat 3B',
      );

      Future<void> deliver({
        required String opId,
        required int deliverySequence,
      }) =>
          store.applyInboundMessage(
            localUserId: 'u-self',
            channelId: 'g-1',
            opId: opId,
            messageId: 'm-dup',
            senderUserId: 'u-vikram',
            body: 'Water tanker at 6',
            contentType: 'text/plain',
            attachments: null,
            forwardSource: null,
            replyToMessageId: null,
            clientTimestampMs: 500,
            serverTimestampMs: 500 + deliverySequence,
            deliverySequence: deliverySequence,
            nowMs: 600,
          );

      await deliver(opId: 'op-1', deliverySequence: 7);
      await store.markChannelRead('g-1', 650);
      expect(await store.fetchChannelList(), hasLength(1));
      expect((await store.fetchChannelList()).single.unreadCount, 0);

      // Same message, second delivery, NEW op_id — so the §7.2
      // op_id_seen gate upstream cannot catch it. It must not throw,
      // must not duplicate the row, and must not resurrect the unread
      // badge the user has already cleared.
      await deliver(opId: 'op-2', deliverySequence: 9);

      final rows = await store.fetchChannelMessages('g-1');
      expect(
        rows.map((m) => m.messageId),
        ['m-dup'],
        reason: 'one row, not two — a duplicate delivery adds no bubble.',
      );
      expect(
        rows.single.deliverySequence,
        7,
        reason: 'the original ordering survives; a re-delivery does not '
            'reshuffle the conversation.',
      );
      expect(
        (await store.fetchChannelList()).single.unreadCount,
        0,
        reason: 'and it does not move the unread count.',
      );
      expect(
        await store.hasSeenOpId('g-1', 'op-2'),
        isTrue,
        reason: 'op_id_seen is still recorded — the old plain INSERT threw '
            'and rolled this row back with it, so a re-fanout of the same '
            'op was re-evaluated forever.',
      );
    });
  });

  group('pin and mute', () {
    test('pinned channels sort first regardless of activity', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await _seedChatWithMessage(store, 'c-old', 'Old', activityMs: 100);
      await _seedChatWithMessage(store, 'c-new', 'New', activityMs: 900);

      expect(
        (await store.fetchChannelList()).map((c) => c.channelId),
        ['c-new', 'c-old'],
      );

      await store.setChannelPinned('c-old', true);

      final pinnedFirst = await store.fetchChannelList();
      expect(pinnedFirst.map((c) => c.channelId), ['c-old', 'c-new']);
      expect(pinnedFirst.first.pinned, isTrue);
      expect(pinnedFirst.last.pinned, isFalse);

      await store.setChannelPinned('c-old', false);
      expect(
        (await store.fetchChannelList()).map((c) => c.channelId),
        ['c-new', 'c-old'],
      );
    });

    test('setChannelMuted writes and clears muted_until_ms', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await _seedChatWithMessage(store, 'c-1', 'Ananya', activityMs: 100);

      expect((await store.fetchChannelList()).single.mutedUntilMs, isNull);

      await store.setChannelMuted('c-1', 5000);
      final muted = (await store.fetchChannelList()).single;
      expect(muted.mutedUntilMs, 5000);
      expect(muted.isMutedAt(4000), isTrue);
      // An elapsed mute reads as unmuted without a sweep job.
      expect(muted.isMutedAt(6000), isFalse);

      await store.setChannelMuted('c-1', null);
      expect((await store.fetchChannelList()).single.mutedUntilMs, isNull);
    });
  });

  group('hasFailedOp', () {
    test('flips once an op targeting the channel dead-letters', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'c-1',
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Farhan Qureshi',
      );
      await store.enqueueLocalMessage(
        message: const MessageRow(
          messageId: 'm-1',
          channelId: 'c-1',
          authorUserId: 'u-self',
          body: 'hi',
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
          opId: 'op-1',
          transport: OpTransport.ws,
          kind: OpKind.chatPayload,
          restMethod: null,
          restPath: null,
          resourceId: 'c-1',
          payload: [1, 2, 3],
          status: OpStatus.pending,
          attempts: 0,
          nextRetryAt: 200,
          dispatchedAt: null,
          lastError: null,
          acknowledgedAt: null,
          createdAt: 200,
          targetMessageId: 'm-1',
          targetChannelId: 'c-1',
        ),
        nowMs: 200,
      );

      expect((await store.fetchChannelList()).single.hasFailedOp, isFalse);

      await store.markOpDeadLetter(
        opId: 'op-1',
        reason: 'retry budget exhausted',
        messageId: 'm-1',
        nowMs: 300,
      );

      expect((await store.fetchChannelList()).single.hasFailedOp, isTrue);
    });
  });

  group('fetchChannelMedia', () {
    test('returns image messages newest-first and nothing else', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'c-1',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Iyer Family',
      );
      await _seedMessage(store, channelId: 'c-1', messageId: 'm-text');
      await _seedMessage(store,
          channelId: 'c-1',
          messageId: 'm-img-1',
          contentType: 'image/jpeg',
          clientTimestampMs: 200);
      await _seedMessage(store,
          channelId: 'c-1',
          messageId: 'm-img-2',
          contentType: 'image/png',
          clientTimestampMs: 300);
      await _seedMessage(store,
          channelId: 'c-1',
          messageId: 'm-img-gone',
          contentType: 'image/png',
          clientTimestampMs: 400,
          tombstoned: true);

      final media = await store.fetchChannelMedia('c-1');
      expect(media.map((m) => m.messageId), ['m-img-2', 'm-img-1']);
    });

    test('is empty for a channel with no images', () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.insertChannel(
        channelId: 'c-1',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: 100,
        name: 'Iyer Family',
      );
      await _seedMessage(store, channelId: 'c-1', messageId: 'm-text');

      expect(await store.fetchChannelMedia('c-1'), isEmpty);
    });
  });
}

/// Insert a server-acked message directly, bypassing the optimistic
/// send path (which would also write `outbound_ops`).
Future<void> _seedMessage(
  ChatStore store, {
  required String channelId,
  required String messageId,
  String? body = 'hello',
  String contentType = 'text/plain',
  int clientTimestampMs = 150,
  bool tombstoned = false,
}) async {
  await store.db.insert('messages', {
    'message_id': messageId,
    'channel_id': channelId,
    'author_user_id': 'u-peer',
    'body': body,
    'content_type': contentType,
    'reply_to_message_id': null,
    'attachments': null,
    'forward_source': null,
    'client_timestamp_ms': clientTimestampMs,
    'server_timestamp_ms': clientTimestampMs + 10,
    'delivery_sequence': clientTimestampMs,
    'message_state': MessageState.sent.wire,
    'state_updated_at': clientTimestampMs,
    'is_edited': 0,
    'last_edit_ms': null,
    'tombstoned': tombstoned ? 1 : 0,
    'tombstone_pending_until': null,
  });
  await store.db.update(
    'channels',
    {'last_message_id': messageId, 'last_activity_ms': clientTimestampMs},
    where: 'channel_id = ?',
    whereArgs: [channelId],
  );
}

/// A channel with exactly one message, so it qualifies for the chat
/// list (§6: only conversations with messages appear there).
Future<void> _seedChatWithMessage(
  ChatStore store,
  String channelId,
  String name, {
  required int activityMs,
}) async {
  await store.insertChannel(
    channelId: channelId,
    kind: 'one_to_one',
    ownerUserId: 'u-self',
    createdAt: 100,
    name: name,
  );
  await _seedMessage(
    store,
    channelId: channelId,
    messageId: 'm-$channelId',
    clientTimestampMs: activityMs,
  );
}
