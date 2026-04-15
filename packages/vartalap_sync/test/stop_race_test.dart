/// Regression for the stop()-vs-dispatch race.
///
/// Before the fix, `scheduler.stop()` flipped `_running = false` but
/// didn't await the in-flight `_dispatchOnce()` or `_onAck()` tasks
/// already scheduled off the tickSoon / ack streams. A caller that
/// did `await scheduler.stop(); await store.close();` could see a
/// DatabaseException(error database_closed) as the dispatcher
/// continued to touch the closed store.
///
/// The fix: every flow wraps its async work via `_track`, adding the
/// Future to an in-flight set that `stop()` drains before returning.
/// Flows also re-check `_running` after every await so a mid-flight
/// stop aborts before the next DB touch.
library vartalap_sync.stop_race_test;

import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  test(
      'stop() drains the in-flight dispatch before returning; '
      'subsequent store.close() is safe',
      timeout: const Timeout(Duration(seconds: 5)), () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final clock = FakeClock(1000000);
    final ws = _StubTransport();
    final rest = _StubTransport(connected: false);

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

    // Enqueue a single op. tickSoon fires synchronously from
    // enqueueLocalMessage's nudge; the listener kicks off
    // _dispatchOnce asynchronously.
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
    scheduler.tickSoon();

    // Yield once so the tickSoon listener schedules _dispatchOnce,
    // and give it time to begin the selectDispatchable read but not
    // enough to complete the markOpInFlight transaction. Without
    // this pump the tickSoon event hasn't even been dequeued — the
    // dispatch isn't yet in flight and the race doesn't trigger.
    await Future<void>.delayed(Duration.zero);

    // stop() must drain the in-flight dispatch before returning.
    // close() must then be safe against concurrent DB access.
    await scheduler.stop();
    await store.close();

    // If we got here without throwing, the fix holds.
  });

  test('stop() returns promptly when nothing is in flight',
      timeout: const Timeout(Duration(seconds: 2)), () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final scheduler = SyncScheduler(
      store: store,
      wsTransport: _StubTransport(connected: false),
      restTransport: _StubTransport(connected: false),
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
      clock: FakeClock(0),
    );
    await scheduler.start();
    await scheduler.stop();
    await store.close();
  });
}

class _StubTransport implements Transport {
  final _ackCtrl = StreamController<AckFrame>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();
  TransportState _state;

  _StubTransport({bool connected = true})
      : _state = connected
            ? TransportState.connected
            : TransportState.disconnected;

  @override
  Future<void> send(OutboundFrame frame) async {}

  @override
  Stream<AckFrame> get acks => _ackCtrl.stream;

  @override
  Stream<TransportState> get state => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;
}
