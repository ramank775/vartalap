import 'dart:async';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart'
    show InboundEnvelope, dmChannelId;

// SYNC_PROTOCOL §23: the invite events, as the inbound receiver applies them.

const _me = '0aaaaaaa1';
const _ravi = '0bbbbbbb2';
const _li = '0ccccccc3';
const _group = '01efabcd-7000-8000-8abc-000000000001';

void main() {
  late ChatStore store;
  late StreamController<InboundEnvelope> pushes;
  late InboundReceiver receiver;
  var n = 0;

  setUp(() async {
    store = await ChatStore.open(path: inMemoryDatabasePath);
    pushes = StreamController<InboundEnvelope>.broadcast();
    receiver = InboundReceiver(
      store: store,
      pushes: pushes.stream,
      localUserId: _me,
      clock: FakeClock(1000),
    );
    await receiver.start();
  });

  tearDown(() async {
    await receiver.stop();
    await pushes.close();
    await store.close();
  });

  /// One server event from [actor], as the transport hands it over: a
  /// 1:1 one on the pair's DM id, a group's on the group.
  Future<void> push(String actor, pb.ServerEventPayload event,
      {String? channelId}) async {
    n++;
    pushes.add(InboundEnvelope(
      opId: '01efabcd-7000-8000-8abc-0000000000${n.toString().padLeft(2, '0')}',
      channelId: channelId ?? dmChannelId(actor, _me),
      senderUserId: actor,
      payload: [0x53, ...event.writeToBuffer()],
      serverTimestampMs: 5000 + n,
    ));
    await receiver.drainPending();
  }

  pb.ServerEventPayload sent(
          {String group = '',
          List<String> users = const [],
          String name = ''}) =>
      pb.ServerEventPayload(
        version: 1,
        type: pb.ServerEventType.INVITE_SENT,
        inviteSent: pb.InviteSent(
            channelId: group, users: users, name: name, atMs: fixnum.Int64(42)),
      );

  pb.ServerEventPayload answered(String user, pb.InviteAnswer answer,
          {String group = ''}) =>
      pb.ServerEventPayload(
        version: 1,
        type: pb.ServerEventType.INVITE_ANSWERED,
        inviteAnswered:
            pb.InviteAnswered(channelId: group, user: user, answer: answer),
      );

  test('a 1:1 invite to us is stored, and announced so it notifies', () async {
    final announced = receiver.peerMessagesStored.first;
    await push(_ravi, sent(users: [_me]));
    final [invite] = await store.fetchInvites();
    expect((invite.channelId, invite.fromUser, invite.toUser, invite.createdAt),
        (dmChannelId(_ravi, _me), _ravi, _me, 42));
    expect(await announced, dmChannelId(_ravi, _me));
    expect(await store.channelExists(dmChannelId(_ravi, _me)), isFalse,
        reason: 'no chat in the list until it is accepted');

    // taken back
    await push(_ravi, answered(_me, pb.InviteAnswer.INVITE_CANCELED));
    expect(await store.fetchInvites(), isEmpty);
  });

  test('our invite accepted: connected, and the chat says so', () async {
    final dm = dmChannelId(_me, _ravi);
    await store.putInvite(
        InviteRow(channelId: dm, toUser: _ravi, fromUser: _me, createdAt: 1));
    await push(_ravi, answered(_ravi, pb.InviteAnswer.INVITE_ACCEPTED));
    expect(await store.fetchInvites(), isEmpty);
    expect((await store.peerLink(_me, _ravi)).connected, isTrue);
    final lines = await store.fetchChannelMessages(dm);
    expect(GroupEvent.parse(lines.single.body)!.kind, GroupEventKind.accepted);
    expect(lines.single.authorUserId, _ravi);
  });

  test('a group invite: to us with its name; in ours, "Invited" and a line',
      () async {
    await push(_ravi, sent(group: _group, users: [_me], name: 'Family'),
        channelId: _group);
    final [mine] = await store.fetchInvites();
    expect((mine.toUser, mine.name, mine.isGroup), (_me, 'Family', true));

    await store.removeInvites(_group);
    await store.insertChannel(
        channelId: _group, kind: 'group', ownerUserId: _ravi, createdAt: 1);
    await push(_ravi, sent(group: _group, users: [_li]), channelId: _group);
    expect([for (final i in await store.fetchInvites()) i.toUser], [_li]);
    final lines = await store.fetchChannelMessages(_group);
    final line = GroupEvent.parse(lines.single.body)!;
    expect(line.kind, GroupEventKind.invited);
    expect(line.users, [_li]);

    // declined: no longer invited
    await push(
        _li, answered(_li, pb.InviteAnswer.INVITE_DECLINED, group: _group),
        channelId: _group);
    expect(await store.fetchInvites(), isEmpty);

    // accepted: ChannelMemberAdded with the newcomer as actor
    await store.putInvite(const InviteRow(
        channelId: _group, toUser: _li, fromUser: _ravi, createdAt: 1));
    await push(
        _li,
        pb.ServerEventPayload(
          version: 1,
          type: pb.ServerEventType.CHANNEL_MEMBER_ADDED,
          memberAdded: pb.ChannelMemberAdded(
              channelId: _group, members: [_li], addedAtMs: fixnum.Int64(7)),
        ),
        channelId: _group);
    expect(await store.fetchInvites(), isEmpty);
  });
}
