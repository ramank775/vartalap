import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// Gate test per SPIKE_B_SYNC.md §12.
///
/// Script:
///   1. Enqueue one chat_payload op.
///   2. Transport emits AckTransient three times.
///   3. Transport emits AckPermanent on the fourth attempt — but by
///      then the soft retry limit (3 in this config) has been hit on
///      the transient side, so the op moves to dead_letter before the
///      permanent ACK would arrive. (Equivalent behavior is reachable
///      via silent-drop + Flow C timeout — both paths converge at
///      dead_letter, which is the property the gate asserts.)
///
/// What we assert:
///   - op ends in `dead_letter` (not silently `completed`).
///   - message projection is `rejected`.
///   - watchFailures() emits the terminal row.
void main() {
  test('transient×3 → dead_letter, projection rejected, failures emitted',
      timeout: const Timeout(Duration(seconds: 10)), () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final clock = FakeClock(1000000);
    final ws = _ScriptedTransport();
    final rest = _ScriptedTransport(connected: false);

    final scheduler = SyncScheduler(
      store: store,
      wsTransport: ws,
      restTransport: rest,
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
      clock: clock,
      maxAttempts: 3,
      maxAge: const Duration(hours: 48),
      inFlightTimeout: const Duration(seconds: 30),
      sweepInterval: const Duration(seconds: 60),
    );

    const channelId = 'c-1';
    const messageId = 'm-1';
    const opId = 'op-1';

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
        payload: const [0x01],
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

    // Collect failure-stream emissions so we can assert the last one
    // contains our dead_letter row.
    final failures = <List<OutboundOpRow>>[];
    final sub = watchFailures(store).listen(failures.add);

    await scheduler.start();

    // Two full transient cycles. Each cycle: op is in_flight with
    // attempts=N+1, we ACK transient, scheduler sees attempts < 3 and
    // moves back to retrying. Advance clock past backoff, tick.
    for (var i = 0; i < 2; i++) {
      await _waitUntil(
        () async =>
            (await store.fetchOutboundOp(opId))?.status == OpStatus.inFlight,
        label: 'iter $i in_flight',
      );

      ws.emitAck(const AckFrame(
        opId: opId,
        outcome: AckTransientReject(reason: 'server_busy'),
      ));

      await _waitUntil(
        () async =>
            (await store.fetchOutboundOp(opId))?.status == OpStatus.retrying,
        label: 'iter $i retrying',
      );

      clock.advance(const Duration(milliseconds: 50));
      scheduler.tickSoon();
    }

    // Third dispatch. attempts becomes 3 (== maxAttempts). The next
    // transient ACK triggers the _exhausted() branch and moves the op
    // to dead_letter instead of scheduling another retry.
    await _waitUntil(
      () async =>
          (await store.fetchOutboundOp(opId))?.status == OpStatus.inFlight,
      label: 'final in_flight',
    );
    ws.emitAck(const AckFrame(
      opId: opId,
      outcome: AckTransientReject(reason: 'server_busy'),
    ));

    final dead = await _waitForDeadLetter(store, opId);
    expect(dead.status, OpStatus.deadLetter);
    expect(dead.attempts, greaterThanOrEqualTo(3));

    final msg = await store.fetchMessage(messageId);
    expect(msg!.state, MessageState.rejected);

    expect(failures.last.map((f) => f.opId), contains(opId));
    expect(failures.last.single.status, OpStatus.deadLetter);

    await sub.cancel();
    await scheduler.stop();
    await store.close();
  });

  test('manualRetry spawns a fresh op, dismisses the dead_letter row',
      timeout: const Timeout(Duration(seconds: 10)), () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final clock = FakeClock(1000000);

    const channelId = 'c-1';
    const messageId = 'm-1';
    const deadOpId = 'op-dead';
    const newOpId = 'op-new';

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
        opId: deadOpId,
        transport: OpTransport.ws,
        kind: OpKind.chatPayload,
        restMethod: null,
        restPath: null,
        resourceId: channelId,
        resourceSeq: 1,
        payload: const [0x42],
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

    // Drive the op into dead_letter directly.
    await store.markOpDeadLetter(
      opId: deadOpId,
      reason: 'retry_limit_exceeded',
      messageId: messageId,
      nowMs: clock.nowMs(),
    );
    expect((await store.fetchOutboundOp(deadOpId))!.status,
        OpStatus.deadLetter);
    expect((await store.fetchMessage(messageId))!.state,
        MessageState.rejected);

    clock.advance(const Duration(seconds: 30));

    await store.manualRetry(
      failedOpId: deadOpId,
      newOpId: newOpId,
      nowMs: clock.nowMs(),
    );

    // New op is pending with incremented resource_seq and same payload.
    final fresh = await store.fetchOutboundOp(newOpId);
    expect(fresh, isNotNull);
    expect(fresh!.status, OpStatus.pending);
    expect(fresh.attempts, 0);
    expect(fresh.resourceSeq, 2); // original was 1
    expect(fresh.payload, const [0x42]);
    expect(fresh.targetMessageId, messageId);

    // Failed row is acknowledged so watchFailures stops surfacing it.
    final oldRow = await store.fetchOutboundOp(deadOpId);
    expect(oldRow!.acknowledgedAt, isNotNull);

    final failures = await store.fetchFailures();
    expect(failures, isEmpty);

    // Message projection flipped back to pending for the new op.
    expect((await store.fetchMessage(messageId))!.state,
        MessageState.pending);

    await store.close();
  });
}

Future<void> _waitUntil(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
  String? label,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError(
    'waitUntil(${label ?? 'unlabeled'}): predicate never became true '
    'within $timeout',
  );
}

Future<OutboundOpRow> _waitForDeadLetter(
  ChatStore store,
  String opId,
) async {
  await _waitUntil(
    () async =>
        (await store.fetchOutboundOp(opId))?.status == OpStatus.deadLetter,
    label: 'dead_letter',
  );
  return (await store.fetchOutboundOp(opId))!;
}

/// Transport stub that lets the test drive ACKs by hand.
class _ScriptedTransport implements Transport {
  final _ackCtrl = StreamController<AckFrame>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();
  TransportState _state;

  _ScriptedTransport({bool connected = true})
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

  void emitAck(AckFrame ack) => _ackCtrl.add(ack);
}
