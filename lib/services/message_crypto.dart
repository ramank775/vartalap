import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Transaction;
import 'package:vartalap_crypto/vartalap_crypto.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// The app's half of decision 188: which ops seal how, who a group's key
/// goes to, and how a key hand-out reaches the wire. AppServices and the
/// golden-path harness share it.
class MessageCrypto {
  final E2eeCrypto crypto;
  final ChatStore store;
  final Transport ws;
  final String selfUserId;
  final Uuid7Gen _opIds;
  final Clock clock;

  MessageCrypto({
    required this.crypto,
    required this.store,
    required this.ws,
    required this.selfUserId,
    this.clock = Clock.system,
  }) : _opIds = Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(selfUserId));

  /// [SyncScheduler.seal]: a DM op for its peer, a group op for every
  /// member, the sealed bytes kept on the op's row.
  Future<List<int>> seal(OutboundOpRow op, String? peer) async {
    final payload = Uint8List.fromList(op.payload);
    Future<void> persist(Transaction txn, Uint8List sealed) =>
        ChatStore.storeSealedPayload(txn, op.opId, sealed);
    final sealed = peer != null
        ? await crypto.sealDm(
            opId: op.opId,
            channelId: op.resourceId,
            peer: peer,
            payload: payload,
            persist: persist)
        : await _sealGroup(op.opId, op.resourceId, payload, persist: persist);
    return sealed!;
  }

  /// A typing indicator: sealed only over what is already set up (a
  /// session, a handed-out group key), else null and not sent.
  Future<Uint8List?> sealTyping({
    required String opId,
    required String channelId,
    required String? peer,
    required Uint8List payload,
  }) =>
      peer != null
          ? crypto.sealDm(
              opId: opId,
              channelId: channelId,
              peer: peer,
              payload: payload,
              ephemeral: true,
              onlyIfSession: true)
          : _sealGroup(opId, channelId, payload,
              ephemeral: true, onlyIfDistributed: true);

  Future<Uint8List?> _sealGroup(String opId, String channelId, Uint8List payload,
      {bool ephemeral = false,
      bool onlyIfDistributed = false,
      Future<void> Function(Transaction txn, Uint8List sealed)? persist}) async {
    final members = {
      for (final m in await store.fetchChannelMembers(channelId))
        if (m.userId != selfUserId) m.userId
    };
    return crypto.sealGroup(
      opId: opId,
      channelId: channelId,
      members: members,
      payload: payload,
      dmChannel: (member) => dmChannelId(selfUserId, member),
      newOpId: () => _opIds.next(nowMs: clock.nowMs()),
      sendKey: _sendKey,
      ephemeral: ephemeral,
      onlyIfDistributed: onlyIfDistributed,
      persist: persist,
    );
  }

  /// A group key goes out on the member's 1:1 channel, ahead of the group
  /// op on the same socket. Not queued: if it is lost, the member's phone
  /// asks again when a message will not open.
  Future<void> _sendKey(
          String member, String channelId, String opId, Uint8List sealed) =>
      ws.send(OutboundFrame(
        kind: OpKind.chatPayload,
        resourceId: channelId,
        peer: member,
        ops: [
          FramedOp(opId: opId, payload: sealed, clientTimestampMs: clock.nowMs())
        ],
      ));

  /// [InboundReceiver.open].
  Future<List<int>> open(pb.Envelope env) => crypto.open(env);

  /// [InboundReceiver.applied].
  Future<void> applied(pb.Envelope env) => crypto.applied(env);
}
