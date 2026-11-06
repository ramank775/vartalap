/// Live location (SYNC_PROTOCOL §21): the share's body, the frames it
/// queues, the inbound checks (only the sharer moves a share; only a
/// contact this phone allows turns it on or off), and when a share ends.
library;

import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/live_location.dart';
import 'package:vartalap/services/message_crypto.dart';
import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const _self = 'aaaaaaaaa';
const _peer = 'bbbbbbbbb';
const _other = 'ccccccccc';
const _group = '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0000';

class _FakePlatform extends LiveLocationPlatform {
  String answer = 'started';
  final starts = <({bool background, String? refusedTitle, String? title})>[];
  int changes = 0;

  @override
  Future<String> start(
      {bool background = false, String? refusedTitle, String? title}) async {
    starts.add(
        (background: background, refusedTitle: refusedTitle, title: title));
    return answer;
  }

  @override
  Future<void> changed() async => changes++;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late ChatStore store;
  late FakeClock clock;
  late _FakePlatform platform;
  late LiveLocation live;
  final dm = dmChannelId(_self, _peer);
  var ticks = 0;
  var op = 0;

  setUp(() async {
    store = await ChatStore.open(path: inMemoryDatabasePath);
    clock = FakeClock(1700000000000);
    platform = _FakePlatform();
    ticks = 0;
    live = LiveLocation(
      store: store,
      selfUserId: _self,
      tick: () => ticks++,
      clock: clock,
      platform: platform,
    );
    await store.insertChannel(
        channelId: dm, kind: 'one_to_one', ownerUserId: _self, createdAt: 1);
    await store.insertChannelMember(
        channelId: dm, userId: _peer, role: 'member', joinedAt: 1);
    await store.upsertContact(
        userId: _peer, contactBookName: 'Rahul', nowMs: 1);
    await store.insertChannel(
        channelId: _group,
        kind: 'group',
        ownerUserId: _self,
        createdAt: 1,
        name: 'Family');
  });

  tearDown(() => store.close());

  /// The ChatPayloads queued, oldest first.
  Future<List<pb.ChatPayload>> queued() async => [
        for (final r in await store.db.query('outbound_ops', orderBy: 'rowid'))
          pb.ChatPayload.fromBuffer(r['payload'] as List<int>)
      ];

  InboundEnvelope env(pb.ChatPayload chat,
          {String from = _peer, String? channelId, int at = 0}) =>
      InboundEnvelope(
        opId:
            '0190aaaa-bbbb-7ccc-8ddd-${(op++).toRadixString(16).padLeft(12, '0')}',
        channelId: channelId ?? dmChannelId(_self, from),
        senderUserId: from,
        payload: chat.writeToBuffer(),
        serverTimestampMs: at,
      );

  /// [from]'s share in [channelId], as an inbound message.
  Future<String> peerShare(String channelId,
      {String from = _peer, LiveShare? share}) async {
    const id = '0190aaaa-bbbb-7ccc-8ddd-000000000099';
    await store.applyInboundMessage(
      localUserId: _self,
      channelId: channelId,
      opId: '0190aaaa-bbbb-7ccc-8ddd-000000000098',
      messageId: id,
      senderUserId: from,
      body: (share ?? LiveShare(untilMs: clock.nowMs() + 3600000)).encode(),
      contentType: kLiveLocationType,
      attachments: null,
      forwardSource: null,
      replyToMessageId: null,
      clientTimestampMs: clock.nowMs(),
      serverTimestampMs: clock.nowMs(),
      nowMs: clock.nowMs(),
    );
    return id;
  }

  pb.ChatPayload point(String messageId, double lat, int atMs) =>
      pb.ChatPayload(
        version: 1,
        type: pb.ChatPayloadType.TYPE_LIVE_LOCATION_UPDATE,
        messageId: uuidBytes(messageId),
        liveLocationPoint: pb.LiveLocationPoint(
            lat: lat, lng: 77.5, accuracyM: 12, atMs: Int64(atMs)),
      );

  pb.ChatPayload control(int seconds) => pb.ChatPayload(
        version: 1,
        type: pb.ChatPayloadType.TYPE_LIVE_LOCATION_CONTROL,
        liveLocationDurationSec: seconds,
      );

  group('LiveShare', () {
    test('round-trips its body and ends at its time or when stopped', () {
      const s = LiveShare(
          untilMs: 2000,
          point: GeoPoint(12.5, 77.25, accuracyM: 9.6),
          atMs: 1500,
          by: _peer);
      final back = LiveShare.parse(s.encode())!;
      expect(back.untilMs, 2000);
      expect(back.point!.lat, 12.5);
      expect(back.point!.accuracyM, 10);
      expect(back.atMs, 1500);
      expect(back.by, _peer);
      expect(back.liveAt(1999), isTrue);
      expect(back.liveAt(2000), isFalse, reason: 'time is up');
      expect(back.ended(1600).liveAt(1700), isFalse, reason: 'stopped early');
      expect(LiveShare.parse('not json'), isNull);
      expect(LiveShare.parse('{"until":1,"lat":91,"lng":0}')!.point, isNull,
          reason: 'not a point on Earth');
    });
  });

  group('sharing', () {
    test('a share is a message that goes out at once; the service starts',
        () async {
      final started = await live.share(dm, const Duration(hours: 1),
          point: const GeoPoint(12.9, 77.6, accuracyM: 15));
      expect(started, 'started');
      expect(platform.starts.single.background, isFalse);

      final [create] = await queued();
      expect(create.type, pb.ChatPayloadType.TYPE_MESSAGE_CREATE);
      expect(create.contentType, kLiveLocationType);
      final share = LiveShare.parse(create.body)!;
      expect(share.untilMs, clock.nowMs() + 3600000);
      expect(share.point!.lat, 12.9);
      final row = await store.fetchMessage(uuidText(create.messageId));
      expect(row!.contentType, kLiveLocationType);
      expect((await live.shares()).single.channelId, dm);
      expect(ticks, greaterThan(0));
    });

    test('a share the service cannot start is stopped again', () async {
      platform.answer = 'refused';
      await live.share(dm, const Duration(minutes: 15));
      final ops = await queued();
      expect(ops.map((o) => o.type), [
        pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
        pb.ChatPayloadType.TYPE_LIVE_LOCATION_STOP,
      ]);
      expect(await live.shares(), isEmpty);
      expect(await live.status(), isNull);
    });

    test(
        'a position goes to every running share; one still unsent is '
        'replaced', () async {
      await live.share(dm, const Duration(hours: 1));
      await live.share(_group, const Duration(minutes: 15));
      await live.onFix(const GeoPoint(1, 2, accuracyM: 5), clock.nowMs());
      await live.onFix(const GeoPoint(3, 4), clock.nowMs() + 1);
      final updates = (await queued())
          .where((o) => o.type == pb.ChatPayloadType.TYPE_LIVE_LOCATION_UPDATE)
          .toList();
      expect(updates, hasLength(2), reason: 'one per share, the newest');
      expect(updates.every((u) => u.liveLocationPoint.lat == 3), isTrue);
      final mine = await live.shares();
      expect(mine.every((s) => s.share.point!.lat == 3), isTrue,
          reason: 'our own bubble keeps the newest position too');

      final status = (await live.status())!;
      expect(status['title'], 'Sharing live location');
      expect(status['text'], 'In 2 chats');
      expect(status['until'], clock.nowMs() + 3600000);
    });

    test('a share whose time is up gets no positions and drops out', () async {
      await live.share(dm, const Duration(minutes: 15));
      expect((await live.status())!['text'], 'With Rahul');
      clock.advance(const Duration(minutes: 15));
      await live.onFix(const GeoPoint(1, 2), clock.nowMs());
      expect((await queued()).length, 1, reason: 'only the create');
      expect(await live.status(), isNull, reason: 'the service stops');
    });

    test('Stop sends a stop once and ends the share; Stop all ends every one',
        () async {
      await live.share(dm, const Duration(hours: 1));
      final id = (await live.shares()).single.messageId;
      await live.stop(id);
      await live.stop(id);
      expect(
          (await queued()).where(
              (o) => o.type == pb.ChatPayloadType.TYPE_LIVE_LOCATION_STOP),
          hasLength(1));
      expect(LiveShare.parse((await store.fetchMessage(id))!.body)!.endedMs,
          clock.nowMs());
      expect(platform.changes, 1, reason: 'the service re-reads');

      await live.share(dm, const Duration(hours: 1));
      await live.share(_group, const Duration(hours: 1));
      await live.stopAll();
      expect(await live.shares(), isEmpty);
    });
  });

  test('app start brings the service back, or stops shares it cannot run',
      () async {
    await live.resume();
    expect(platform.starts, isEmpty, reason: 'nothing shared');
    await live.share(dm, const Duration(hours: 1));
    await live.resume();
    expect(platform.starts, hasLength(2));
    expect(await live.shares(), hasLength(1));
    platform.answer = 'permission';
    await live.resume();
    expect(await live.shares(), isEmpty);
  });

  group('inbound positions', () {
    test("only the sharer moves a share, and never back in time", () async {
      final id = await peerShare(dm);
      await live.apply(env(point(id, 10, 5000)), point(id, 10, 5000));
      var share = LiveShare.parse((await store.fetchMessage(id))!.body)!;
      expect(share.point!.lat, 10);
      expect(share.atMs, 5000);

      // older than what we have
      await live.apply(env(point(id, 11, 4000)), point(id, 11, 4000));
      // someone else, even in a chat they are in
      await live.apply(env(point(id, 12, 6000), from: _other, channelId: dm),
          point(id, 12, 6000));
      share = LiveShare.parse((await store.fetchMessage(id))!.body)!;
      expect(share.point!.lat, 10);

      final stop = pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_LIVE_LOCATION_STOP,
          messageId: uuidBytes(id));
      await live.apply(env(stop, at: 7000), stop);
      await live.apply(env(point(id, 13, 8000)), point(id, 13, 8000));
      share = LiveShare.parse((await store.fetchMessage(id))!.body)!;
      expect(share.endedMs, 7000);
      expect(share.point!.lat, 10, reason: 'a stopped share stays put');
    });
  });

  group('remote on/off', () {
    test('refused unless this phone allows the sender', () async {
      await live.apply(env(control(3600)), control(3600));
      expect(await live.shares(), isEmpty);
      expect(platform.starts, isEmpty);
    });

    test(
        'an allowed contact turns it on (their chat, held to 8 hours) and '
        'off', () async {
      await live.allow(_peer, true);
      await live.apply(env(control(24 * 3600)), control(24 * 3600));
      final [s] = await live.shares();
      expect(s.channelId, dm);
      expect(s.share.by, _peer);
      expect(s.share.untilMs, clock.nowMs() + 8 * 3600000);
      expect(platform.starts.single.background, isTrue);
      expect(platform.starts.single.refusedTitle,
          'Rahul asked to see your live location');
      expect(
          platform.starts.single.title, 'Rahul turned on your live location');
      expect((await live.status())!['title'],
          'Rahul turned on your live location');

      // a second "on" while sharing changes nothing
      await live.apply(env(control(900)), control(900));
      expect(await live.shares(), hasLength(1));

      await live.apply(env(control(0)), control(0));
      expect(await live.shares(), isEmpty);
    });

    test('refused once revoked, from someone else, and in a group', () async {
      await live.allow(_peer, true);
      await live.allow(_peer, false);
      await live.apply(env(control(900)), control(900));
      await live.apply(env(control(900), from: _other), control(900));
      await live.allow(_other, true);
      await live.apply(
          env(control(900), from: _other, channelId: _group), control(900));
      expect(await live.shares(), isEmpty);
      expect(platform.starts, isEmpty);
    });

    test('an "off" from a contact not allowed stops nothing', () async {
      await live.share(dm, const Duration(hours: 1));
      await live.apply(env(control(0)), control(0));
      expect(await live.shares(), hasLength(1));
    });

    test('the permission goes to the contact, whose phone records it',
        () async {
      await live.allow(_peer, true);
      final [permission] = await queued();
      expect(permission.type, pb.ChatPayloadType.TYPE_LIVE_LOCATION_PERMISSION);
      expect(permission.liveLocationAllowed, isTrue);
      final row = (await store.db.query('outbound_ops')).single;
      expect(row['peer'], _peer);
      expect(row['resource_id'], dm);

      expect(await live.allowedBy(_peer), isFalse);
      await live.apply(env(permission), permission);
      expect(await live.allowedBy(_peer), isTrue);
      expect(await live.allows(_peer), isTrue, reason: 'ours, set above');

      await live.remote(_peer, const Duration(hours: 1));
      expect((await queued()).last.liveLocationDurationSec, 3600);
      await live.remote(_peer, null);
      expect((await queued()).last.hasLiveLocationDurationSec(), isFalse,
          reason: '0 is off');
    });
  });

  test('a position is not kept for a re-send, so a request for one goes '
      'unanswered; a stop is re-sent', () async {
    await E2eeRecordStore.createSchema(store.db);
    final crypto = MessageCrypto(
      crypto: E2eeCrypto(
        db: store.db,
        records: E2eeRecordStore(store.db,
            accountId: _self, wrappingKey: Uint8List(32)),
        selfUserId: _self,
        selfDeviceId: 'phone-a',
        directory: (_) async => [],
        claim: (_, __, ___) => throw StateError('no keys here'),
      ),
      store: store,
      ws: _NoTransport(),
      selfUserId: _self,
      clock: clock,
    );
    final ops = <pb.ChatPayloadType, String>{};
    for (final (i, type) in [
      pb.ChatPayloadType.TYPE_LIVE_LOCATION_UPDATE,
      pb.ChatPayloadType.TYPE_LIVE_LOCATION_STOP,
    ].indexed) {
      final opId = ops[type] = '0190aaaa-bbbb-7ccc-8ddd-00000000000$i';
      final row = OutboundOpRow(
        opId: opId,
        transport: OpTransport.ws,
        kind: OpKind.chatPayload,
        restMethod: null,
        restPath: null,
        resourceId: _group,
        payload: pb.ChatPayload(type: type).writeToBuffer(),
        status: OpStatus.pending,
        attempts: 0,
        nextRetryAt: 0,
        dispatchedAt: null,
        lastError: null,
        acknowledgedAt: null,
        createdAt: 0,
        targetMessageId: null,
        targetChannelId: _group,
      );
      await store.enqueueOutboundOp(row);
      await crypto.seal(row, null);
    }
    // The peer joined after: their phone asks for both.
    await store.insertChannelMember(
        channelId: _group, userId: _peer, role: 'member', joinedAt: 2);
    final before = (await store.db.query('outbound_ops')).length;
    for (final opId in ops.values) {
      await crypto.open(InboundEnvelope(
        opId: '0190aaaa-bbbb-7ccc-8ddd-0000000000ff',
        channelId: dm,
        senderUserId: _peer,
        senderDeviceId: 'phone-b',
        payload: [
          kSealedMarker, kSealedVersion, 5,
          ...uuidBytes(opId), ...uuidBytes(_group),
        ],
      ));
    }
    final resent = (await store.db.query('outbound_ops',
            where: 'retry_of IS NOT NULL'))
        .map((r) => r['retry_of'])
        .toList();
    expect(resent, [ops[pb.ChatPayloadType.TYPE_LIVE_LOCATION_STOP]]);
    expect((await store.db.query('outbound_ops')).length, before + 1);
  });
}

class _NoTransport implements Transport {
  @override
  Future<void> send(OutboundFrame frame) async {}

  @override
  Stream<AckFrame> get acks => const Stream.empty();

  @override
  Stream<TransportState> get state => const Stream.empty();

  @override
  TransportState get currentState => TransportState.disconnected;
}
