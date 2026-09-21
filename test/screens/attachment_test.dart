/// Attachments — V3_RELEASE_PLAN §4.2, mockup frames d1 and e.
///
/// Real [ChatStore] and [ChatService]; the transports are stubs that
/// stay disconnected, so every op parks in `outbound_ops` where the
/// assertions can read it. Bytes come from a [FakeAssetCache] instead
/// of a presigned download.
library vartalap.screens.attachment_test;

import 'dart:io';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/screens/chat_info/media.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

import '../fake_asset_cache.dart';

const String channelId = 'c-1';
const String localUserId = 'aaaaaaaaa';
const String peerUserId = 'bbbbbbbbb';

void main() {
  setUpAll(sqfliteFfiInit);

  late ChatStore store;
  late SyncScheduler scheduler;
  late ChatService chat;
  late Directory tmp;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pump();
  }

  Future<void> boot(WidgetTester tester) async {
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('vartalap_attach');
      store = await ChatStore.open(path: inMemoryDatabasePath);
      final auth = AuthClient(baseUrl: Uri.parse('https://example.invalid'));
      scheduler = SyncScheduler(
        store: store,
        wsTransport: _StubTransport(),
        restTransport: _StubTransport(),
        backoff: const FixedBackoff(Duration(milliseconds: 10)),
      );
      chat = ChatService(
        store: store,
        scheduler: scheduler,
        authClient: auth,
        wsTransport: WsTransport(
          endpoint: Uri.parse('ws://example.invalid'),
          auth: auth,
        ),
        uuidGen: Uuid7Gen(userIdBits: 0xAAAAAAAAA),
        clock: Clock.system,
      );
      await store.insertChannel(
        channelId: channelId,
        kind: 'group',
        ownerUserId: localUserId,
        createdAt: 1000,
      );
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      AssetCache.instance = null;
      await scheduler.stop();
      await store.close();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
  }

  testWidgets(
      'sending an image queues an upload op and shows the picked file in '
      'the bubble straight away', (tester) async {
    await boot(tester);

    late String messageId;
    await tester.runAsync(() async {
      final file = File('${tmp.path}/holiday.png')
        ..writeAsBytesSync(onePixelPng);
      messageId = await chat.sendAttachment(
        channelId: channelId,
        authorUserId: localUserId,
        path: file.path,
        width: 1,
        height: 1,
      );
      AssetCache.instance = FakeAssetCache({file.path: onePixelPng});
    });

    final row = await tester.runAsync(() => store.fetchMessage(messageId));
    expect(
      row!.state,
      MessageState.pending,
      reason: 'The row is local-first: it exists before anything is '
          'uploaded, exactly like a text send.',
    );
    expect(row.contentType, 'image/png');
    final attachment =
        pb.ChatPayload.fromBuffer(row.attachments!).attachments.single;
    expect(
      attachment.url,
      endsWith('holiday.png'),
      reason: 'Until the upload lands the attachment points at the local '
          'copy, which is what the bubble renders.',
    );
    expect(attachment.mimeType, 'image/png');
    expect(attachment.sizeBytes.toInt(), onePixelPng.length);

    final ops = await tester.runAsync(
      () => store.db.query('outbound_ops', orderBy: 'created_at'),
    );
    expect(
      ops!.map((o) => o['kind']),
      [OpKind.assetUpload],
      reason: 'The only op so far is the upload — the MESSAGE_CREATE '
          'cannot exist until there is a fileId to put in it.',
    );
    expect(ops.single['transport'], 'asset');
    expect(
      ops.single['resource_id'],
      isNot(channelId),
      reason: 'SYNC_PROTOCOL §6: an upload never reaches the server, so it '
          "must not spend one of the channel's resource_seq numbers.",
    );

    // The picked file renders through the cache like any other asset.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssetImageView(
          uri: attachment.url,
          placeholder: const AssetImagePlaceholder(),
        ),
      ),
    ));
    await settle(tester);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the media screen grids images and lists documents below',
      (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      await _inbound(store, 'm-img', 'image/png', 'shot.png', 1);
      await _inbound(store, 'm-doc', 'application/pdf', 'accounts.pdf', 2);
    });
    AssetCache.instance = FakeAssetCache({'shot.png': onePixelPng});

    await tester.pumpWidget(MaterialApp(
      home: MediaScreen(
        channelId: channelId,
        chatService: chat,
        cache: AssetCache.instance,
      ),
    ));
    await settle(tester);

    expect(
      find.byType(AssetImageView),
      findsOneWidget,
      reason: 'One image attachment → one thumbnail tile.',
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
      find.text('accounts.pdf'),
      findsOneWidget,
      reason: 'Non-image attachments are listed under Documents, not in '
          'the grid.',
    );
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Nothing shared yet'), findsNothing);
  });
}

Future<void> _inbound(
  ChatStore store,
  String messageId,
  String mimeType,
  String filename,
  int seq,
) =>
    store.applyInboundMessage(
      localUserId: localUserId,
      channelId: channelId,
      opId: 'seed-$messageId',
      messageId: messageId,
      senderUserId: peerUserId,
      body: '',
      contentType: mimeType,
      attachments: pb.ChatPayload(
        attachments: [
          pb.Attachment(
            url: filename,
            mimeType: mimeType,
            filename: filename,
            sizeBytes: fixnum.Int64(2048),
          ),
        ],
      ).writeToBuffer(),
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: 1000 + seq,
      serverTimestampMs: 1000 + seq,
      deliverySequence: seq,
      nowMs: 1000 + seq,
    );

/// Disconnected on purpose — ops park in the queue.
class _StubTransport implements Transport {
  @override
  Stream<AckFrame> get acks => const Stream.empty();

  @override
  Stream<TransportState> get state => const Stream.empty();

  @override
  TransportState get currentState => TransportState.disconnected;

  @override
  Future<void> send(OutboundFrame frame) async {}
}
