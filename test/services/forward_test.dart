/// Forward (SYNC_PROTOCOL §25) through ChatService: a real store, a
/// scheduler whose transports never connect, so every op stays queued.
library vartalap.services.forward_test;

import 'dart:async';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const self = '0a11ce001';
const bob = '0b0b00002';
const group = '0190aaaa-0000-7000-8000-0000000000a1';
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
    await scheduler.start();
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
    for (final (id, kind) in [(dm, 'one_to_one'), (group, 'group')]) {
      await store.insertChannel(
          channelId: id, kind: kind, ownerUserId: self, createdAt: 1);
      for (final m in [self, bob]) {
        await store.insertChannelMember(
            channelId: id, userId: m, role: 'member', joinedAt: 1);
      }
    }
  });

  tearDown(() async {
    await scheduler.stop();
    await store.close();
  });

  /// A message from Bob in the DM.
  Future<MessageRow> received(
    String id, {
    String? body,
    String? contentType,
    List<pb.Attachment>? attachments,
    pb.ChatPayload? secure,
    pb.ForwardSource? forwarded,
    int? timerSec,
    int at = t0,
  }) async {
    await store.applyInboundMessage(
      localUserId: self,
      channelId: dm,
      opId: 'op-$id',
      messageId: id,
      senderUserId: bob,
      body: body,
      contentType: contentType,
      attachments: attachments == null
          ? null
          : pb.ChatPayload(attachments: attachments).writeToBuffer(),
      forwardSource: forwarded?.writeToBuffer(),
      replyToMessageId: null,
      clientTimestampMs: t0,
      serverTimestampMs: at,
      nowMs: t0,
      timerSec: timerSec,
      secure: secure?.writeToBuffer(),
    );
    return (await store.fetchMessage(id))!;
  }

  Future<List<pb.ChatPayload>> forwardOps(String channelId) async => [
        for (final op in await store.db.query('outbound_ops',
            where: 'resource_id = ?',
            whereArgs: [channelId],
            orderBy: 'created_at, op_id'))
          pb.ChatPayload.fromBuffer(op['payload'] as List<int>),
      ];

  /// An own photo whose upload has not run: its url is the local file.
  Future<void> uploadingPhoto(String channelId, String path) =>
      store.enqueueLocalMessage(
        message: MessageRow(
          messageId: '0190aaaa-0000-7000-8000-0000000000f1',
          channelId: channelId,
          authorUserId: self,
          body: null,
          contentType: 'image/jpeg',
          replyToMessageId: null,
          clientTimestampMs: t0 + 5000,
          serverTimestampMs: null,
          state: MessageState.pending,
          stateUpdatedAt: t0,
          isEdited: false,
          lastEditMs: null,
          tombstoned: false,
          tombstonePendingUntil: null,
          attachments: pb.ChatPayload(attachments: [
            pb.Attachment(url: path, mimeType: 'image/jpeg'),
          ]).writeToBuffer(),
        ),
        op: OutboundOpRow(
          opId: 'up-1',
          transport: OpTransport.asset,
          kind: OpKind.assetUpload,
          restMethod: null,
          restPath: null,
          resourceId: 'asset:x',
          payload: const [123, 125],
          status: OpStatus.pending,
          attempts: 0,
          nextRetryAt: t0 + 999999,
          dispatchedAt: null,
          lastError: null,
          acknowledgedAt: null,
          createdAt: t0,
          targetMessageId: '0190aaaa-0000-7000-8000-0000000000f1',
          targetChannelId: channelId,
        ),
        nowMs: t0,
      );

  test(
      'a forward carries the content unchanged as TYPE_MESSAGE_FORWARD, '
      'counted once, to every chat picked, oldest first', () async {
    final photo = pb.Attachment(
      url: 'file-1#a2V5',
      mimeType: 'image/jpeg',
      sizeBytes: fixnum.Int64(1234),
      width: 4,
      height: 3,
    );
    final sealed = sealSecret('hunter2');
    final text = await received('m-1', body: 'hello');
    final pic = await received('m-2',
        body: 'caption',
        contentType: 'image/jpeg',
        attachments: [photo],
        at: t0 + 1);
    final secret = await received('m-3',
        at: t0 + 2,
        contentType: kSecureType,
        secure: pb.ChatPayload(secureBox: sealed.box, secureKey: sealed.key));

    await chat.forwardMessages(
      messages: [secret, pic, text],
      channelIds: [dm, group],
      authorUserId: self,
    );

    for (final channel in [dm, group]) {
      final sent = await forwardOps(channel);
      expect(sent, hasLength(3));
      expect(sent.map((p) => p.type),
          everyElement(pb.ChatPayloadType.TYPE_MESSAGE_FORWARD));
      expect(sent.map((p) => p.forwardSource.forwardCount), everyElement(1));
      expect(sent.map((p) => p.forwardSource.sourceMessageId),
          everyElement(isEmpty),
          reason: 'a message id carries its author: never sent on');
      expect(sent.map((p) => p.hasReplyToMessageId()), everyElement(isFalse));
      expect(sent[0].body, 'hello');
      expect(sent[1].body, 'caption');
      expect(sent[1].attachments.single, photo,
          reason: 'the same url: nothing is uploaded again');
      expect(sent[2].secureBox, sealed.box,
          reason: 'decision 222: copied byte for byte, never re-sealed');
      expect(sent[2].secureKey, sealed.key);
      expect(sent[2].hasBody(), isFalse);
    }
    final mine = [
      for (final m in await store.fetchChannelMessages(group))
        if (m.authorUserId == self) m,
    ];
    expect(mine, hasLength(3));
    expect(mine.map(ChatService.forwardCount), everyElement(1));
    expect(mine.map((m) => m.state), everyElement(MessageState.pending));
  });

  test('forwarding a forward counts it again', () async {
    final m = await received('m-4',
        body: 'pass it on', forwarded: pb.ForwardSource(forwardCount: 4));
    expect(ChatService.forwardCount(m), 4);
    await chat.forwardMessages(
        messages: [m], channelIds: [group], authorUserId: self);
    final sent = (await forwardOps(group)).single;
    expect(sent.forwardSource.forwardCount, kForwardedManyTimes);
  });

  test(
      'not forwardable: deleted, waiting, live location, timed, an upload '
      'still on this phone', () async {
    final ok = await received('m-5', body: 'fine');
    expect(ChatService.canForward(ok), isTrue);
    final live = await received('m-6',
        body: '{"until":1}', contentType: kLiveLocationType);
    final timed = await received('m-7', body: 'OTP 1234', timerSec: 3600);
    final waiting = await received('m-8', contentType: kUndecryptedType);
    for (final m in [live, timed, waiting]) {
      expect(ChatService.canForward(m), isFalse, reason: m.contentType);
    }
    await uploadingPhoto(dm, '/data/user/0/files/assets/1/a.jpg');
    final uploading = (await store.fetchChannelMessages(dm)).first;
    expect(ChatService.canForward(uploading), isFalse);
    await store.applyInboundMessageDelete(
      channelId: dm,
      opId: 'del-5',
      messageId: 'm-5',
      senderUserId: bob,
      serverTimestampMs: t0 + 1,
      nowMs: t0 + 1,
      madeAtMs: t0 + 1,
    );
    expect(ChatService.canForward((await store.fetchMessage('m-5'))!), isFalse);
    expect(
        () => chat.forwardMessages(
            messages: [timed], channelIds: [group], authorUserId: self),
        throwsArgumentError);
  });
}

class _Offline implements Transport {
  @override
  Stream<AckFrame> get acks => const Stream.empty();
  @override
  Stream<TransportState> get state => const Stream.empty();
  @override
  TransportState get currentState => TransportState.disconnected;
  @override
  Future<void> send(OutboundFrame frame) async {}
}
