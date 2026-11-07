/// Event replies and video thumbnails through ChatService (SYNC_PROTOCOL
/// §25.3, §25.4): a real store, a scheduler that never connects.
library vartalap.services.chat_media_test;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const self = '0a11ce001';
const bob = '0b0b00002';
const t0 = 1700000000000;

void main() {
  setUpAll(sqfliteFfiInit);

  late ChatStore store;
  late SyncScheduler scheduler;
  late ChatService chat;
  final dm = dmChannelId(self, bob);

  setUp(() async {
    store = await ChatStore.open(path: inMemoryDatabasePath);
    scheduler = SyncScheduler(
      store: store,
      wsTransport: _Offline(),
      restTransport: _Offline(),
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
      clock: FakeClock(t0),
    );
    chat = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: AuthClient(baseUrl: Uri.parse('http://localhost'))
        ..restoreSession(accesskey: 'a', userId: self),
      wsTransport: WsTransport(
        endpoint: Uri.parse('ws://example.invalid/wss'),
        auth: AuthClient(baseUrl: Uri.parse('http://example.invalid')),
      ),
      uuidGen: Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(self)),
      clock: FakeClock(t0),
    );
    await store.insertChannel(
        channelId: dm, kind: 'one_to_one', ownerUserId: self, createdAt: 1);
  });

  tearDown(() async {
    await scheduler.stop();
    await store.close();
  });

  Future<OutboundOpRow> onlyOp() async =>
      (await store.selectDispatchable(now: t0 + 1)).single;

  test(
      'an answer to an event is ours at once and goes as a silent '
      'TYPE_EVENT_RSVP', () async {
    const event = '0190aaaa-0000-7000-8000-0000000000e1';
    await store.applyInboundMessage(
      localUserId: self,
      channelId: dm,
      opId: 'op-e',
      messageId: event,
      senderUserId: bob,
      body: 'BEGIN:VCALENDAR',
      contentType: 'text/calendar',
      attachments: null,
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: t0,
      serverTimestampMs: t0,
      nowMs: t0,
    );
    await chat.rsvp(
        channelId: dm, messageId: event, userId: self, going: true);

    final op = await onlyOp();
    final p = pb.ChatPayload.fromBuffer(op.payload);
    expect(p.type, pb.ChatPayloadType.TYPE_EVENT_RSVP);
    expect(p.eventRsvp, pb.EventRsvp.EVENT_RSVP_GOING);
    expect(uuidText(p.messageId), event);
    expect(op.kind, OpKind.messageReaction,
        reason: 'class MUTATION, silent, nothing to roll back');
    expect((await store.fetchChannelMessages(dm)).single.rsvps, {self: true});
  });

  test('a video goes with its thumbnail in the attachment', () async {
    final dir = await Directory.systemTemp.createTemp('chat_media_test');
    addTearDown(() => dir.delete(recursive: true));
    final video = File('${dir.path}/clip.mp4')..writeAsBytesSync([1, 2, 3]);
    final thumb = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);

    await chat.sendAttachment(
      channelId: dm,
      authorUserId: self,
      path: video.path,
      width: 720,
      height: 1280,
      durationMs: 4000,
      thumbnail: thumb,
    );

    final shown = pb.ChatPayload.fromBuffer(
            (await store.fetchChannelMessages(dm)).single.attachments!)
        .attachments
        .single;
    expect(shown.thumbnail, thumb);
    expect([shown.width, shown.height, shown.durationMs], [720, 1280, 4000]);
    // The upload op carries it on to the MESSAGE_CREATE built after it.
    expect((await onlyOp()).kind, OpKind.assetUpload);
  });
}

class _Offline implements Transport {
  @override
  Future<void> send(OutboundFrame frame) async {}
  @override
  Stream<AckFrame> get acks => const Stream.empty();
  @override
  Stream<TransportState> get state => const Stream.empty();
  @override
  TransportState get currentState => TransportState.disconnected;
}
