import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';

/// Decision 222's message features, store side.
void main() {
  late ChatStore store;

  setUp(() async {
    store = await ChatStore.open(path: inMemoryDatabasePath);
    await store.insertChannel(
      channelId: 'c-1',
      kind: 'one_to_one',
      ownerUserId: 'u-self',
      createdAt: 1,
    );
  });
  tearDown(() => store.close());

  Future<void> inbound(String id, String author, String body, int at,
          {String? opId, int? timerSec, int? nowMs}) =>
      store.applyInboundMessage(
        localUserId: 'u-self',
        channelId: 'c-1',
        opId: opId ?? 'op-$id',
        messageId: id,
        senderUserId: author,
        body: body,
        contentType: null,
        attachments: null,
        forwardSource: null,
        replyToMessageId: null,
        clientTimestampMs: at,
        serverTimestampMs: at,
        nowMs: nowMs ?? at,
        timerSec: timerSec,
      );

  group('delete for everyone within 5 minutes (SYNC_PROTOCOL §20.1)', () {
    const sentAt = 1700000000000;
    const window = 5 * 60 * 1000;
    const grace = 60 * 1000;

    Future<bool> deleteMadeAt(int madeAt, {int? viaOpId}) =>
        store.applyInboundMessageDelete(
          channelId: 'c-1',
          opId: _op7(viaOpId ?? madeAt),
          messageId: 'm-1',
          senderUserId: 'u-peer',
          // The server stamp of the delete itself plays no part.
          serverTimestampMs: sentAt + const Duration(hours: 3).inMilliseconds,
          nowMs: sentAt + const Duration(hours: 3).inMilliseconds,
          madeAtMs: viaOpId == null ? null : madeAt,
        );

    test('a delete made inside the window applies, however late it lands',
        () async {
      await inbound('m-1', 'u-peer', 'oops', sentAt);
      expect(await deleteMadeAt(sentAt + window - 1000), isTrue);
      expect((await store.fetchMessage('m-1'))!.tombstoned, isTrue);
    });

    test('the grace covers a delete made just past the window', () async {
      await inbound('m-1', 'u-peer', 'oops', sentAt);
      expect(await deleteMadeAt(sentAt + window + grace), isTrue);
    });

    test('a delete made past window and grace is ignored', () async {
      await inbound('m-1', 'u-peer', 'keep me', sentAt);
      expect(await deleteMadeAt(sentAt + window + grace + 1), isFalse);
      final row = await store.fetchMessage('m-1');
      expect(row!.tombstoned, isFalse);
      expect(row.body, 'keep me');
    });

    test('madeAtMs (a re-send standing for an older op) wins over the op id',
        () async {
      await inbound('m-1', 'u-peer', 'oops', sentAt);
      expect(
          await deleteMadeAt(sentAt + 1000,
              viaOpId: sentAt + const Duration(hours: 2).inMilliseconds),
          isTrue);
    });

    test('a parked delete is judged by its op id once the message lands',
        () async {
      expect(await deleteMadeAt(sentAt + window + grace + 1), isFalse);
      await inbound('m-1', 'u-peer', 'late', sentAt);
      expect((await store.fetchMessage('m-1'))!.tombstoned, isFalse);
    });
  });

  group('edit history', () {
    Future<void> edit(String body, int at, {String? from}) =>
        store.applyInboundMessageUpdate(
          channelId: 'c-1',
          opId: 'op-edit-$at',
          messageId: 'm-1',
          senderUserId: from ?? 'u-peer',
          body: body,
          contentType: null,
          attachments: null,
          serverTimestampMs: at,
          nowMs: at,
        );

    Future<List<String>> versions() async => [
          for (final v in await store.fetchMessageVersions('m-1'))
            '${v.body}@${v.atMs}'
        ];

    test('a peer\'s edits keep every earlier version, newest first', () async {
      await inbound('m-1', 'u-peer', 'meet at 5', 1000);
      expect(await versions(), ['meet at 5@1000']);
      await edit('meet at 6', 2000);
      await edit('meet at 7', 3000);
      expect(await versions(),
          ['meet at 7@3000', 'meet at 6@2000', 'meet at 5@1000']);
    });

    test('an older edit landing after a newer one only joins the history',
        () async {
      await inbound('m-1', 'u-peer', 'v0', 1000);
      await edit('v2', 3000);
      await edit('v1', 2000);
      expect((await store.fetchMessage('m-1'))!.body, 'v2');
      expect(await versions(), ['v2@3000', 'v1@2000', 'v0@1000']);
    });

    test('an edit from someone else keeps nothing', () async {
      await inbound('m-1', 'u-peer', 'v0', 1000);
      await edit('forged', 2000, from: 'u-other');
      expect(await versions(), ['v0@1000']);
    });

    test('a delete for everyone takes the history with it', () async {
      await inbound('m-1', 'u-peer', 'v0', 1000);
      await edit('v1', 2000);
      await store.applyInboundMessageDelete(
          channelId: 'c-1',
          opId: 'op-del',
          messageId: 'm-1',
          senderUserId: 'u-peer',
          serverTimestampMs: 3000,
          nowMs: 3000);
      expect(await store.db.query('message_versions'), isEmpty);
    });

    test(
        'own edits keep versions as they are made; a rejected one takes '
        'back what it kept', () async {
      await inbound('m-1', 'u-self', 'v0', 1000);
      Future<void> ownEdit(String body, String opId, int at) =>
          store.enqueueMessageEdit(
            messageId: 'm-1',
            newBody: body,
            nowMs: at,
            op: OutboundOpRow(
              opId: opId,
              transport: OpTransport.ws,
              kind: OpKind.messageEdit,
              restMethod: null,
              restPath: null,
              resourceId: 'c-1',
              payload: const [1],
              status: OpStatus.pending,
              attempts: 0,
              nextRetryAt: at,
              dispatchedAt: null,
              lastError: null,
              acknowledgedAt: null,
              createdAt: at,
              targetMessageId: 'm-1',
              targetChannelId: 'c-1',
            ),
          );
      await ownEdit('v1', 'op-a', 2000);
      await store.applyMessageOpAck(
          opId: 'op-a',
          kind: OpKind.messageEdit,
          messageId: 'm-1',
          nowMs: 2100);
      // Offline: two more, neither acked yet.
      await ownEdit('v2', 'op-b', 3000);
      await ownEdit('v3', 'op-c', 4000);
      expect(await versions(), ['v3@4000', 'v2@3000', 'v1@2100', 'v0@1000']);

      await store.applyPermanentReject(
          opId: 'op-b', reason: 'forbidden', messageId: 'm-1', nowMs: 5000);
      final m = (await store.fetchMessage('m-1'))!;
      expect(m.body, 'v1');
      expect(m.isEdited, isTrue);
      expect(await versions(), ['v1@2100', 'v0@1000']);
    });

    test('rejecting the only edit leaves the message unedited', () async {
      await inbound('m-1', 'u-self', 'v0', 1000);
      await store.enqueueMessageEdit(
        messageId: 'm-1',
        newBody: 'v1',
        nowMs: 2000,
        op: OutboundOpRow(
          opId: 'op-a',
          transport: OpTransport.ws,
          kind: OpKind.messageEdit,
          restMethod: null,
          restPath: null,
          resourceId: 'c-1',
          payload: const [1],
          status: OpStatus.pending,
          attempts: 0,
          nextRetryAt: 2000,
          dispatchedAt: null,
          lastError: null,
          acknowledgedAt: null,
          createdAt: 2000,
          targetMessageId: 'm-1',
          targetChannelId: 'c-1',
        ),
      );
      await store.applyPermanentReject(
          opId: 'op-a', reason: 'forbidden', messageId: 'm-1', nowMs: 3000);
      final m = (await store.fetchMessage('m-1'))!;
      expect([m.body, m.isEdited, m.lastEditMs], ['v0', false, null]);
      expect(await versions(), ['v0@1000']);
    });
  });

  group('timed messages', () {
    test(
        'a timed message goes at its server time plus its timer, and an '
        'unread one stops counting', () async {
      await inbound('m-0', 'u-peer', 'hello', 500);
      await store.markChannelRead('c-1', 600);
      await inbound('m-1', 'u-peer', 'OTP 1234', 1000, timerSec: 60);
      final m = (await store.fetchMessage('m-1'))!;
      expect([m.timerSec, m.expiresAtMs], [60, 61000]);
      expect(await store.nextExpiryMs(), 61000);
      expect((await store.fetchChannelList()).single.unreadCount, 1);

      expect(
          await store.deleteExpiredMessages(
              nowMs: 60999, localUserId: 'u-self'),
          isEmpty);
      expect(
          await store.deleteExpiredMessages(
              nowMs: 61000, localUserId: 'u-self'),
          {'c-1'});
      expect(await store.fetchMessage('m-1'), isNull);
      final chat = (await store.fetchChannelList()).single;
      expect(chat.unreadCount, 0);
      expect(chat.lastMessagePreview, 'hello');
      expect(await store.nextExpiryMs(), isNull);
    });

    test('one whose time was up before it arrived is never stored', () async {
      await inbound('m-1', 'u-peer', 'OTP 1234', 1000,
          timerSec: 60, nowMs: 61000);
      expect(await store.fetchMessage('m-1'), isNull);
      expect(await store.hasSeenOpId('c-1', 'op-m-1'), isTrue);
    });

    test(
        'edits and reactions to one whose time is up are ignored, even '
        'before the sweep', () async {
      await inbound('m-1', 'u-peer', 'OTP 1234', 1000, timerSec: 60);
      expect(
          await store.applyInboundMessageUpdate(
              channelId: 'c-1',
              opId: 'op-edit',
              messageId: 'm-1',
              senderUserId: 'u-peer',
              body: 'OTP 9999',
              contentType: null,
              attachments: null,
              serverTimestampMs: 61500,
              nowMs: 61500),
          isFalse);
      expect(
          await store.applyInboundReactionAdd(
              channelId: 'c-1',
              opId: 'op-react',
              messageId: 'm-1',
              senderUserId: 'u-other',
              emoji: '👍',
              serverTimestampMs: 61500,
              nowMs: 61500),
          isFalse);
      expect((await store.fetchMessage('m-1'))!.body, 'OTP 1234');
    });

    test('our own timed message starts its timer when the server takes it',
        () async {
      await store.enqueueLocalMessage(
        message: const MessageRow(
          messageId: 'm-own',
          channelId: 'c-1',
          authorUserId: 'u-self',
          body: 'code 42',
          contentType: null,
          replyToMessageId: null,
          clientTimestampMs: 1000,
          serverTimestampMs: null,
          state: MessageState.pending,
          stateUpdatedAt: 1000,
          isEdited: false,
          lastEditMs: null,
          tombstoned: false,
          tombstonePendingUntil: null,
          timerSec: 300,
        ),
        op: const OutboundOpRow(
          opId: 'op-own',
          transport: OpTransport.ws,
          kind: OpKind.chatPayload,
          restMethod: null,
          restPath: null,
          resourceId: 'c-1',
          payload: [1],
          status: OpStatus.pending,
          attempts: 0,
          nextRetryAt: 1000,
          dispatchedAt: null,
          lastError: null,
          acknowledgedAt: null,
          createdAt: 1000,
          targetMessageId: 'm-own',
          targetChannelId: 'c-1',
        ),
        nowMs: 1000,
      );
      expect(await store.nextExpiryMs(), isNull,
          reason: 'not sent yet: nothing to count from');
      await store.applyAckSuccess(
          opId: 'op-own',
          messageId: 'm-own',
          serverTimestampMs: 5000,
          nowMs: 5000);
      expect((await store.fetchMessage('m-own'))!.expiresAtMs, 305000);
      await store.deleteExpiredMessages(nowMs: 305000, localUserId: 'u-self');
      expect(await store.fetchMessage('m-own'), isNull);
    });
  });

  group('secure messages', () {
    test(
        'the sealed secret is kept apart from the body, and a delete for '
        'everyone takes it', () async {
      await store.applyInboundMessage(
        localUserId: 'u-self',
        channelId: 'c-1',
        opId: 'op-s',
        messageId: 'm-s',
        senderUserId: 'u-peer',
        body: null,
        contentType: kSecureType,
        attachments: null,
        forwardSource: null,
        replyToMessageId: null,
        clientTimestampMs: 1000,
        serverTimestampMs: 1000,
        nowMs: 1000,
        secure: Uint8List.fromList([1, 2, 3]),
      );
      final m = (await store.fetchMessage('m-s'))!;
      expect([
        m.body,
        m.contentType,
        m.secure
      ], [
        null,
        kSecureType,
        [1, 2, 3]
      ]);
      await store.applyInboundMessageDelete(
          channelId: 'c-1',
          opId: 'op-del',
          messageId: 'm-s',
          senderUserId: 'u-peer',
          serverTimestampMs: 2000,
          nowMs: 2000);
      expect((await store.fetchMessage('m-s'))!.secure, isNull);
    });
  });

  group('delete for me', () {
    test('removes the rows here only, sends nothing, keeps the chat listed',
        () async {
      await inbound('m-1', 'u-peer', 'first', 1000);
      await inbound('m-2', 'u-self', 'second', 2000);
      await store.deleteMessagesLocal(['m-2']);

      expect(await store.fetchMessage('m-2'), isNull);
      expect(await store.db.query('outbound_ops'), isEmpty);
      var chats = await store.fetchChannelList();
      expect(chats.single.lastMessagePreview, 'first');

      await store.deleteMessagesLocal(['m-1']);
      chats = await store.fetchChannelList();
      expect(chats, hasLength(1),
          reason: 'like Clear chat, an emptied chat stays in the list');
    });
  });
}

/// A UUIDv7 op id minted at [ms].
String _op7(int ms) {
  final h = ms.toRadixString(16).padLeft(12, '0');
  return '${h.substring(0, 8)}-${h.substring(8)}-7000-8000-000000000001';
}
