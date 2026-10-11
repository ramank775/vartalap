import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';

void main() {
  test('dispatching an op moves only a pending message to sending', () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    addTearDown(store.close);
    await store.insertChannel(
      channelId: 'c1',
      kind: 'one_to_one',
      ownerUserId: 'u-me',
      createdAt: 1000,
    );
    Future<void> message(String id) => store.applyInboundMessage(
          localUserId: 'u-me',
          channelId: 'c1',
          opId: 'op-$id',
          messageId: id,
          senderUserId: 'u-peer',
          body: id,
          contentType: 'text/plain',
          attachments: null,
          forwardSource: null,
          replyToMessageId: null,
          clientTimestampMs: 1000,
          serverTimestampMs: 1000,
          nowMs: 1000,
        );
    await message('m-sent');
    await message('m-new');
    await store.db.update('messages', {'message_state': 'pending'},
        where: 'message_id = ?', whereArgs: ['m-new']);

    // An edit / reaction targeting an already-sent message.
    await store.markOpInFlight(opId: 'edit', messageId: 'm-sent', nowMs: 2000);
    // The create of a message that has not gone out yet.
    await store.markOpInFlight(opId: 'create', messageId: 'm-new', nowMs: 2000);

    expect((await store.fetchMessage('m-sent'))!.state, MessageState.sent);
    expect((await store.fetchMessage('m-new'))!.state, MessageState.sending);
  });
}
