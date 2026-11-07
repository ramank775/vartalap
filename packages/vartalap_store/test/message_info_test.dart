import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';

/// Message info (SYNC_PROTOCOL §25.2), store side: when each member got
/// and read an own message, from the receipts that moved their markers.
void main() {
  late ChatStore store;
  const sentAt = 1700000000000;

  setUp(() async {
    store = await ChatStore.open(path: inMemoryDatabasePath);
    await store.insertChannel(
        channelId: 'g-1', kind: 'group', ownerUserId: 'me', createdAt: 1);
    for (final (user, joined) in [
      ('me', 1),
      ('asha', 1),
      ('ravi', 1),
      ('late', sentAt + 1),
    ]) {
      await store.insertChannelMember(
          channelId: 'g-1', userId: user, role: 'member', joinedAt: joined);
    }
    await store.applyInboundMessage(
      localUserId: 'me',
      channelId: 'g-1',
      opId: 'op-1',
      messageId: 'm-1',
      senderUserId: 'me',
      body: 'hello',
      contentType: null,
      attachments: null,
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: sentAt,
      serverTimestampMs: sentAt,
      nowMs: sentAt,
    );
  });
  tearDown(() => store.close());

  /// What InboundReceiver does with a receipt: move the marker, record it.
  Future<void> receipt(String user,
      {required bool read, required int upTo, required int at}) async {
    await store.db.rawUpdate(
      'UPDATE channel_members '
      'SET delivered_up_to = MAX(COALESCE(delivered_up_to, 0), ?)'
      '${read ? ', read_up_to = MAX(COALESCE(read_up_to, 0), ?)' : ''} '
      'WHERE channel_id = ? AND user_id = ?',
      [upTo, if (read) upTo, 'g-1', user],
    );
    await store.recordReceipt(
        channelId: 'g-1', userId: user, read: read, upTo: upTo, atMs: at);
  }

  Future<Map<String, (int?, int?)>> info() async => {
        for (final r in await store.fetchMessageReceipts('m-1', 'me'))
          r.userId: (r.deliveredAtMs, r.readAtMs),
      };

  test('each member it went to, with when they got it and read it', () async {
    expect(await info(), {'asha': (null, null), 'ravi': (null, null)},
        reason: 'not "me", not someone who joined after it was sent');

    await receipt('asha', read: false, upTo: sentAt, at: sentAt + 10);
    await receipt('asha', read: true, upTo: sentAt + 50, at: sentAt + 90);
    // Ravi read it straight away: the read is his delivery too.
    await receipt('ravi', read: true, upTo: sentAt, at: sentAt + 20);

    expect(await info(), {
      'asha': (sentAt + 10, sentAt + 90),
      'ravi': (sentAt + 20, sentAt + 20),
    });
  });

  test('a receipt arriving late still gives the earlier time', () async {
    await receipt('asha', read: true, upTo: sentAt + 50, at: sentAt + 90);
    await receipt('asha', read: true, upTo: sentAt, at: sentAt + 30);
    expect((await info())['asha'], (sentAt + 30, sentAt + 30));
    // One that adds nothing is not kept.
    await receipt('asha', read: false, upTo: sentAt, at: sentAt + 95);
    expect(await store.db.query('receipt_marks'), hasLength(2));
  });

  test('a marker from before the times were kept reads as done, time 0',
      () async {
    await store.db.rawUpdate(
        'UPDATE channel_members SET delivered_up_to = ? WHERE user_id = ?',
        [sentAt, 'ravi']);
    expect((await info())['ravi'], (0, null));
  });

  test('a receipt for a chat this phone does not hold is dropped', () async {
    await store.recordReceipt(
        channelId: 'g-nope', userId: 'asha', read: true, upTo: 1, atMs: 2);
    expect(await store.db.query('receipt_marks'), isEmpty);
  });
}
