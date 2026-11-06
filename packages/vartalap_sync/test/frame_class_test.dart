/// Decision 218: every queued op names its class in `Envelope.flags`;
/// only a message or a resend request wakes the recipient (decision 212).
library vartalap_sync.frame_class_test;

import 'package:test/test.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/src/sync_scheduler.dart'
    show frameClassOf, liveLocationWire;
import 'package:vartalap_transport/src/ws_transport.dart' show opFrame;
import 'package:vartalap_transport/vartalap_transport.dart';

const _group = '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0000';
const _opId = '0190aaaa-bbbb-7ccc-8ddd-eeeeffff0001';

OutboundOpRow _op(String kind, List<int> payload) => OutboundOpRow(
      opId: _opId,
      transport: OpTransport.ws,
      kind: kind,
      restMethod: null,
      restPath: null,
      resourceId: _group,
      payload: payload,
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: 0,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: 0,
      targetMessageId: null,
      targetChannelId: _group,
    );

List<int> _payload(pb.ChatPayloadType type) =>
    pb.ChatPayload(version: 1, type: type).writeToBuffer();

void main() {
  test('each queued op maps to its class', () {
    FrameClass of(String kind, pb.ChatPayloadType type) =>
        frameClassOf(_op(kind, _payload(type)));

    expect(of(OpKind.chatPayload, pb.ChatPayloadType.TYPE_MESSAGE_CREATE),
        FrameClass.message);
    expect(of(OpKind.chatPayload, pb.ChatPayloadType.TYPE_MESSAGE_FORWARD),
        FrameClass.message);
    expect(of(OpKind.chatPayload, pb.ChatPayloadType.TYPE_READ_RECEIPT),
        FrameClass.receipt);
    expect(of(OpKind.chatPayload, pb.ChatPayloadType.TYPE_DELIVERY_RECEIPT),
        FrameClass.receipt);
    expect(of(OpKind.messageEdit, pb.ChatPayloadType.TYPE_MESSAGE_UPDATE),
        FrameClass.mutation);
    expect(of(OpKind.messageDelete, pb.ChatPayloadType.TYPE_MESSAGE_DELETE),
        FrameClass.mutation);
    expect(of(OpKind.messageReaction, pb.ChatPayloadType.TYPE_REACTION_ADD),
        FrameClass.mutation);
    // A resend request is queued already sealed, with binary ids that
    // might parse as a ChatPayload: told apart by its first byte.
    expect(frameClassOf(_op(OpKind.chatPayload, [0x45, 2, 5, 0x08, 7])),
        FrameClass.resend);
  });

  test('the class reaches the wire envelope, a message as no flags at all', () {
    pb.Envelope sent(FrameClass c) => opFrame(OutboundFrame(
          kind: OpKind.chatPayload,
          resourceId: _group,
          ops: [
            FramedOp(opId: _opId, payload: const [1], frameClass: c)
          ],
        )).ops.envelopes.single;

    // Decision 220: what shows no notification goes SILENT (bit 0).
    expect(sent(FrameClass.message).hasFlags(), isFalse);
    expect(sent(FrameClass.mutation).flags, (1 << 1) | 1);
    expect(sent(FrameClass.receipt).flags, (2 << 1) | 1);
    expect(sent(FrameClass.key).flags, (3 << 1) | 1);
    expect(sent(FrameClass.resend).flags, 4 << 1, reason: 'a resend wakes');
  });

  test('live location: class LOCATION; a position or stop SILENT and short '
      'lived, a remote on/off wakes (SYNC_PROTOCOL §21)', () {
    pb.Envelope sent(pb.ChatPayloadType type) {
      final op = _op(OpKind.chatPayload, _payload(type));
      final live = liveLocationWire(op)!;
      return opFrame(OutboundFrame(
        kind: OpKind.chatPayload,
        resourceId: _group,
        ops: [
          FramedOp(
            opId: _opId,
            payload: const [1],
            frameClass: frameClassOf(op),
            wakes: live.wakes,
            ttlSec: live.ttlSec,
          )
        ],
      )).ops.envelopes.single;
    }

    final update = sent(pb.ChatPayloadType.TYPE_LIVE_LOCATION_UPDATE);
    expect((update.flags >> 1) & 15, 7);
    expect(update.flags & kEnvelopeFlagSilent, 1);
    expect(update.ttlSec, 15 * 60);
    final stop = sent(pb.ChatPayloadType.TYPE_LIVE_LOCATION_STOP);
    expect(stop.flags, (7 << 1) | 1);
    expect(stop.ttlSec, 8 * 3600);
    final control = sent(pb.ChatPayloadType.TYPE_LIVE_LOCATION_CONTROL);
    expect(control.flags, 7 << 1, reason: 'wakes the owner\'s phone');
    expect(control.ttlSec, 3600);
    final permission = sent(pb.ChatPayloadType.TYPE_LIVE_LOCATION_PERMISSION);
    expect(permission.flags, (7 << 1) | 1);
    expect(permission.hasTtlSec(), isFalse, reason: 'kept the full time');

    expect(
        liveLocationWire(_op(OpKind.chatPayload,
            _payload(pb.ChatPayloadType.TYPE_MESSAGE_CREATE))),
        isNull,
        reason: 'a share itself is a message');
  });
}
