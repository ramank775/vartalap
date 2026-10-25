/// Decision 188: a WS op goes out as the bytes its seal hook made, kept on
/// the row; a retry resends them without sealing again, and an op that
/// cannot be sealed yet is never sent.
library vartalap_sync.seal_test;

import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  late ChatStore store;
  late FakeClock clock;
  late _Transport ws;
  late SyncScheduler scheduler;

  setUp(() async {
    store = await ChatStore.open(path: inMemoryDatabasePath);
    clock = FakeClock(1000000);
    ws = _Transport();
    scheduler = SyncScheduler(
      store: store,
      wsTransport: ws,
      restTransport: _Transport(),
      backoff: const FixedBackoff(Duration(milliseconds: 10)),
      clock: clock,
    );
    await store.insertChannel(
        channelId: 'g-1',
        kind: 'group',
        ownerUserId: 'u-self',
        createdAt: clock.nowMs());
    await store.enqueueOutboundOp(OutboundOpRow(
      opId: 'op-1',
      transport: OpTransport.ws,
      kind: OpKind.chatPayload,
      restMethod: null,
      restPath: null,
      resourceId: 'g-1',
      payload: const [8, 1],
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: clock.nowMs(),
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: clock.nowMs(),
      targetMessageId: null,
      targetChannelId: 'g-1',
    ));
  });

  tearDown(() async {
    await scheduler.stop();
    await store.close();
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('sealed once, resent as the same bytes', () async {
    var seals = 0;
    scheduler.seal = (op, peer) async {
      seals++;
      final sealed = [0x45, 1, 2, seals];
      await ChatStore.storeSealedPayload(store.db, op.opId, sealed);
      return sealed;
    };
    await scheduler.start();
    scheduler.tickSoon();
    await settle();
    expect(ws.sent, [
      [0x45, 1, 2, 1]
    ]);

    // A transient reject: the retry goes out as what was sealed.
    ws.ack(const AckFrame(
        opId: 'op-1', outcome: AckTransientReject(reason: 'busy')));
    await settle();
    clock.advance(const Duration(seconds: 1));
    scheduler.tickSoon();
    await settle();
    expect(ws.sent, [
      [0x45, 1, 2, 1],
      [0x45, 1, 2, 1]
    ]);
    expect(seals, 1);
  });

  test('an op that cannot be sealed yet waits; it never goes in plaintext',
      () async {
    scheduler.seal = (op, peer) async => throw StateError('no keys yet');
    await scheduler.start();
    scheduler.tickSoon();
    await settle();
    expect(ws.sent, isEmpty);
    final op = (await store.fetchOutboundOp('op-1'))!;
    expect([op.status, op.attempts], [OpStatus.retrying, 1]);
    expect(op.lastError, startsWith('seal_failed'));
  });
}

class _Transport implements Transport {
  final _acks = StreamController<AckFrame>.broadcast();
  final sent = <List<int>>[];

  void ack(AckFrame frame) => _acks.add(frame);

  @override
  Future<void> send(OutboundFrame frame) async {
    for (final op in frame.ops) {
      sent.add(op.payload);
    }
  }

  @override
  Stream<AckFrame> get acks => _acks.stream;

  @override
  Stream<TransportState> get state => const Stream.empty();

  @override
  TransportState get currentState => TransportState.connected;
}
