/// Decision 212: only a new message may wake the recipient's phone.
library vartalap_sync.silent_test;

import 'package:test/test.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/src/sync_scheduler.dart' show silentOp;
import 'package:vartalap_transport/src/ws_transport.dart' show opFrame;
import 'package:vartalap_transport/vartalap_transport.dart';

OutboundOpRow _op(String kind, List<int> payload) => OutboundOpRow(
      opId: 'op-1',
      transport: OpTransport.ws,
      kind: kind,
      restMethod: null,
      restPath: null,
      resourceId: 'g-1',
      payload: payload,
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: 0,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: 0,
      targetMessageId: null,
      targetChannelId: 'g-1',
    );

List<int> _payload(pb.ChatPayloadType type) =>
    pb.ChatPayload(version: 1, type: type).writeToBuffer();

void main() {
  test('a new message or forward wakes, receipts and mutations do not', () {
    bool silent(String kind, pb.ChatPayloadType type) =>
        silentOp(_op(kind, _payload(type)));

    expect(silent(OpKind.chatPayload, pb.ChatPayloadType.TYPE_MESSAGE_CREATE),
        isFalse);
    expect(silent(OpKind.chatPayload, pb.ChatPayloadType.TYPE_MESSAGE_FORWARD),
        isFalse);
    expect(silent(OpKind.chatPayload, pb.ChatPayloadType.TYPE_READ_RECEIPT),
        isTrue);
    expect(
        silent(OpKind.chatPayload, pb.ChatPayloadType.TYPE_DELIVERY_RECEIPT),
        isTrue);
    expect(silent(OpKind.messageEdit, pb.ChatPayloadType.TYPE_MESSAGE_UPDATE),
        isTrue);
    expect(
        silent(OpKind.messageDelete, pb.ChatPayloadType.TYPE_MESSAGE_DELETE),
        isTrue);
    expect(
        silent(OpKind.messageReaction, pb.ChatPayloadType.TYPE_REACTION_ADD),
        isTrue);
    // A key resend request is sealed bytes, not a ChatPayload.
    expect(silentOp(_op(OpKind.chatPayload, [0x45, 1, 5, 9, 9])), isFalse);
  });

  test('the flag reaches the wire envelope', () {
    pb.Envelope sent(bool silent) => opFrame(OutboundFrame(
          kind: OpKind.chatPayload,
          resourceId: 'g-1',
          ops: [FramedOp(opId: 'op-1', payload: const [1], silent: silent)],
        )).ops.envelopes.single;

    expect(sent(true).flags, 1);
    expect(sent(false).hasFlags(), isFalse);
  });
}
