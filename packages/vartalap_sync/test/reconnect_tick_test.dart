import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// Flow A skips an op whose transport is disconnected without charging
/// it an attempt (SPIKE_B_SYNC §12a) and relies on "the next tickSoon()
/// on transport reconnect" to pick it up again. Nothing made that call:
/// Flow C only ticks when it finds a stuck `in_flight` row, and an op
/// that never left the device is `pending`. A whole queue written while
/// offline could therefore stay put after the network came back.
///
/// The sweep here is deliberately far outside the test's patience, so a
/// pass can only mean the reconnect itself woke the dispatcher.
void main() {
  Future<ChatStore> storeWithPendingOp(String opId, String channelId) async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    await store.insertChannel(
      channelId: channelId,
      kind: 'one_to_one',
      ownerUserId: 'u-self',
      createdAt: 1000,
    );
    await store.enqueueOutboundOp(OutboundOpRow(
      opId: opId,
      transport: OpTransport.ws,
      kind: OpKind.chatPayload,
      restMethod: null,
      restPath: null,
      resourceId: channelId,
      payload: const [0x01],
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: 0,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: 1000,
      targetMessageId: null,
      targetChannelId: channelId,
    ));
    return store;
  }

  SyncScheduler schedulerFor(
    ChatStore store,
    Transport ws,
    Transport rest,
  ) =>
      SyncScheduler(
        store: store,
        wsTransport: ws,
        restTransport: rest,
        backoff: const FixedBackoff(Duration(milliseconds: 10)),
        // Long enough that Flow C cannot be what rescues the op.
        sweepInterval: const Duration(minutes: 10),
      );

  Future<bool> dispatchedWithin(
    ChatStore store,
    String opId, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < timeout) {
      final op = await store.fetchOutboundOp(opId);
      if (op != null && op.status != OpStatus.pending) return true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return false;
  }

  test('an op queued while offline dispatches when the WS reconnects',
      timeout: const Timeout(Duration(seconds: 15)), () async {
    final store = await storeWithPendingOp('op-ws', 'c-ws');
    final ws = _ScriptedTransport(connected: false);
    final rest = _ScriptedTransport(connected: false);
    final scheduler = schedulerFor(store, ws, rest);
    addTearDown(() async {
      await scheduler.stop();
      await store.close();
    });

    await scheduler.start();
    expect(
      (await store.fetchOutboundOp('op-ws'))?.status,
      OpStatus.pending,
      reason: 'no transport, no dispatch — and no attempt charged.',
    );

    ws.goConnected();

    expect(
      await dispatchedWithin(store, 'op-ws'),
      isTrue,
      reason: 'reconnecting must wake Flow A. Without a tick on the '
          "transport's state stream this op waits for the next unrelated "
          'enqueue or ACK, which on an idle chat never comes.',
    );
  });

  test('the REST transport reconnecting wakes the dispatcher too',
      timeout: const Timeout(Duration(seconds: 15)), () async {
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    await store.insertChannel(
      channelId: 'c-rest',
      kind: 'one_to_one',
      ownerUserId: 'u-self',
      createdAt: 1000,
    );
    await store.enqueueOutboundOp(OutboundOpRow(
      opId: 'op-rest',
      transport: OpTransport.rest,
      kind: OpKind.createChannel,
      restMethod: 'POST',
      restPath: '/v3.0/channels',
      resourceId: 'c-rest',
      payload: const [0x7b, 0x7d],
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: 0,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: 1000,
      targetMessageId: null,
      targetChannelId: 'c-rest',
    ));
    final ws = _ScriptedTransport(connected: false);
    final rest = _ScriptedTransport(connected: false);
    final scheduler = schedulerFor(store, ws, rest);
    addTearDown(() async {
      await scheduler.stop();
      await store.close();
    });

    await scheduler.start();
    expect((await store.fetchOutboundOp('op-rest'))?.status, OpStatus.pending);

    rest.goConnected();

    expect(
      await dispatchedWithin(store, 'op-rest'),
      isTrue,
      reason: 'the connectivity-backed REST transport is the one a phone '
          'flips most often; it has to wake the queue as well.',
    );
  });

  test('stop() releases the transport state subscriptions',
      timeout: const Timeout(Duration(seconds: 15)), () async {
    final store = await storeWithPendingOp('op-stopped', 'c-stopped');
    final ws = _ScriptedTransport(connected: false);
    final rest = _ScriptedTransport(connected: false);
    final scheduler = schedulerFor(store, ws, rest);
    addTearDown(store.close);

    await scheduler.start();
    await scheduler.stop();
    ws.goConnected();

    expect(
      await dispatchedWithin(
        store,
        'op-stopped',
        timeout: const Duration(milliseconds: 500),
      ),
      isFalse,
      reason: 'a stopped scheduler must not be revived by a reconnect — '
          'the caller may already be closing the store.',
    );
  });
}

class _ScriptedTransport implements Transport {
  final _ackCtrl = StreamController<AckFrame>.broadcast();
  final _stateCtrl = StreamController<TransportState>.broadcast();
  TransportState _state;

  _ScriptedTransport({bool connected = true})
      : _state = connected
            ? TransportState.connected
            : TransportState.disconnected;

  /// What a real transport does on reconnect: flip `currentState`, then
  /// announce it.
  void goConnected() {
    _state = TransportState.connected;
    _stateCtrl.add(_state);
  }

  @override
  Future<void> send(OutboundFrame frame) async {}

  @override
  Stream<AckFrame> get acks => _ackCtrl.stream;

  @override
  Stream<TransportState> get state => _stateCtrl.stream;

  @override
  TransportState get currentState => _state;
}
