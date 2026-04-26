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
/// (sender_user_id, server_timestamp_ms, delivery_sequence) on fanout,
/// and delivers the same Envelope to every other channel member.
///
/// Recipients interpret `payload` according to the client-to-client
/// schema. The server's job ends at "delivered to channel members."
class Envelope extends $pb.GeneratedMessage {
  factory Envelope({
    $core.String? opId,
    $core.String? channelId,
    $fixnum.Int64? resourceSeq,
    $fixnum.Int64? clientTimestampMs,
    $core.List<$core.int>? payload,
    $core.bool? ephemeral,
    $core.String? senderUserId,
    $fixnum.Int64? serverTimestampMs,
    $fixnum.Int64? deliverySequence,
  }) {
    final result = create();
    if (opId != null) result.opId = opId;
    if (channelId != null) result.channelId = channelId;
    if (resourceSeq != null) result.resourceSeq = resourceSeq;
    if (clientTimestampMs != null) result.clientTimestampMs = clientTimestampMs;
    if (payload != null) result.payload = payload;
    if (ephemeral != null) result.ephemeral = ephemeral;
    if (senderUserId != null) result.senderUserId = senderUserId;
    if (serverTimestampMs != null) result.serverTimestampMs = serverTimestampMs;
    if (deliverySequence != null) result.deliverySequence = deliverySequence;
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
    ..aOS(1, _omitFieldNames ? '' : 'opId')
    ..aOS(2, _omitFieldNames ? '' : 'channelId')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'resourceSeq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'clientTimestampMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..aOB(6, _omitFieldNames ? '' : 'ephemeral')
    ..aOS(20, _omitFieldNames ? '' : 'senderUserId')
    ..a<$fixnum.Int64>(
        21, _omitFieldNames ? '' : 'serverTimestampMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        22, _omitFieldNames ? '' : 'deliverySequence', $pb.PbFieldType.OU6,
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

  /// Client-generated UUIDv7. The dedup key. Stable across retries.
  /// Required on client→server. Echoed unchanged on fanout.
  @$pb.TagNumber(1)
  $core.String get opId => $_getSZ(0);
  @$pb.TagNumber(1)
  set opId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOpId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOpId() => $_clearField(1);

  /// The channel this envelope targets. Server validates the sender is
  /// a member of this channel. Used as the `resource_id` for per-channel
  /// sequencing and dedup keying. Required.
  @$pb.TagNumber(2)
  $core.String get channelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set channelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasChannelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChannelId() => $_clearField(2);

  /// Per-channel monotonic counter, client-generated. Server validates
  /// strict increment per `(authenticated_user_id, channel_id)`.
  /// Required.
  @$pb.TagNumber(3)
  $fixnum.Int64 get resourceSeq => $_getI64(2);
  @$pb.TagNumber(3)
  set resourceSeq($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasResourceSeq() => $_has(2);
  @$pb.TagNumber(3)
  void clearResourceSeq() => $_clearField(3);

  /// Client wall-clock at op-creation, ms since epoch. Advisory only —
  /// server may use for audit logs and debugging; never for ordering
  /// (use resource_seq for that). Optional.
  @$pb.TagNumber(4)
  $fixnum.Int64 get clientTimestampMs => $_getI64(3);
  @$pb.TagNumber(4)
  set clientTimestampMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasClientTimestampMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearClientTimestampMs() => $_clearField(4);

  /// OPAQUE TO SERVER. Client-defined chat-content payload. The server
  /// does not parse, validate, or interpret these bytes — it only
  /// forwards them. Suggested client schema in v3-chat-payload.proto;
  /// clients are free to evolve it without server coordination.
  /// Required (zero-length allowed for client-defined "ping" semantics).
  @$pb.TagNumber(5)
  $core.List<$core.int> get payload => $_getN(4);
  @$pb.TagNumber(5)
  set payload($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPayload() => $_has(4);
  @$pb.TagNumber(5)
  void clearPayload() => $_clearField(5);

  /// Best-effort, no-persistence, no-ack signal. Drives "send-and-forget"
  /// events like typing indicators. Server semantics:
  ///   - Fan to currently-connected channel members verbatim.
  ///   - DO NOT enqueue for offline members (skip the undelivered queue).
  ///   - DO NOT emit an `Ack` back to the sender.
  ///   - DO NOT include in any history / sync-pull responses.
  ///
  /// Recipients that observe this flag bypass `op_id_seen` and any
  /// projection writes — these envelopes are routed to a side-channel
  /// (e.g. typing-indicator stream) and dropped from the persistent
  /// pipeline entirely. Senders construct ephemeral envelopes via a
  /// direct `WsTransport.sendEphemeral(...)` path that bypasses
  /// `outbound_ops`; if the WS is not connected the envelope is dropped.
  ///
  /// Wire compat: defaults to false, so older clients/servers that don't
  /// know about this field treat the envelope as a normal queued op —
  /// which is harmless for typing (wastes one row, never re-applied
  /// because the receiver-side dispatcher dedups by op_id) but the
  /// optimization only kicks in once both sides understand the flag.
  @$pb.TagNumber(6)
  $core.bool get ephemeral => $_getBF(5);
  @$pb.TagNumber(6)
  set ephemeral($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEphemeral() => $_has(5);
  @$pb.TagNumber(6)
  void clearEphemeral() => $_clearField(6);

  /// The authenticated sender's user_id (9 lowercase hex chars). Server
  /// derives from session, not from any client-supplied field. Recipients
  /// use this for sender attribution; see SYNC_PROTOCOL.md §10.1 for the
  /// display-name resolution rule (contact-book → username → phone).
  @$pb.TagNumber(20)
  $core.String get senderUserId => $_getSZ(6);
  @$pb.TagNumber(20)
  set senderUserId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(20)
  $core.bool hasSenderUserId() => $_has(6);
  @$pb.TagNumber(20)
  void clearSenderUserId() => $_clearField(20);

  /// When the server accepted the envelope, ms since epoch.
  @$pb.TagNumber(21)
  $fixnum.Int64 get serverTimestampMs => $_getI64(7);
  @$pb.TagNumber(21)
  set serverTimestampMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(21)
  $core.bool hasServerTimestampMs() => $_has(7);
  @$pb.TagNumber(21)
  void clearServerTimestampMs() => $_clearField(21);

  /// Per-channel monotonic sequence assigned by the server at fanout
  /// time. Used by recipients for inbound ordering across senders.
  /// Distinct from `resource_seq` (which is sender-scoped).
  @$pb.TagNumber(22)
  $fixnum.Int64 get deliverySequence => $_getI64(8);
  @$pb.TagNumber(22)
  set deliverySequence($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(22)
  $core.bool hasDeliverySequence() => $_has(8);
  @$pb.TagNumber(22)
  void clearDeliverySequence() => $_clearField(22);
}

/// -----------------------------------------------------------------------------
/// Ack — server's per-op response on the WS wire.
/// -----------------------------------------------------------------------------
///
/// One Ack per Envelope. Multiplexed across all in-flight ops; client
/// matches by `op_id`.
class Ack extends $pb.GeneratedMessage {
  factory Ack({
    $core.String? opId,
    AckOutcome? outcome,
    $core.String? reason,
    $fixnum.Int64? retryAfterMs,
    $fixnum.Int64? serverTimestampMs,
    $fixnum.Int64? deliverySequence,
  }) {
    final result = create();
    if (opId != null) result.opId = opId;
    if (outcome != null) result.outcome = outcome;
    if (reason != null) result.reason = reason;
    if (retryAfterMs != null) result.retryAfterMs = retryAfterMs;
    if (serverTimestampMs != null) result.serverTimestampMs = serverTimestampMs;
    if (deliverySequence != null) result.deliverySequence = deliverySequence;
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
    ..aOS(1, _omitFieldNames ? '' : 'opId')
    ..aE<AckOutcome>(2, _omitFieldNames ? '' : 'outcome',
        enumValues: AckOutcome.values)
    ..aOS(3, _omitFieldNames ? '' : 'reason')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'retryAfterMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'serverTimestampMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'deliverySequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
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

  @$pb.TagNumber(1)
  $core.String get opId => $_getSZ(0);
  @$pb.TagNumber(1)
  set opId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOpId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOpId() => $_clearField(1);

  @$pb.TagNumber(2)
  AckOutcome get outcome => $_getN(1);
  @$pb.TagNumber(2)
  set outcome(AckOutcome value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOutcome() => $_has(1);
  @$pb.TagNumber(2)
  void clearOutcome() => $_clearField(2);

  /// Server-defined code string. Populated for non-success outcomes.
  /// See SYNC_PROTOCOL.md §8 for the enumerated set:
  ///   forbidden, prefix_mismatch, out_of_order, rate_limited,
  ///   validation_failed, server_busy, storage_unavailable,
  ///   downstream_timeout, fanout_queue_full.
  /// Note: per SYNC_PROTOCOL.md §6a, reasons specific to chat-content
  /// semantics (gone, not_found-for-message, author-mismatch) do NOT
  /// appear here — the server does not interpret payloads, so it
  /// cannot produce those outcomes.
  @$pb.TagNumber(3)
  $core.String get reason => $_getSZ(2);
  @$pb.TagNumber(3)
  set reason($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReason() => $_has(2);
  @$pb.TagNumber(3)
  void clearReason() => $_clearField(3);

  /// Lower bound on retry delay. Populated on transient outcomes and
  /// on rate_limited.
  @$pb.TagNumber(4)
  $fixnum.Int64 get retryAfterMs => $_getI64(3);
  @$pb.TagNumber(4)
  set retryAfterMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRetryAfterMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearRetryAfterMs() => $_clearField(4);

  /// Server-stamped on success — same value the recipient sees on the
  /// fanout Envelope. Lets the sender's local store record a stable
  /// server timestamp without waiting for the fanout echo.
  @$pb.TagNumber(5)
  $fixnum.Int64 get serverTimestampMs => $_getI64(4);
  @$pb.TagNumber(5)
  set serverTimestampMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasServerTimestampMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearServerTimestampMs() => $_clearField(5);

  /// Server-stamped on success — same value as the fanout Envelope.
  @$pb.TagNumber(6)
  $fixnum.Int64 get deliverySequence => $_getI64(5);
  @$pb.TagNumber(6)
  set deliverySequence($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDeliverySequence() => $_has(5);
  @$pb.TagNumber(6)
  void clearDeliverySequence() => $_clearField(6);
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

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
