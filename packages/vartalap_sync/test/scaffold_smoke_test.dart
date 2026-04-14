import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  test(
    'optimistic send: pending -> sending -> sent, outbound_ops deleted',
    () async {
      final store = await ChatStore.open(path: inMemoryDatabasePath);
      final clock = FakeClock(1000000);
      final wsTransport = _StubTransport();
      final restTransport = _StubTransport(connected: false);

      final scheduler = SyncScheduler(
        store: store,
        wsTransport: wsTransport,
        restTransport: restTransport,
        backoff: const FixedBackoff(Duration(milliseconds: 10)),
        clock: clock,
      );

      const channelId = 'c-1';
      const messageId = 'm-1';
      const opId = 'op-1';
      const payloadBytes = <int>[0x01, 0x02, 0x03];

      await store.insertChannel(
        channelId: channelId,
        kind: 'one_to_one',
        ownerUserId: 'u-self',
        createdAt: clock.nowMs(),
      );
      await store.enqueueLocalMessage(
        message: MessageRow(
          messageId: messageId,
          channelId: channelId,
          authorUserId: 'u-self',
          body: 'hello',
          contentType: 'text/plain',
          replyToMessageId: null,
          clientTimestampMs: clock.nowMs(),
          serverTimestampMs: null,
          deliverySequence: null,
          state: MessageState.pending,
          stateUpdatedAt: clock.nowMs(),
          isEdited: false,
          lastEditMs: null,
          tombstoned: false,
          tombstonePendingUntil: null,
        ),
        op: OutboundOpRow(
          opId: opId,
          transport: OpTransport.ws,
          kind: OpKind.chatPayload,
          restMethod: null,
          restPath: null,
          resourceId: channelId,
          resourceSeq: 1,
          payload: payloadBytes,
          status: OpStatus.pending,
          attempts: 0,
          nextRetryAt: clock.nowMs(),
          dispatchedAt: null,
          lastError: null,
          acknowledgedAt: null,
          createdAt: clock.nowMs(),
          targetMessageId: messageId,
          targetChannelId: channelId,
        ),
        nowMs: clock.nowMs(),
      );

      expect((await store.fetchMessage(messageId))!.state,
          MessageState.pending);
      expect(await store.fetchOutboundOp(opId), isNotNull);

      await scheduler.start();

      // Flow A dispatched → message is now 'sending', frame was handed
      // to the transport.
      expect((await store.fetchMessage(messageId))!.state,
          MessageState.sending);
      expect(wsTransport.sent, hasLength(1));
      expect(wsTransport.sent.single.ops.single.opId, opId);

      // Transport returns AckSuccess. Flow B deletes the op, message
      // transitions to 'sent' with the server-stamped fields.
      wsTransport.emitAck(AckFrame(
        opId: opId,
        outcome: const AckSuccess(
          serverTimestampMs: 2000000,
          deliverySequence: 42,
        ),
      ));
      // Flow B listens on a broadcast stream and applies the ack in an
      // async callback. Poll until the op is deleted (bounded).
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (await store.fetchOutboundOp(opId) == null) break;
      }

      final delivered = await store.fetchMessage(messageId);
      expect(delivered!.state, MessageState.sent);
      expect(delivered.serverTimestampMs, 2000000);
      expect(delivered.deliverySequence, 42);
      expect(await store.fetchOutboundOp(opId), isNull);

      await scheduler.stop();
      await store.close();
    },
  );
}

/// Minimal hand-written transport stub. No mockito — the Flow A/B
/// wiring is simple enough to test with a pair of controllers.
class _StubTransport implements Transport {
  final _ackCtrl = StreamController<AckFrame>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();
  final List<OutboundFrame> sent = [];
  TransportState _state;

  _StubTransport({bool connected = true})
      : _state = connected
            ? TransportState.connected
            : TransportState.disconnected;

  @override
  Future<void> send(OutboundFrame frame) async {
    sent.add(frame);
  }

  @override
  Stream<AckFrame> get acks => _ackCtrl.stream;

  @override
  Stream<TransportState> get state => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;

  void emitAck(AckFrame ack) => _ackCtrl.add(ack);
}
