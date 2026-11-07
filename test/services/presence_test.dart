/// Decision 223, track F: last seen and online (SYNC_PROTOCOL §22) and
/// the two privacy switches, as ChatService handles them.
library vartalap.services.presence_test;

import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const self = '0a11ce001';
const bob = '0b0b00002';
const carol = '0c0ffee03';

/// What the gateway pushes: [from]'s presence, as a DM frame from them.
InboundEnvelope presenceFrame(String from,
        {bool online = false,
        int lastSeenMs = 0,
        bool ephemeral = true,
        int? flags}) =>
    InboundEnvelope(
      opId: '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0001',
      channelId: dmChannelId(self, from),
      senderUserId: from,
      peer: self,
      payload: [
        0x53,
        ...pb.ServerEventPayload(
          version: 1,
          type: pb.ServerEventType.PRESENCE,
          presence: pb.Presence(
              userId: from,
              online: online,
              lastSeenMs: fixnum.Int64(lastSeenMs)),
        ).writeToBuffer(),
      ],
      ephemeral: ephemeral,
      flags: flags ?? FrameClass.presence.flags,
    );

void main() {
  setUpAll(sqfliteFfiInit);

  late ChatStore store;
  late SyncScheduler scheduler;
  late WsTransport ws;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await ChatStore.open(path: inMemoryDatabasePath);
    scheduler = SyncScheduler(
      store: store,
      wsTransport: _Offline(),
      restTransport: _Offline(),
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
      clock: FakeClock(5000),
    );
    ws = WsTransport(
      endpoint: Uri.parse('ws://example.invalid/wss'),
      auth: AuthClient(baseUrl: Uri.parse('http://example.invalid')),
    );
    chat = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: AuthClient(baseUrl: Uri.parse('http://localhost'))
        ..restoreSession(accesskey: 'a', userId: self),
      wsTransport: ws,
      uuidGen: Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(self)),
      clock: FakeClock(5000),
    );
    for (final peer in [bob, carol]) {
      final dm = dmChannelId(self, peer);
      await store.insertChannel(
          channelId: dm, kind: 'one_to_one', ownerUserId: self, createdAt: 1);
      for (final m in [self, peer]) {
        await store.insertChannelMember(
            channelId: dm, userId: m, role: 'member', joinedAt: 1);
      }
    }
  });

  tearDown(() async {
    chat.stopPresence();
    await store.close();
  });

  Future<void> push(InboundEnvelope env) async {
    ws.injectPush(env);
    await pumpEventQueue();
  }

  test('the watched peer\'s presence lands; anyone else\'s is ignored',
      () async {
    await chat.watchPresence(dmChannelId(self, bob));
    expect(chat.presence.value, isNull);

    await push(presenceFrame(bob, online: true));
    expect(chat.presence.value, (online: true, lastSeenMs: 0));
    await push(presenceFrame(carol, lastSeenMs: 99));
    expect(chat.presence.value, (online: true, lastSeenMs: 0),
        reason: 'not the chat on screen');
    await push(presenceFrame(bob, lastSeenMs: 1234));
    expect(chat.presence.value, (online: false, lastSeenMs: 1234));
    await push(presenceFrame(bob));
    expect(chat.presence.value, isNull, reason: 'the server says nothing');

    await push(presenceFrame(bob, online: true, ephemeral: false));
    await push(presenceFrame(bob, online: true, flags: FrameClass.event.flags));
    expect(chat.presence.value, isNull, reason: 'only an ephemeral PRESENCE');

    // another chat took over; the first one's close leaves it alone
    await chat.watchPresence(dmChannelId(self, carol));
    chat.unwatchPresence(dmChannelId(self, bob));
    await push(presenceFrame(carol, online: true));
    expect(chat.presence.value, (online: true, lastSeenMs: 0));

    chat.unwatchPresence(dmChannelId(self, carol));
    await pumpEventQueue();
    expect(chat.presence.value, isNull);
    await push(presenceFrame(carol, online: true));
    expect(chat.presence.value, isNull, reason: 'nobody watched');
  });

  test('a socket already up when the account opens hears we are on screen',
      () async {
    // Found on the emulators: the app's socket connects before the account
    // opens, and `state` does not replay, so nobody ever saw us online.
    final up = _UpAlready();
    final opened = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: AuthClient(baseUrl: Uri.parse('http://localhost'))
        ..restoreSession(accesskey: 'a', userId: self),
      wsTransport: up,
      uuidGen: Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(self)),
      clock: FakeClock(5000),
    );
    addTearDown(opened.stopPresence);
    expect(up.sent, hasLength(1));
    final body = pb.ServerEventPayload.fromBuffer(up.sent.single.sublist(1));
    expect(body.presence.online, isTrue);
  });

  test('a group watches nobody', () async {
    await chat.watchPresence('0190aaaa-bbbb-7ccc-8ddd-eeeeffff0009');
    await push(presenceFrame(bob, online: true));
    expect(chat.presence.value, isNull);
  });

  test('typing off: nobody\'s typing shows', () async {
    final source = StreamController<TypingEvent>();
    addTearDown(source.close);
    chat.bindTypingSource(source.stream);
    final seen = <TypingEvent>[];
    final sub = chat.typingEvents.listen(seen.add);
    addTearDown(sub.cancel);
    final event = TypingEvent(
        channelId: dmChannelId(self, bob),
        userId: bob,
        isTyping: true,
        emittedAtMs: 1);

    source.add(event);
    await pumpEventQueue();
    expect(seen, hasLength(1));
    await chat.setTypingIndicator(false);
    source.add(event);
    await pumpEventQueue();
    expect(seen, hasLength(1));
  });

  test('both switches are on by default and stay as set', () async {
    await chat.loadPrivacy();
    expect([chat.readReceipts.value, chat.typingIndicator.value], [true, true]);
    await chat.setReadReceipts(false);
    await chat.setTypingIndicator(false);
    chat
      ..readReceipts.value = true
      ..typingIndicator.value = true;
    await chat.loadPrivacy();
    expect(
        [chat.readReceipts.value, chat.typingIndicator.value], [false, false]);
  });
}

class _Offline implements Transport {
  @override
  TransportState get currentState => TransportState.disconnected;

  @override
  Stream<TransportState> get state => const Stream.empty();

  @override
  Stream<AckFrame> get acks => const Stream.empty();

  @override
  Future<void> send(OutboundFrame frame) async {}
}

/// A socket that is already connected and records what goes out.
class _UpAlready extends WsTransport {
  _UpAlready()
      : super(
          endpoint: Uri.parse('ws://example.invalid/wss'),
          auth: AuthClient(baseUrl: Uri.parse('http://example.invalid')),
        );

  final sent = <Uint8List>[];

  @override
  TransportState get currentState => TransportState.connected;

  @override
  bool sendEphemeral({
    required String opId,
    required String channelId,
    required Uint8List payload,
    String? peer,
    int flags = 0,
  }) {
    sent.add(payload);
    return true;
  }
}
