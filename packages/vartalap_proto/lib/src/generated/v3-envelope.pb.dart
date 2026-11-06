// This is a generated file - do not edit.
//
// Generated from v3-envelope.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'v3-envelope.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'v3-envelope.pbenum.dart';

/// -----------------------------------------------------------------------------
/// Envelope — the unit of opaque chat-content delivery.
/// -----------------------------------------------------------------------------
///
/// A client sends an Envelope to push some payload bytes into a channel.
/// The server validates routing fields, adds the server-stamped fields
/// (server_timestamp_ms, sender_device_id) on fanout,
/// and delivers the same Envelope to every other channel member.
///
/// Recipients interpret `payload` according to the client-to-client
/// schema. The server's job ends at "delivered to channel members."
class Envelope extends $pb.GeneratedMessage {
  factory Envelope({
    $core.List<$core.int>? payload,
    $core.bool? ephemeral,
    $core.int? ttlSec,
    $core.int? flags,
    $core.List<$core.int>? opId,
    $core.List<$core.int>? channelId,
    $core.List<$core.int>? peer,
    $core.List<$core.int>? senderDeviceId,
    $fixnum.Int64? serverTimestampMs,
  }) {
    final result = create();
    if (payload != null) result.payload = payload;
    if (ephemeral != null) result.ephemeral = ephemeral;
    if (ttlSec != null) result.ttlSec = ttlSec;
    if (flags != null) result.flags = flags;
    if (opId != null) result.opId = opId;
    if (channelId != null) result.channelId = channelId;
    if (peer != null) result.peer = peer;
    if (senderDeviceId != null) result.senderDeviceId = senderDeviceId;
    if (serverTimestampMs != null) result.serverTimestampMs = serverTimestampMs;
    return result;
  }

  Envelope._();

  factory Envelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Envelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Envelope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..aOB(6, _omitFieldNames ? '' : 'ephemeral')
    ..aI(8, _omitFieldNames ? '' : 'ttlSec', fieldType: $pb.PbFieldType.OU3)
    ..aI(9, _omitFieldNames ? '' : 'flags', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        10, _omitFieldNames ? '' : 'opId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        11, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        12, _omitFieldNames ? '' : 'peer', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        13, _omitFieldNames ? '' : 'senderDeviceId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(
        14, _omitFieldNames ? '' : 'serverTimestampMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope copyWith(void Function(Envelope) updates) =>
      super.copyWith((message) => updates(message as Envelope)) as Envelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Envelope create() => Envelope._();
  @$core.override
  Envelope createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Envelope getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Envelope>(create);
  static Envelope? _defaultInstance;

  /// Opaque to the server (end-to-end encrypted, sealed format v2,
  /// decision 218). Required.
  @$pb.TagNumber(5)
  $core.List<$core.int> get payload => $_getN(0);
  @$pb.TagNumber(5)
  set payload($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(5)
  $core.bool hasPayload() => $_has(0);
  @$pb.TagNumber(5)
  void clearPayload() => $_clearField(5);

  /// Typing and the like: never acked, never stored, never pushed.
  @$pb.TagNumber(6)
  $core.bool get ephemeral => $_getBF(1);
  @$pb.TagNumber(6)
  set ephemeral($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(6)
  $core.bool hasEphemeral() => $_has(1);
  @$pb.TagNumber(6)
  void clearEphemeral() => $_clearField(6);

  /// How long the server keeps this envelope on its recipients' timeline
  /// for a later pull, in seconds (SYNC_PROTOCOL.md §10.6). 0 or absent
  /// means the maximum, 30 days; more is capped to it. The server may keep
  /// a class for less (a receipt: 7 days). Echoed unchanged on fanout.
  @$pb.TagNumber(8)
  $core.int get ttlSec => $_getIZ(2);
  @$pb.TagNumber(8)
  set ttlSec($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(8)
  $core.bool hasTtlSec() => $_has(2);
  @$pb.TagNumber(8)
  void clearTtlSec() => $_clearField(8);

  /// Handling bits (decisions 212, 215, 218, 220). Unknown bits are kept
  /// and echoed. Echoed unchanged on fanout.
  ///   bit 0 (1)        SILENT: no push wake. The sender sets it on what
  ///                    shows no notification; the server wakes for every
  ///                    other stored frame, so a new kind of frame needs no
  ///                    server change.
  ///   bits 1-4 (2-30)  CLASS, (flags >> 1) & 15: what the frame is, for
  ///                    the server's storage and (later) the invite gate:
  ///     0 MESSAGE   a new message or forward
  ///     1 MUTATION  edit, delete, reaction (sent SILENT)
  ///     2 RECEIPT   delivered/read (sent SILENT); kept 7 days
  ///     3 KEY       a group-key handoff (sent SILENT)
  ///     4 RESEND    "send me that again"
  ///     5 EVENT     server-authored, set by the server only (SILENT)
  ///     7 LOCATION  live location (SYNC_PROTOCOL.md §20): positions,
  ///                 stops and permissions SILENT, a remote on/off wakes
  ///     6, 8-15     free, for kinds to come (timeline, presence)
  ///   A frame with no flags is a MESSAGE that wakes.
  @$pb.TagNumber(9)
  $core.int get flags => $_getIZ(3);
  @$pb.TagNumber(9)
  set flags($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(9)
  $core.bool hasFlags() => $_has(3);
  @$pb.TagNumber(9)
  void clearFlags() => $_clearField(9);

  /// The op's UUIDv7, 16 bytes (RFC 9562 byte order). Required. Its first
  /// 48 bits are the client's clock in ms (what client_timestamp_ms was),
  /// and bits 66..101 (bytes 8-12, after the variant bits) carry the
  /// sender's 36-bit user_id (§3): the server checks them against the
  /// session, so a receiver reads the sender from here. Clients dedupe on
  /// it and break ordering ties with it. A server-authored group event
  /// (payload starting 0x53) carries the acting user's bits the same way.
  @$pb.TagNumber(10)
  $core.List<$core.int> get opId => $_getN(4);
  @$pb.TagNumber(10)
  set opId($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(10)
  $core.bool hasOpId() => $_has(4);
  @$pb.TagNumber(10)
  void clearOpId() => $_clearField(10);

  /// A group's channel id: its UUID, 16 bytes. Absent for a DM: a DM
  /// channel is derived from the pair (TRIM_4_12_CONTRACT §1), the server
  /// from (sender, peer) and a receiver from (sender, peer) as well.
  @$pb.TagNumber(11)
  $core.List<$core.int> get channelId => $_getN(5);
  @$pb.TagNumber(11)
  set channelId($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(11)
  $core.bool hasChannelId() => $_has(5);
  @$pb.TagNumber(11)
  void clearChannelId() => $_clearField(11);

  /// A DM's other participant: the 36-bit user_id as 5 bytes, big-endian
  /// (the 9-hex id left-padded with one 0 nibble). Required on a DM,
  /// absent on a group. Echoed unchanged on fanout.
  @$pb.TagNumber(12)
  $core.List<$core.int> get peer => $_getN(6);
  @$pb.TagNumber(12)
  set peer($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(12)
  $core.bool hasPeer() => $_has(6);
  @$pb.TagNumber(12)
  void clearPeer() => $_clearField(12);

  /// Server-stamped on fanout: the sending device's id, its UUID as 16
  /// bytes. Absent on a server-authored event.
  @$pb.TagNumber(13)
  $core.List<$core.int> get senderDeviceId => $_getN(7);
  @$pb.TagNumber(13)
  set senderDeviceId($core.List<$core.int> value) => $_setBytes(7, value);
  @$pb.TagNumber(13)
  $core.bool hasSenderDeviceId() => $_has(7);
  @$pb.TagNumber(13)
  void clearSenderDeviceId() => $_clearField(13);

  /// Server-stamped on fanout; a client never sets it. When the server
  /// accepted the envelope, ms since epoch: with op_id, the channel's
  /// ordering key (server_timestamp_ms, op_id).
  @$pb.TagNumber(14)
  $fixnum.Int64 get serverTimestampMs => $_getI64(8);
  @$pb.TagNumber(14)
  set serverTimestampMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(14)
  $core.bool hasServerTimestampMs() => $_has(8);
  @$pb.TagNumber(14)
  void clearServerTimestampMs() => $_clearField(14);
}

/// -----------------------------------------------------------------------------
/// Ack — server's per-op response on the WS wire.
/// -----------------------------------------------------------------------------
///
/// One Ack per Envelope. Multiplexed across all in-flight ops; client
/// matches by `op_id`.
class Ack extends $pb.GeneratedMessage {
  factory Ack({
    AckOutcome? outcome,
    $core.String? reason,
    $fixnum.Int64? retryAfterMs,
    $fixnum.Int64? serverTimestampMs,
    $core.List<$core.int>? opId,
  }) {
    final result = create();
    if (outcome != null) result.outcome = outcome;
    if (reason != null) result.reason = reason;
    if (retryAfterMs != null) result.retryAfterMs = retryAfterMs;
    if (serverTimestampMs != null) result.serverTimestampMs = serverTimestampMs;
    if (opId != null) result.opId = opId;
    return result;
  }

  Ack._();

  factory Ack.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Ack.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ack',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3'),
      createEmptyInstance: create)
    ..aE<AckOutcome>(2, _omitFieldNames ? '' : 'outcome',
        enumValues: AckOutcome.values)
    ..aOS(3, _omitFieldNames ? '' : 'reason')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'retryAfterMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'serverTimestampMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'opId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ack clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ack copyWith(void Function(Ack) updates) =>
      super.copyWith((message) => updates(message as Ack)) as Ack;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Ack create() => Ack._();
  @$core.override
  Ack createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Ack getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Ack>(create);
  static Ack? _defaultInstance;

  @$pb.TagNumber(2)
  AckOutcome get outcome => $_getN(0);
  @$pb.TagNumber(2)
  set outcome(AckOutcome value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOutcome() => $_has(0);
  @$pb.TagNumber(2)
  void clearOutcome() => $_clearField(2);

  /// Server-defined code string. Populated for non-success outcomes.
  /// See SYNC_PROTOCOL.md §8 for the enumerated set:
  ///   forbidden, prefix_mismatch, rate_limited,
  ///   validation_failed, server_busy, storage_unavailable,
  ///   downstream_timeout, fanout_queue_full.
  @$pb.TagNumber(3)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(3)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(3)
  void clearReason() => $_clearField(3);

  /// Lower bound on retry delay. Populated on transient outcomes and
  /// on rate_limited.
  @$pb.TagNumber(4)
  $fixnum.Int64 get retryAfterMs => $_getI64(2);
  @$pb.TagNumber(4)
  set retryAfterMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(4)
  $core.bool hasRetryAfterMs() => $_has(2);
  @$pb.TagNumber(4)
  void clearRetryAfterMs() => $_clearField(4);

  /// Server-stamped on success: the same value the recipients get on the
  /// fanout Envelope, so the sender orders its own op without waiting.
  @$pb.TagNumber(5)
  $fixnum.Int64 get serverTimestampMs => $_getI64(3);
  @$pb.TagNumber(5)
  set serverTimestampMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(5)
  $core.bool hasServerTimestampMs() => $_has(3);
  @$pb.TagNumber(5)
  void clearServerTimestampMs() => $_clearField(5);

  /// The op this answers: its 16-byte UUIDv7, as sent.
  @$pb.TagNumber(7)
  $core.List<$core.int> get opId => $_getN(4);
  @$pb.TagNumber(7)
  set opId($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(7)
  $core.bool hasOpId() => $_has(4);
  @$pb.TagNumber(7)
  void clearOpId() => $_clearField(7);
}

enum WsEnvelope_Body { ops, acks, push, reauthRequired, error, notSet }

/// -----------------------------------------------------------------------------
/// WsEnvelope — multiplexer for the WebSocket frame channel.
/// -----------------------------------------------------------------------------
///
/// Each WS frame on `wss://<host>/wss` carries one WsEnvelope. The
/// `type` field discriminates which `body` variant is present.
///
/// Frame direction:
///   client→server: WS_OP only
///   server→client: WS_ACK, WS_PUSH, WS_REAUTH_REQUIRED, WS_ERROR
class WsEnvelope extends $pb.GeneratedMessage {
  factory WsEnvelope({
    WsType? type,
    EnvelopeBatch? ops,
    AckBatch? acks,
    Envelope? push,
    $core.bool? reauthRequired,
    WsError? error,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (ops != null) result.ops = ops;
    if (acks != null) result.acks = acks;
    if (push != null) result.push = push;
    if (reauthRequired != null) result.reauthRequired = reauthRequired;
    if (error != null) result.error = error;
    return result;
  }

  WsEnvelope._();

  factory WsEnvelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory WsEnvelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, WsEnvelope_Body> _WsEnvelope_BodyByTag = {
    10: WsEnvelope_Body.ops,
    11: WsEnvelope_Body.acks,
    12: WsEnvelope_Body.push,
    13: WsEnvelope_Body.reauthRequired,
    14: WsEnvelope_Body.error,
    0: WsEnvelope_Body.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WsEnvelope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3'),
      createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13, 14])
    ..aE<WsType>(1, _omitFieldNames ? '' : 'type', enumValues: WsType.values)
    ..aOM<EnvelopeBatch>(10, _omitFieldNames ? '' : 'ops',
        subBuilder: EnvelopeBatch.create)
    ..aOM<AckBatch>(11, _omitFieldNames ? '' : 'acks',
        subBuilder: AckBatch.create)
    ..aOM<Envelope>(12, _omitFieldNames ? '' : 'push',
        subBuilder: Envelope.create)
    ..aOB(13, _omitFieldNames ? '' : 'reauthRequired')
    ..aOM<WsError>(14, _omitFieldNames ? '' : 'error',
        subBuilder: WsError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WsEnvelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WsEnvelope copyWith(void Function(WsEnvelope) updates) =>
      super.copyWith((message) => updates(message as WsEnvelope)) as WsEnvelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WsEnvelope create() => WsEnvelope._();
  @$core.override
  WsEnvelope createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static WsEnvelope getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WsEnvelope>(create);
  static WsEnvelope? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  WsEnvelope_Body whichBody() => _WsEnvelope_BodyByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  void clearBody() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  WsType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(WsType value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(10)
  EnvelopeBatch get ops => $_getN(1);
  @$pb.TagNumber(10)
  set ops(EnvelopeBatch value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasOps() => $_has(1);
  @$pb.TagNumber(10)
  void clearOps() => $_clearField(10);
  @$pb.TagNumber(10)
  EnvelopeBatch ensureOps() => $_ensure(1);

  @$pb.TagNumber(11)
  AckBatch get acks => $_getN(2);
  @$pb.TagNumber(11)
  set acks(AckBatch value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasAcks() => $_has(2);
  @$pb.TagNumber(11)
  void clearAcks() => $_clearField(11);
  @$pb.TagNumber(11)
  AckBatch ensureAcks() => $_ensure(2);

  @$pb.TagNumber(12)
  Envelope get push => $_getN(3);
  @$pb.TagNumber(12)
  set push(Envelope value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasPush() => $_has(3);
  @$pb.TagNumber(12)
  void clearPush() => $_clearField(12);
  @$pb.TagNumber(12)
  Envelope ensurePush() => $_ensure(3);

  @$pb.TagNumber(13)
  $core.bool get reauthRequired => $_getBF(4);
  @$pb.TagNumber(13)
  set reauthRequired($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(13)
  $core.bool hasReauthRequired() => $_has(4);
  @$pb.TagNumber(13)
  void clearReauthRequired() => $_clearField(13);

  @$pb.TagNumber(14)
  WsError get error => $_getN(5);
  @$pb.TagNumber(14)
  set error(WsError value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(14)
  void clearError() => $_clearField(14);
  @$pb.TagNumber(14)
  WsError ensureError() => $_ensure(5);
}

/// One WsEnvelope MAY carry up to 20 envelopes per the WS batching cap
/// (SYNC_PROTOCOL.md §5.1.4). Server emits one Ack per Envelope, in any
/// order, multiplexed across the WS_ACK frames.
class EnvelopeBatch extends $pb.GeneratedMessage {
  factory EnvelopeBatch({
    $core.Iterable<Envelope>? envelopes,
  }) {
    final result = create();
    if (envelopes != null) result.envelopes.addAll(envelopes);
    return result;
  }

  EnvelopeBatch._();

  factory EnvelopeBatch.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EnvelopeBatch.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EnvelopeBatch',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3'),
      createEmptyInstance: create)
    ..pPM<Envelope>(1, _omitFieldNames ? '' : 'envelopes',
        subBuilder: Envelope.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnvelopeBatch clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EnvelopeBatch copyWith(void Function(EnvelopeBatch) updates) =>
      super.copyWith((message) => updates(message as EnvelopeBatch))
          as EnvelopeBatch;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EnvelopeBatch create() => EnvelopeBatch._();
  @$core.override
  EnvelopeBatch createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EnvelopeBatch getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EnvelopeBatch>(create);
  static EnvelopeBatch? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Envelope> get envelopes => $_getList(0);
}

class AckBatch extends $pb.GeneratedMessage {
  factory AckBatch({
    $core.Iterable<Ack>? acks,
  }) {
    final result = create();
    if (acks != null) result.acks.addAll(acks);
    return result;
  }

  AckBatch._();

  factory AckBatch.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AckBatch.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AckBatch',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3'),
      createEmptyInstance: create)
    ..pPM<Ack>(1, _omitFieldNames ? '' : 'acks', subBuilder: Ack.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AckBatch clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AckBatch copyWith(void Function(AckBatch) updates) =>
      super.copyWith((message) => updates(message as AckBatch)) as AckBatch;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AckBatch create() => AckBatch._();
  @$core.override
  AckBatch createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AckBatch getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AckBatch>(create);
  static AckBatch? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Ack> get acks => $_getList(0);
}

/// Protocol-level error not tied to a specific op. Server emits this
/// before closing the connection on malformed-frame / policy violations.
/// See SYNC_PROTOCOL.md §5.1.8.
class WsError extends $pb.GeneratedMessage {
  factory WsError({
    $core.String? code,
    $core.String? message,
  }) {
    final result = create();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    return result;
  }

  WsError._();

  factory WsError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory WsError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WsError',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'code')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WsError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WsError copyWith(void Function(WsError) updates) =>
      super.copyWith((message) => updates(message as WsError)) as WsError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WsError create() => WsError._();
  @$core.override
  WsError createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static WsError getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WsError>(create);
  static WsError? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get code => $_getSZ(0);
  @$pb.TagNumber(1)
  set code($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);
}

/// -----------------------------------------------------------------------------
/// PendingPage — the body of GET /v3.0/sync/pending (decision 218).
/// -----------------------------------------------------------------------------
///
/// application/x-protobuf. The device's timeline from its pointer on,
/// oldest first, each envelope exactly as a WS_PUSH carries it.
class PendingPage extends $pb.GeneratedMessage {
  factory PendingPage({
    $core.Iterable<Envelope>? envelopes,
    $core.bool? more,
  }) {
    final result = create();
    if (envelopes != null) result.envelopes.addAll(envelopes);
    if (more != null) result.more = more;
    return result;
  }

  PendingPage._();

  factory PendingPage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PendingPage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PendingPage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3'),
      createEmptyInstance: create)
    ..pPM<Envelope>(1, _omitFieldNames ? '' : 'envelopes',
        subBuilder: Envelope.create)
    ..aOB(2, _omitFieldNames ? '' : 'more')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PendingPage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PendingPage copyWith(void Function(PendingPage) updates) =>
      super.copyWith((message) => updates(message as PendingPage))
          as PendingPage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PendingPage create() => PendingPage._();
  @$core.override
  PendingPage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PendingPage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PendingPage>(create);
  static PendingPage? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Envelope> get envelopes => $_getList(0);

  /// More wait past this page: pull again from the last one's stamp.
  @$pb.TagNumber(2)
  $core.bool get more => $_getBF(1);
  @$pb.TagNumber(2)
  set more($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMore() => $_has(1);
  @$pb.TagNumber(2)
  void clearMore() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
