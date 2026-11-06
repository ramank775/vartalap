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
          {String? opId}) =>
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
        nowMs: at,
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
