import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Transaction;
import 'package:vartalap_crypto/vartalap_crypto.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// A re-send request (decision 188): kind 5 after the 0x45 marker and
/// version, then JSON `{"op": op id, "ch": channel id}`. Not encrypted: it
/// carries only ids, and the session it would ride may be the broken one.
const int _kindResendRequest = 5;

/// The app's half of decision 188: which ops seal how, who a group's key
/// goes to, how a key hand-out reaches the wire, and the "Waiting for this
/// message" re-send. AppServices and the golden-path harness share it.
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
  }) : _opIds = Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(selfUserId)) {
    crypto.identityChanges.listen(_noteSecurityCode);
  }

  /// Decision 184, WhatsApp style: a contact's new key is accepted and
  /// every chat with them says so.
  Future<void> _noteSecurityCode(String userId) async {
    final now = clock.nowMs();
    for (final chat in await store.fetchMemberChannels(userId: userId)) {
      await store.insertGroupEvent(
        channelId: chat.channelId,
        // message ids are unique across chats: one shared id would land
        // in the first chat only
        messageId: 'sc-$userId-${chat.channelId}-$now',
        actorUserId: userId,
        event: GroupEvent(GroupEventKind.securityCode, users: [userId]),
        atMs: now,
      );
    }
  }

  /// Wakes the scheduler for an op this queued (a re-send or its request).
  void Function()? tick;

  String _newOpId() => _opIds.next(nowMs: clock.nowMs());

  static bool _isResendRequest(List<int> p) =>
      p.length > 3 &&
      p[0] == kSealedMarker &&
      p[1] == 1 &&
      p[2] == _kindResendRequest;

  /// [SyncScheduler.seal]: a DM op for its peer, a group op for every
  /// member, the sealed bytes kept on the op's row. A re-send names the op
  /// it replaces inside the authenticated header.
  Future<List<int>> seal(OutboundOpRow op, String? peer) async {
    if (_isResendRequest(op.payload)) return op.payload;
    final payload = Uint8List.fromList(op.payload);
    final retryOf = op.retryOf ?? '';
    Future<void> persist(Transaction txn, Uint8List sealed) async {
      await ChatStore.storeSealedPayload(txn, op.opId, sealed);
      // A re-send is never re-sent again.
      if (op.retryOf == null) {
        await crypto.rememberSent(txn, op.opId, {
          'ch': op.resourceId,
          'kind': op.kind,
          'peer': peer,
          'payload': base64.encode(payload),
        });
      }
    }
    final sealed = peer != null
        ? await crypto.sealDm(
            opId: op.opId,
            channelId: op.resourceId,
            peer: peer,
            payload: payload,
            retryOf: retryOf,
            persist: persist)
        : await _sealGroup(op.opId, op.resourceId, payload,
            retryOf: retryOf, persist: persist);
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

  Future<Set<String>> _members(String channelId) async => {
        for (final m in await store.fetchChannelMembers(channelId))
          if (m.userId != selfUserId) m.userId
      };

  Future<Uint8List?> _sealGroup(String opId, String channelId, Uint8List payload,
      {bool ephemeral = false,
      bool onlyIfDistributed = false,
      String retryOf = '',
      Future<void> Function(Transaction txn, Uint8List sealed)? persist}) async {
    final members = await _members(channelId);
    return crypto.sealGroup(
      opId: opId,
      channelId: channelId,
      members: members,
      payload: payload,
      dmChannel: (member) => dmChannelId(selfUserId, member),
      newOpId: _newOpId,
      sendKey: _sendKey,
      ephemeral: ephemeral,
      onlyIfDistributed: onlyIfDistributed,
      retryOf: retryOf,
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

  /// [InboundReceiver.open]: null for an op that will never open here.
  Future<OpenedPayload?> open(pb.Envelope env) async {
    if (_isResendRequest(env.payload)) {
      await _onResendRequest(env);
      return (payload: const <int>[], retryOf: '');
    }
    try {
      final opened = await crypto.open(env);
      return (payload: opened.payload, retryOf: opened.retryOf);
    } on E2eeUndecryptable {
      return null;
    }
  }

  /// [InboundReceiver.applied].
  Future<void> applied(pb.Envelope env) => crypto.applied(env);

  /// [InboundReceiver.undecryptable]: ask the sender's phone, on our 1:1
  /// channel with them, to re-send [env].
  Future<void> requestResend(pb.Envelope env) async {
    final sender = env.senderUserId;
    await store.enqueueOutboundOp(_op(
      channelId: dmChannelId(selfUserId, sender),
      peer: sender,
      payload: [
        kSealedMarker,
        1,
        _kindResendRequest,
        ...utf8.encode(jsonEncode({'op': env.opId, 'ch': env.channelId})),
      ],
    ));
    tick?.call();
  }

  /// [env]'s sender could not open one of ours: re-send it once, sealed
  /// afresh for its current phone, under a new op id that names the old.
  Future<void> _onResendRequest(pb.Envelope env) async {
    final requester = env.senderUserId;
    final Map<String, dynamic> ask;
    try {
      ask = jsonDecode(utf8.decode(env.payload.sublist(3)))
          as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final channelId = '${ask['ch']}';
    // Only for a recipient of the op: a member of the group, the DM's peer.
    final group = !isDmChannelId(channelId);
    if (group
        ? !(await _members(channelId)).contains(requester)
        : channelId != dmChannelId(selfUserId, requester)) {
      return;
    }
    final opId = '${ask['op']}';
    final sent = await crypto.takeForResend(opId);
    if (sent == null || sent['ch'] != channelId) return;
    await crypto.resetSession(requester, env.senderDeviceId);
    if (group) await crypto.forgetKeyHolder(channelId, requester);
    // No message id on the row: its ACK must not restamp our own copy.
    await store.enqueueOutboundOp(_op(
      channelId: channelId,
      peer: sent['peer'] as String?,
      payload: base64.decode(sent['payload'] as String),
      kind: sent['kind'] as String,
      retryOf: opId,
    ));
    tick?.call();
  }

  OutboundOpRow _op({
    required String channelId,
    required List<int> payload,
    String? peer,
    String kind = OpKind.chatPayload,
    String? retryOf,
  }) {
    final now = clock.nowMs();
    return OutboundOpRow(
      opId: _newOpId(),
      transport: OpTransport.ws,
      kind: kind,
      restMethod: null,
      restPath: null,
      resourceId: channelId,
      payload: payload,
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: now,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: now,
      targetMessageId: null,
      targetChannelId: channelId,
      peer: peer,
      retryOf: retryOf,
    );
  }
}
