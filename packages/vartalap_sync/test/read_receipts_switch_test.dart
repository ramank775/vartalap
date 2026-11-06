import 'dart:async';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart'
    show InboundEnvelope, dmChannelId, uuidBytes;

const _self = '0abcdef12';
const _peer = '0aabbccdd';
const _group = '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0223';

/// Decision 223: with read receipts off, a DM peer's read receipt counts
/// as delivered only; a group's still reads.
void main() {
  test('read receipts off: a DM read shows as delivered, a group read as read',
      () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final pushes = StreamController<InboundEnvelope>();
    var on = false;
    final receiver = InboundReceiver(
      store: store,
      pushes: pushes.stream,
      localUserId: _self,
      dmReadReceipts: () => on,
    );
    await receiver.start();
    addTearDown(() async {
      await receiver.stop();
      await pushes.close();
      await store.close();
    });

    final dm = dmChannelId(_self, _peer);
    for (final (channel, kind) in [(dm, 'one_to_one'), (_group, 'group')]) {
      await store.insertChannel(
          channelId: channel, kind: kind, ownerUserId: _self, createdAt: 1);
      for (final u in [_self, _peer]) {
        await store.insertChannelMember(
            channelId: channel, userId: u, role: 'member', joinedAt: 1);
      }
    }
    for (final channel in [dm, _group]) {
      await store.db.insert('messages', {
        'message_id': 'own-$channel',
        'channel_id': channel,
        'author_user_id': _self,
        'client_timestamp_ms': 100,
        'server_timestamp_ms': 100,
        'message_state': MessageState.sent.wire,
        'state_updated_at': 1,
      });
    }
    var n = 0;
    Future<MessageState> read(String channel, {String? group}) async {
      n++;
      pushes.add(InboundEnvelope(
        opId: 'op-$n',
        channelId: dm,
        senderUserId: _peer,
        payload: pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_READ_RECEIPT,
          markerServerTimestampMs: fixnum.Int64(150),
          groupId: group == null ? null : uuidBytes(group),
        ).writeToBuffer(),
        serverTimestampMs: 400 + n,
      ));
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return (await store.fetchMessage('own-$channel'))!.state;
    }

    expect(await read(dm), MessageState.delivered);
    expect(await read(_group, group: _group), MessageState.read);
    on = true;
    expect(await read(dm), MessageState.read, reason: 'on again');
  });
}
