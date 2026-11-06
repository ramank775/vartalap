import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:vartalap_proto/vartalap_proto.dart' as pb;

import 'dm_channel_id.dart';

// Decision 218: ids are raw bytes on the wire and nowhere else. Databases,
// models, logs and dedup keys keep the text forms; the transport converts
// at the edge with these, and each rejects a wrong length.

final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);
final RegExp _userId = RegExp(r'^[0-9a-f]{9}$');

/// A UUID's 16 bytes (RFC 9562 order) from its dashed text.
Uint8List uuidBytes(String uuid) {
  if (!_uuid.hasMatch(uuid)) throw FormatException('Not a UUID: $uuid');
  return _bytes(uuid.replaceAll('-', ''));
}

/// The dashed, lowercase text of a 16-byte UUID.
String uuidText(List<int> bytes) {
  if (bytes.length != 16) {
    throw FormatException('A UUID is 16 bytes, not ${bytes.length}');
  }
  final h = _hex(bytes);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// A 9-hex user_id as 5 bytes, big-endian (one 0 nibble in front).
Uint8List userIdBytes(String userId) {
  if (!_userId.hasMatch(userId))
    throw FormatException('Not a user id: $userId');
  return _bytes('0$userId');
}

/// The 9-hex user_id of its 5 wire bytes.
String userIdText(List<int> bytes) {
  if (bytes.length != 5 || bytes[0] > 0x0f) {
    throw const FormatException('A user id is 5 bytes under 2^36');
  }
  return _hex(bytes).substring(1);
}

/// The user_id in a UUIDv7 op id: the 36 bits after the variant (bytes
/// 8-12, `Uuid7Gen`'s layout), which the server checks against the
/// sending session (SYNC_PROTOCOL §3), so they name the sender.
String opIdUserId(List<int> opId) {
  if (opId.length != 16) {
    throw FormatException('An op id is 16 bytes, not ${opId.length}');
  }
  final bits = ((opId[8] & 0x3f) << 30) |
      (opId[9] << 22) |
      (opId[10] << 14) |
      (opId[11] << 6) |
      (opId[12] >> 2);
  return bits.toRadixString(16).padLeft(9, '0');
}

Uint8List _bytes(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16)
    ]);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// `Envelope.flags` bit 0 (decision 220): no push wake. The app sets it
/// on what shows the recipient no notification.
const int kEnvelopeFlagSilent = 1;

/// `Envelope.flags` bits 1-4, `(flags >> 1) & 15` (decisions 218, 220):
/// what an op is, which tells the server how long to keep it (a
/// [receipt]: 7 days). [event] is the server's own. Classes 8-15 are free
/// for kinds to come.
enum FrameClass {
  message,
  mutation,
  receipt,
  key,
  resend,
  event,

  /// Class 6, set aside for the private timeline (decision 223), whose
  /// posts go over REST for now; held here so that [location] is 7.
  timeline,

  /// Live location (SYNC_PROTOCOL §21): positions, stops and permissions
  /// go SILENT; a remote on/off wakes ([FramedOp.wakes]).
  location;

  /// A new message, or a resend request (its sender must answer), shows
  /// a notification or needs the phone awake; the rest do not.
  bool get wakes => this == message || this == resend;

  int get flags => (index << 1) | (wakes ? 0 : kEnvelopeFlagSilent);
}

/// The wire envelope for text ids. A DM ([peer] set) sends no channel:
/// both ends derive it from the pair. Default values stay unset, so they
/// cost nothing on the wire. The server stamps the last two on fanout.
pb.Envelope wireEnvelope({
  required String opId,
  required String channelId,
  String? peer,
  required List<int> payload,
  bool ephemeral = false,
  int ttlSec = 0,
  int flags = 0,
  int serverTimestampMs = 0,
  String senderDeviceId = '',
}) =>
    pb.Envelope(
      opId: uuidBytes(opId),
      channelId: peer == null ? uuidBytes(channelId) : null,
      peer: peer == null ? null : userIdBytes(peer),
      payload: payload,
      ephemeral: ephemeral ? true : null,
      ttlSec: ttlSec == 0 ? null : ttlSec,
      flags: flags == 0 ? null : flags,
      serverTimestampMs:
          serverTimestampMs == 0 ? null : fixnum.Int64(serverTimestampMs),
      senderDeviceId: senderDeviceId.isEmpty ? null : uuidBytes(senderDeviceId),
    );

/// A fanned-out envelope (a WS_PUSH, or one a pull brought) with its ids
/// in text form: what everything above the transport reads.
class InboundEnvelope {
  final String opId;

  /// A group's UUID, or a DM's derived `d…` id.
  final String channelId;

  /// From the op id's user bits; '' for a server event whose op id
  /// carries none.
  final String senderUserId;

  /// '' on a server event.
  final String senderDeviceId;

  /// A DM's other participant as its sender named it (so, once fanned
  /// out, this phone's user); '' on a group.
  final String peer;

  final List<int> payload;
  final bool ephemeral;
  final int ttlSec;
  final int flags;
  final int serverTimestampMs;

  const InboundEnvelope({
    required this.opId,
    required this.channelId,
    this.senderUserId = '',
    this.senderDeviceId = '',
    this.peer = '',
    required this.payload,
    this.ephemeral = false,
    this.ttlSec = 0,
    this.flags = 0,
    this.serverTimestampMs = 0,
  });

  /// [env]'s text form. Throws [FormatException] on a malformed one: an
  /// id of the wrong length, or not exactly one of `peer` (a DM) and
  /// `channel_id` (a group).
  factory InboundEnvelope.fromWire(pb.Envelope env) {
    final opId = uuidText(env.opId);
    final p = env.payload;
    // A server event (0x53) carries the server's own op id: its user bits
    // name the actor only on a UUIDv7 the server minted with them.
    final sender = p.isNotEmpty && p[0] == 0x53 && env.opId[6] >> 4 != 7
        ? ''
        : opIdUserId(env.opId);
    final dm = env.peer.isNotEmpty;
    if (dm == env.channelId.isNotEmpty || (dm && sender.isEmpty)) {
      throw const FormatException('An envelope is a DM or a group');
    }
    final peer = dm ? userIdText(env.peer) : '';
    return InboundEnvelope(
      opId: opId,
      channelId: dm ? dmChannelId(sender, peer) : uuidText(env.channelId),
      senderUserId: sender,
      senderDeviceId:
          env.senderDeviceId.isEmpty ? '' : uuidText(env.senderDeviceId),
      peer: peer,
      payload: p,
      ephemeral: env.ephemeral,
      ttlSec: env.ttlSec,
      flags: env.flags,
      serverTimestampMs: env.serverTimestampMs.toInt(),
    );
  }

  /// The sender's clock when it minted the op: a UUIDv7's first 48 bits
  /// (what `client_timestamp_ms` was). 0 for an op id that is no UUID.
  int get clientTimestampMs {
    final hex = opId.replaceAll('-', '');
    return hex.length == 32
        ? int.tryParse(hex.substring(0, 12), radix: 16) ?? 0
        : 0;
  }

  /// This envelope at another server time (a re-send takes its
  /// placeholder's place, decision 188).
  InboundEnvelope at(int serverTimestampMs) => InboundEnvelope(
        opId: opId,
        channelId: channelId,
        senderUserId: senderUserId,
        senderDeviceId: senderDeviceId,
        peer: peer,
        payload: payload,
        ephemeral: ephemeral,
        ttlSec: ttlSec,
        flags: flags,
        serverTimestampMs: serverTimestampMs,
      );
}

/// [InboundEnvelope.fromWire], or null (logged) for a malformed frame:
/// the server never sends one, and nothing could apply it.
InboundEnvelope? inboundOrNull(pb.Envelope env) {
  try {
    return InboundEnvelope.fromWire(env);
  } on FormatException catch (e) {
    // ignore: avoid_print
    print('Transport: dropping a malformed envelope: ${e.message}');
    return null;
  }
}
