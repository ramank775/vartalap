/// Regression for decision 59 (DECISIONS.md) — the scheduler could
/// dispatch the same outbound op twice.
///
/// Root cause: `tickSoon()` pushes onto the `_tickSoon` broadcast stream,
/// and the listener kicked off a brand-new `_dispatchOnce()` for *every*
/// event with no guard against a pass that was already running. Since
/// `_dispatchOnce()` awaits `store.selectDispatchable()` (a plain SELECT)
/// before any row is flipped to `in_flight` by `markOpInFlight()`,
/// several wake-ups firing close together — exactly what happens in
/// production, since chat_service.dart calls `tickSoon()` on every
/// enqueue, Flow B calls it on every ACK, and Flow C's 30s safety timer
/// calls it too — could each run their own SELECT before the first
/// pass's UPDATE committed. Every pass that saw the row still `pending`
/// went ahead and sent it: the same op dispatched more than once.
///
/// Fix: a single-flight guard around the dispatch pass in
/// `_dispatchOnce()`. A wake-up that arrives while a pass is already
/// selecting/sending just asks for one more pass after the current one
/// finishes, instead of starting a second overlapping SELECT.
library vartalap_sync.double_dispatch_test;

import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  test(
      'op stays pending under overlapping tickSoon() wake-ups until it '
      'is dispatched exactly once',
      timeout: const Timeout(Duration(seconds: 5)), () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final clock = FakeClock(1000000);
    final ws = _CountingTransport();
    final rest = _CountingTransport(connected: false);

    final scheduler = SyncScheduler(
      store: store,
      wsTransport: ws,
      restTransport: rest,
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
      clock: clock,
    );
    await scheduler.start();

    const channelId = 'c-1';
    await store.insertChannel(
      channelId: channelId,
      kind: 'one_to_one',
      ownerUserId: 'u-self',
      createdAt: clock.nowMs(),
    );

    await store.enqueueLocalMessage(
      message: MessageRow(
        messageId: 'm-1',
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
        opId: 'op-1',
        transport: OpTransport.ws,
        kind: OpKind.chatPayload,
        restMethod: null,
        restPath: null,
        resourceId: channelId,
        resourceSeq: 1,
        payload: const [0x01],
        status: OpStatus.pending,
        attempts: 0,
        nextRetryAt: clock.nowMs(),
        dispatchedAt: null,
        lastError: null,
        acknowledgedAt: null,
        createdAt: clock.nowMs(),
        targetMessageId: 'm-1',
        targetChannelId: channelId,
      ),
      nowMs: clock.nowMs(),
    );

    // Simulate several dispatch wake-ups landing close together —
    // tickSoon() from an enqueue, the Flow C safety sweep, and a
    // reconnect can all fire around the same time (SPIKE_B_SYNC.md §5
    // Flow A). Fired back-to-back with no await between them, the old
    // (buggy) code's listener schedules several concurrent
    // `_dispatchOnce()` passes; each one's `selectDispatchable()` can
    // resolve before the first pass's `markOpInFlight()` transaction
    // commits, so every pass sends the op.
    for (var i = 0; i < 5; i++) {
      scheduler.tickSoon();
    }

    // Let the wake-ups above actually run to completion before we ask
    // the scheduler to stop. This isn't a race against the clock for
    // *whether* the bug reproduces — all 5 dispatch passes are kicked
    // off synchronously off the tickSoon events above, well before any
    // of them can complete a `selectDispatchable()` round trip through
    // the real (in-memory) sqflite connection, so every pass observes
    // the op as still `pending` on the old code. This pump just gives
    // them real event-loop turns to run their `await`s to completion so
    // the send counts below are settled.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Drains every tracked flow (all the overlapping dispatch passes
    // above included) before returning.
    await scheduler.stop();
    await store.close();

    expect(
      ws.sendCountFor('op-1'),
      1,
      reason: 'op-1 must reach the transport exactly once even when '
          'several dispatch wake-ups race each other',
    );
  });
}

class _CountingTransport implements Transport {
  final _ackCtrl = StreamController<AckFrame>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();
  final Map<String, int> _sendCounts = {};
  final TransportState _state;

  _CountingTransport({bool connected = true})
      : _state = connected
            ? TransportState.connected
            : TransportState.disconnected;

  int sendCountFor(String opId) => _sendCounts[opId] ?? 0;

  @override
  Future<void> send(OutboundFrame frame) async {
    for (final op in frame.ops) {
      _sendCounts[op.opId] = (_sendCounts[op.opId] ?? 0) + 1;
    }
  }

  @override
  Stream<AckFrame> get acks => _ackCtrl.stream;

  @override
  Stream<TransportState> get state => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;
}
