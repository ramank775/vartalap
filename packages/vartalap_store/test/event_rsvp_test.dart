import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';

/// Event replies (decision 134, SYNC_PROTOCOL §25.3), store side.
void main() {
  late ChatStore store;

  setUp(() async {
    store = await ChatStore.open(path: inMemoryDatabasePath);
    await store.insertChannel(
        channelId: 'g-1', kind: 'group', ownerUserId: 'me', createdAt: 1);
  });
  tearDown(() => store.close());

  Future<void> message(String id, String contentType) =>
      store.applyInboundMessage(
        localUserId: 'me',
        channelId: 'g-1',
        opId: 'op-$id',
        messageId: id,
        senderUserId: 'asha',
        body: 'BEGIN:VCALENDAR',
        contentType: contentType,
        attachments: null,
        forwardSource: null,
        replyToMessageId: null,
        clientTimestampMs: 100,
        serverTimestampMs: 100,
        nowMs: 100,
      );

  Future<bool> answer(String who, bool going, int at,
          {String target = 'ev-1'}) =>
      store.applyInboundRsvp(
        channelId: 'g-1',
        opId: 'rsvp-$who-$at',
        messageId: target,
        senderUserId: who,
        going: going,
        serverTimestampMs: at,
        nowMs: at,
      );

  Future<Map<String, bool>> answers(String id) async =>
      (await store.fetchChannelMessages('g-1'))
          .firstWhere((m) => m.messageId == id)
          .rsvps;

  test('each person\'s newest answer counts, whatever order they land in',
      () async {
    await message('ev-1', 'text/calendar');
    expect(await answer('ravi', true, 200), isTrue);
    await answer('ravi', false, 300);
    await answer('ravi', true, 250); // older: ignored
    await answer('meena', true, 210);
    expect(await answers('ev-1'), {'ravi': false, 'meena': true});
  });

  test('an answer that beats its event waits for it (6b)', () async {
    expect(await answer('ravi', true, 200), isFalse);
    await message('ev-1', 'text/calendar');
    expect(await answers('ev-1'), {'ravi': true});
  });

  test('only an event takes answers', () async {
    await message('m-1', 'text/plain');
    expect(await answer('ravi', true, 200, target: 'm-1'), isFalse);
    expect(await answers('m-1'), isEmpty);
  });

  test('our own answer is there at once, with its op queued', () async {
    await message('ev-1', 'text/calendar');
    await store.enqueueRsvp(
      messageId: 'ev-1',
      userId: 'me',
      going: true,
      nowMs: 500,
      op: const OutboundOpRow(
        opId: 'op-r',
        transport: OpTransport.ws,
        kind: OpKind.messageReaction,
        restMethod: null,
        restPath: null,
        resourceId: 'g-1',
        payload: [8],
        status: OpStatus.pending,
        attempts: 0,
        nextRetryAt: 500,
        dispatchedAt: null,
        lastError: null,
        acknowledgedAt: null,
        createdAt: 500,
        targetMessageId: 'ev-1',
        targetChannelId: 'g-1',
      ),
    );
    expect(await answers('ev-1'), {'me': true});
    expect(await store.db.query('outbound_ops'), hasLength(1));
  });
}
