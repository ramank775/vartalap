// This is a generated file - do not edit.
//
// Generated from v3-server-event-payload.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'v3-server-event-payload.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'v3-server-event-payload.pbenum.dart';

enum ServerEventPayload_Body {
  channelCreated,
  memberAdded,
  memberRemoved,
  channelEdited,
  channelDeleted,
  profileEdited,
  usernameChanged,
  messageStateChanged,
  typing,
  notSet
}

/// -----------------------------------------------------------------------------
/// ServerEventPayload — what the server puts inside Envelope.payload bytes
/// for synthetic fanout from REST writes.
/// -----------------------------------------------------------------------------
///
/// One ServerEventPayload per fanout envelope. Recipients decode and
/// dispatch on `type`; the populated `body` oneof variant carries the
/// changed fields.
class ServerEventPayload extends $pb.GeneratedMessage {
  factory ServerEventPayload({
    $core.int? version,
    ServerEventType? type,
    ChannelCreated? channelCreated,
    ChannelMemberAdded? memberAdded,
    ChannelMemberRemoved? memberRemoved,
    ChannelEdited? channelEdited,
    ChannelDeleted? channelDeleted,
    ProfileEdited? profileEdited,
    UsernameChanged? usernameChanged,
    MessageStateChanged? messageStateChanged,
    Typing? typing,
  }) {
    final result = create();
    if (version != null) result.version = version;
    if (type != null) result.type = type;
    if (channelCreated != null) result.channelCreated = channelCreated;
    if (memberAdded != null) result.memberAdded = memberAdded;
    if (memberRemoved != null) result.memberRemoved = memberRemoved;
    if (channelEdited != null) result.channelEdited = channelEdited;
    if (channelDeleted != null) result.channelDeleted = channelDeleted;
    if (profileEdited != null) result.profileEdited = profileEdited;
    if (usernameChanged != null) result.usernameChanged = usernameChanged;
    if (messageStateChanged != null)
      result.messageStateChanged = messageStateChanged;
    if (typing != null) result.typing = typing;
    return result;
  }

  ServerEventPayload._();

  factory ServerEventPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ServerEventPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ServerEventPayload_Body>
      _ServerEventPayload_BodyByTag = {
    10: ServerEventPayload_Body.channelCreated,
    11: ServerEventPayload_Body.memberAdded,
    12: ServerEventPayload_Body.memberRemoved,
    13: ServerEventPayload_Body.channelEdited,
    14: ServerEventPayload_Body.channelDeleted,
    15: ServerEventPayload_Body.profileEdited,
    16: ServerEventPayload_Body.usernameChanged,
    17: ServerEventPayload_Body.messageStateChanged,
    18: ServerEventPayload_Body.typing,
    0: ServerEventPayload_Body.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ServerEventPayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18])
    ..aI(1, _omitFieldNames ? '' : 'version', fieldType: $pb.PbFieldType.OU3)
    ..aE<ServerEventType>(2, _omitFieldNames ? '' : 'type',
        enumValues: ServerEventType.values)
    ..aOM<ChannelCreated>(10, _omitFieldNames ? '' : 'channelCreated',
        subBuilder: ChannelCreated.create)
    ..aOM<ChannelMemberAdded>(11, _omitFieldNames ? '' : 'memberAdded',
        subBuilder: ChannelMemberAdded.create)
    ..aOM<ChannelMemberRemoved>(12, _omitFieldNames ? '' : 'memberRemoved',
        subBuilder: ChannelMemberRemoved.create)
    ..aOM<ChannelEdited>(13, _omitFieldNames ? '' : 'channelEdited',
        subBuilder: ChannelEdited.create)
    ..aOM<ChannelDeleted>(14, _omitFieldNames ? '' : 'channelDeleted',
        subBuilder: ChannelDeleted.create)
    ..aOM<ProfileEdited>(15, _omitFieldNames ? '' : 'profileEdited',
        subBuilder: ProfileEdited.create)
    ..aOM<UsernameChanged>(16, _omitFieldNames ? '' : 'usernameChanged',
        subBuilder: UsernameChanged.create)
    ..aOM<MessageStateChanged>(17, _omitFieldNames ? '' : 'messageStateChanged',
        subBuilder: MessageStateChanged.create)
    ..aOM<Typing>(18, _omitFieldNames ? '' : 'typing',
        subBuilder: Typing.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerEventPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerEventPayload copyWith(void Function(ServerEventPayload) updates) =>
      super.copyWith((message) => updates(message as ServerEventPayload))
          as ServerEventPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ServerEventPayload create() => ServerEventPayload._();
  @$core.override
  ServerEventPayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ServerEventPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ServerEventPayload>(create);
  static ServerEventPayload? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  ServerEventPayload_Body whichBody() =>
      _ServerEventPayload_BodyByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  void clearBody() => $_clearField($_whichOneof(0));

  /// Server-authored schema version. Bumped only when the wire shape
  /// changes in a way clients must opt into; additive variants do NOT
  /// bump this.
  @$pb.TagNumber(1)
  $core.int get version => $_getIZ(0);
  @$pb.TagNumber(1)
  set version($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => $_clearField(1);

  /// What kind of server-state change this envelope describes. Recipients
  /// route on this; the matching `body` variant carries the data.
  @$pb.TagNumber(2)
  ServerEventType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(ServerEventType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(10)
  ChannelCreated get channelCreated => $_getN(2);
  @$pb.TagNumber(10)
  set channelCreated(ChannelCreated value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasChannelCreated() => $_has(2);
  @$pb.TagNumber(10)
  void clearChannelCreated() => $_clearField(10);
  @$pb.TagNumber(10)
  ChannelCreated ensureChannelCreated() => $_ensure(2);

  @$pb.TagNumber(11)
  ChannelMemberAdded get memberAdded => $_getN(3);
  @$pb.TagNumber(11)
  set memberAdded(ChannelMemberAdded value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasMemberAdded() => $_has(3);
  @$pb.TagNumber(11)
  void clearMemberAdded() => $_clearField(11);
  @$pb.TagNumber(11)
  ChannelMemberAdded ensureMemberAdded() => $_ensure(3);

  @$pb.TagNumber(12)
  ChannelMemberRemoved get memberRemoved => $_getN(4);
  @$pb.TagNumber(12)
  set memberRemoved(ChannelMemberRemoved value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasMemberRemoved() => $_has(4);
  @$pb.TagNumber(12)
  void clearMemberRemoved() => $_clearField(12);
  @$pb.TagNumber(12)
  ChannelMemberRemoved ensureMemberRemoved() => $_ensure(4);

  @$pb.TagNumber(13)
  ChannelEdited get channelEdited => $_getN(5);
  @$pb.TagNumber(13)
  set channelEdited(ChannelEdited value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasChannelEdited() => $_has(5);
  @$pb.TagNumber(13)
  void clearChannelEdited() => $_clearField(13);
  @$pb.TagNumber(13)
  ChannelEdited ensureChannelEdited() => $_ensure(5);

  @$pb.TagNumber(14)
  ChannelDeleted get channelDeleted => $_getN(6);
  @$pb.TagNumber(14)
  set channelDeleted(ChannelDeleted value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasChannelDeleted() => $_has(6);
  @$pb.TagNumber(14)
  void clearChannelDeleted() => $_clearField(14);
  @$pb.TagNumber(14)
  ChannelDeleted ensureChannelDeleted() => $_ensure(6);

  @$pb.TagNumber(15)
  ProfileEdited get profileEdited => $_getN(7);
  @$pb.TagNumber(15)
  set profileEdited(ProfileEdited value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasProfileEdited() => $_has(7);
  @$pb.TagNumber(15)
  void clearProfileEdited() => $_clearField(15);
  @$pb.TagNumber(15)
  ProfileEdited ensureProfileEdited() => $_ensure(7);

  @$pb.TagNumber(16)
  UsernameChanged get usernameChanged => $_getN(8);
  @$pb.TagNumber(16)
  set usernameChanged(UsernameChanged value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasUsernameChanged() => $_has(8);
  @$pb.TagNumber(16)
  void clearUsernameChanged() => $_clearField(16);
  @$pb.TagNumber(16)
  UsernameChanged ensureUsernameChanged() => $_ensure(8);

  @$pb.TagNumber(17)
  MessageStateChanged get messageStateChanged => $_getN(9);
  @$pb.TagNumber(17)
  set messageStateChanged(MessageStateChanged value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasMessageStateChanged() => $_has(9);
  @$pb.TagNumber(17)
  void clearMessageStateChanged() => $_clearField(17);
  @$pb.TagNumber(17)
  MessageStateChanged ensureMessageStateChanged() => $_ensure(9);

  @$pb.TagNumber(18)
  Typing get typing => $_getN(10);
  @$pb.TagNumber(18)
  set typing(Typing value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasTyping() => $_has(10);
  @$pb.TagNumber(18)
  void clearTyping() => $_clearField(18);
  @$pb.TagNumber(18)
  Typing ensureTyping() => $_ensure(10);
}

/// Emitted on REST `POST /v3.0/channels` to every member (creator included
/// — see commit e0e6bfe aligning the contract with chat-server behavior).
///
/// Recipients use this to materialize the channel locally without waiting
/// for the next list refresh.
class ChannelCreated extends $pb.GeneratedMessage {
  factory ChannelCreated({
    $core.String? channelId,
    $core.String? kind,
    $core.String? name,
    $core.Iterable<$core.String>? members,
    $core.String? creator,
    $fixnum.Int64? createdAtMs,
  }) {
    final result = create();
    if (channelId != null) result.channelId = channelId;
    if (kind != null) result.kind = kind;
    if (name != null) result.name = name;
    if (members != null) result.members.addAll(members);
    if (creator != null) result.creator = creator;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    return result;
  }

  ChannelCreated._();

  factory ChannelCreated.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChannelCreated.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChannelCreated',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'channelId')
    ..aOS(2, _omitFieldNames ? '' : 'kind')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..pPS(4, _omitFieldNames ? '' : 'members')
    ..aOS(5, _omitFieldNames ? '' : 'creator')
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'createdAtMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelCreated clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelCreated copyWith(void Function(ChannelCreated) updates) =>
      super.copyWith((message) => updates(message as ChannelCreated))
          as ChannelCreated;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelCreated create() => ChannelCreated._();
  @$core.override
  ChannelCreated createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChannelCreated getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChannelCreated>(create);
  static ChannelCreated? _defaultInstance;

  /// Server-assigned channel id.
  @$pb.TagNumber(1)
  $core.String get channelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set channelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => $_clearField(1);

  /// "one_to_one" or "group". Kept as a string (not an enum) to mirror the
  /// wire vocabulary in REST and keep this proto evolution-friendly when
  /// new kinds appear (e.g. "broadcast"); recipients that don't recognize
  /// a kind SHOULD treat the channel as a group with read-only fallbacks.
  @$pb.TagNumber(2)
  $core.String get kind => $_getSZ(1);
  @$pb.TagNumber(2)
  set kind($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  /// Display name. May be empty for one_to_one channels — clients derive
  /// the displayed name from the peer's profile in that case.
  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  /// Full member roster including the creator. Recipients persist this
  /// verbatim into `channel_members`.
  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get members => $_getList(3);

  /// Creator's user_id (9 lowercase hex chars). Always one of `members`.
  @$pb.TagNumber(5)
  $core.String get creator => $_getSZ(4);
  @$pb.TagNumber(5)
  set creator($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCreator() => $_has(4);
  @$pb.TagNumber(5)
  void clearCreator() => $_clearField(5);

  /// Server's authoritative creation timestamp, ms since epoch. Maps to
  /// the `channels.created_at_ms` column on the recipient. Sourced from
  /// the same clock the server stamps on `POST /v3.0/channels` REST
  /// responses.
  @$pb.TagNumber(6)
  $fixnum.Int64 get createdAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCreatedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearCreatedAtMs() => $_clearField(6);
}

/// Emitted on REST `add_members` to existing members + the newly added
/// users. The recipient's view: "these `members` joined `channel_id`."
class ChannelMemberAdded extends $pb.GeneratedMessage {
  factory ChannelMemberAdded({
    $core.String? channelId,
    $core.Iterable<$core.String>? members,
    $fixnum.Int64? addedAtMs,
  }) {
    final result = create();
    if (channelId != null) result.channelId = channelId;
    if (members != null) result.members.addAll(members);
    if (addedAtMs != null) result.addedAtMs = addedAtMs;
    return result;
  }

  ChannelMemberAdded._();

  factory ChannelMemberAdded.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChannelMemberAdded.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChannelMemberAdded',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'channelId')
    ..pPS(2, _omitFieldNames ? '' : 'members')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'addedAtMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelMemberAdded clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelMemberAdded copyWith(void Function(ChannelMemberAdded) updates) =>
      super.copyWith((message) => updates(message as ChannelMemberAdded))
          as ChannelMemberAdded;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelMemberAdded create() => ChannelMemberAdded._();
  @$core.override
  ChannelMemberAdded createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChannelMemberAdded getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChannelMemberAdded>(create);
  static ChannelMemberAdded? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get channelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set channelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => $_clearField(1);

  /// Newly added user_ids. Existing members are NOT included here — the
  /// recipient already has them in local state.
  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get members => $_getList(1);

  /// When the server applied the add, ms since epoch.
  @$pb.TagNumber(3)
  $fixnum.Int64 get addedAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set addedAtMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAddedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearAddedAtMs() => $_clearField(3);
}

/// Emitted on REST `remove_member` to remaining members + the removed
/// member (so the removed user's client knows to leave).
class ChannelMemberRemoved extends $pb.GeneratedMessage {
  factory ChannelMemberRemoved({
    $core.String? channelId,
    $core.String? member,
    $fixnum.Int64? removedAtMs,
  }) {
    final result = create();
    if (channelId != null) result.channelId = channelId;
    if (member != null) result.member = member;
    if (removedAtMs != null) result.removedAtMs = removedAtMs;
    return result;
  }

  ChannelMemberRemoved._();

  factory ChannelMemberRemoved.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChannelMemberRemoved.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChannelMemberRemoved',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'channelId')
    ..aOS(2, _omitFieldNames ? '' : 'member')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'removedAtMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelMemberRemoved clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelMemberRemoved copyWith(void Function(ChannelMemberRemoved) updates) =>
      super.copyWith((message) => updates(message as ChannelMemberRemoved))
          as ChannelMemberRemoved;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelMemberRemoved create() => ChannelMemberRemoved._();
  @$core.override
  ChannelMemberRemoved createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChannelMemberRemoved getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChannelMemberRemoved>(create);
  static ChannelMemberRemoved? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get channelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set channelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => $_clearField(1);

  /// Single removed user_id. The doc spec lists this as scalar (not
  /// repeated) — server emits one event per removal.
  @$pb.TagNumber(2)
  $core.String get member => $_getSZ(1);
  @$pb.TagNumber(2)
  set member($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMember() => $_has(1);
  @$pb.TagNumber(2)
  void clearMember() => $_clearField(2);

  /// When the server applied the removal, ms since epoch.
  @$pb.TagNumber(3)
  $fixnum.Int64 get removedAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set removedAtMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRemovedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearRemovedAtMs() => $_clearField(3);
}

/// Emitted on REST `edit_channel` (rename / avatar change) to all members.
/// Both `name` and `avatar_url` are proto3 `optional` so absent-vs-empty
/// survives — an edit that clears the avatar sends `avatar_url=""` with
/// the field present; an edit that only renames omits `avatar_url`.
class ChannelEdited extends $pb.GeneratedMessage {
  factory ChannelEdited({
    $core.String? channelId,
    $core.String? name,
    $core.String? avatarUrl,
    $fixnum.Int64? editedAtMs,
  }) {
    final result = create();
    if (channelId != null) result.channelId = channelId;
    if (name != null) result.name = name;
    if (avatarUrl != null) result.avatarUrl = avatarUrl;
    if (editedAtMs != null) result.editedAtMs = editedAtMs;
    return result;
  }

  ChannelEdited._();

  factory ChannelEdited.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChannelEdited.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChannelEdited',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'channelId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'avatarUrl')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'editedAtMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelEdited clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelEdited copyWith(void Function(ChannelEdited) updates) =>
      super.copyWith((message) => updates(message as ChannelEdited))
          as ChannelEdited;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelEdited create() => ChannelEdited._();
  @$core.override
  ChannelEdited createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChannelEdited getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChannelEdited>(create);
  static ChannelEdited? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get channelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set channelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get avatarUrl => $_getSZ(2);
  @$pb.TagNumber(3)
  set avatarUrl($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAvatarUrl() => $_has(2);
  @$pb.TagNumber(3)
  void clearAvatarUrl() => $_clearField(3);

  /// When the server applied the edit, ms since epoch.
  @$pb.TagNumber(4)
  $fixnum.Int64 get editedAtMs => $_getI64(3);
  @$pb.TagNumber(4)
  set editedAtMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEditedAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearEditedAtMs() => $_clearField(4);
}

/// Emitted on REST `DELETE /v3.0/channels/<id>` (or equivalent) to all
/// members. Recipients tombstone the channel locally.
class ChannelDeleted extends $pb.GeneratedMessage {
  factory ChannelDeleted({
    $core.String? channelId,
    $fixnum.Int64? deletedAtMs,
  }) {
    final result = create();
    if (channelId != null) result.channelId = channelId;
    if (deletedAtMs != null) result.deletedAtMs = deletedAtMs;
    return result;
  }

  ChannelDeleted._();

  factory ChannelDeleted.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChannelDeleted.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChannelDeleted',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'channelId')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'deletedAtMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelDeleted clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChannelDeleted copyWith(void Function(ChannelDeleted) updates) =>
      super.copyWith((message) => updates(message as ChannelDeleted))
          as ChannelDeleted;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelDeleted create() => ChannelDeleted._();
  @$core.override
  ChannelDeleted createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChannelDeleted getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChannelDeleted>(create);
  static ChannelDeleted? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get channelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set channelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => $_clearField(1);

  /// When the server applied the delete, ms since epoch.
  @$pb.TagNumber(2)
  $fixnum.Int64 get deletedAtMs => $_getI64(1);
  @$pb.TagNumber(2)
  set deletedAtMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeletedAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeletedAtMs() => $_clearField(2);
}

/// Emitted on REST `PATCH /v3.0/users/me` with profile fields, to every
/// user sharing at least one channel with the editor (v3.0 scope).
///
/// Each field is `optional` so a partial patch (e.g. only display_name)
/// can be transmitted without forcing recipients to guess at unset vs
/// cleared. An explicit empty string with the field PRESENT means the
/// user cleared that field.
class ProfileEdited extends $pb.GeneratedMessage {
  factory ProfileEdited({
    $core.String? userId,
    $core.String? displayName,
    $core.String? avatarUrl,
    $core.String? statusText,
    $fixnum.Int64? editedAtMs,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (displayName != null) result.displayName = displayName;
    if (avatarUrl != null) result.avatarUrl = avatarUrl;
    if (statusText != null) result.statusText = statusText;
    if (editedAtMs != null) result.editedAtMs = editedAtMs;
    return result;
  }

  ProfileEdited._();

  factory ProfileEdited.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ProfileEdited.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProfileEdited',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOS(3, _omitFieldNames ? '' : 'avatarUrl')
    ..aOS(4, _omitFieldNames ? '' : 'statusText')
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'editedAtMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProfileEdited clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProfileEdited copyWith(void Function(ProfileEdited) updates) =>
      super.copyWith((message) => updates(message as ProfileEdited))
          as ProfileEdited;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProfileEdited create() => ProfileEdited._();
  @$core.override
  ProfileEdited createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ProfileEdited getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ProfileEdited>(create);
  static ProfileEdited? _defaultInstance;

  /// The editing user's user_id.
  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get avatarUrl => $_getSZ(2);
  @$pb.TagNumber(3)
  set avatarUrl($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAvatarUrl() => $_has(2);
  @$pb.TagNumber(3)
  void clearAvatarUrl() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get statusText => $_getSZ(3);
  @$pb.TagNumber(4)
  set statusText($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStatusText() => $_has(3);
  @$pb.TagNumber(4)
  void clearStatusText() => $_clearField(4);

  /// When the server applied the edit, ms since epoch.
  @$pb.TagNumber(5)
  $fixnum.Int64 get editedAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set editedAtMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEditedAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearEditedAtMs() => $_clearField(5);
}

/// Emitted on REST `PATCH /v3.0/users/me` with `username`, same fanout
/// scope as ProfileEdited.
///
/// `new_username` MAY be empty: per SYNC_PROTOCOL.md §10.2 the new
/// username may be null, signaling the user cleared their handle.
/// Recipients treat empty as null (drop the cached username; fall back
/// to phone / placeholder per AUTH_CONTRACT §2.4).
class UsernameChanged extends $pb.GeneratedMessage {
  factory UsernameChanged({
    $core.String? userId,
    $core.String? newUsername,
    $fixnum.Int64? changedAtMs,
  }) {
    final result = create();
    if (userId != null) result.userId = userId;
    if (newUsername != null) result.newUsername = newUsername;
    if (changedAtMs != null) result.changedAtMs = changedAtMs;
    return result;
  }

  UsernameChanged._();

  factory UsernameChanged.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UsernameChanged.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UsernameChanged',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'newUsername')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'changedAtMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UsernameChanged clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UsernameChanged copyWith(void Function(UsernameChanged) updates) =>
      super.copyWith((message) => updates(message as UsernameChanged))
          as UsernameChanged;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UsernameChanged create() => UsernameChanged._();
  @$core.override
  UsernameChanged createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UsernameChanged getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UsernameChanged>(create);
  static UsernameChanged? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  /// New handle. Empty string == cleared (treat as null).
  @$pb.TagNumber(2)
  $core.String get newUsername => $_getSZ(1);
  @$pb.TagNumber(2)
  set newUsername($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNewUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewUsername() => $_clearField(2);

  /// When the server applied the change, ms since epoch.
  @$pb.TagNumber(3)
  $fixnum.Int64 get changedAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set changedAtMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasChangedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearChangedAtMs() => $_clearField(3);
}

/// Generic message receipt event: sent back to the message AUTHOR when
/// the server observes the message transitioning to a new state. One
/// event per transition. v3.0 emits this on:
///   - delivered: server fans out to a recipient WS, or a recipient
///     drains from undelivered queue.
///   - read: a recipient client posts a read receipt.
///   - rejected: server retracts a previously-acked message (moderation,
///     quota, etc.) — rare; reserved.
///
/// Recipients flip the local `messages.message_state` accordingly.
/// Out-of-order events are tolerated: states are monotonic in the
/// author's UI (delivered cannot revert to sent), so a stale event is
/// dropped client-side if `new_state` is "older" than what's stored.
/// EPHEMERAL: typing indicator. Client-authored despite living under the
/// 0x53 ServerEventPayload namespace (see the §10.2 routing-tag note —
/// 0x53 is the wire discriminator, not a provenance claim).
///
/// CONTRACT (different from every other variant in this file):
///   - The originating client bypasses `outbound_ops` entirely and calls
///     `WsTransport.send` directly with a one-shot op_id. If the WS is
///     not connected the event is DROPPED — typing is lossy by design.
///   - The server fans the frame verbatim to the other channel members
///     and DOES NOT persist or queue it. Recipients who are offline at
///     fanout time MUST NOT receive it on reconnect.
///   - Recipients show the indicator with a short TTL (~6s in v3.0) so
///     a missed `is_typing=false` doesn't strand the UI.
///
/// Why server-event-namespaced rather than a new ChatPayload variant:
/// the 0x53 prefix already routes unconditionally to the receiver's
/// no-op-friendly dispatcher; ChatPayload mutations would be more
/// invasive and would imply persistence on the receiver side.
class Typing extends $pb.GeneratedMessage {
  factory Typing({
    $core.bool? isTyping,
  }) {
    final result = create();
    if (isTyping != null) result.isTyping = isTyping;
    return result;
  }

  Typing._();

  factory Typing.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Typing.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Typing',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isTyping')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Typing clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Typing copyWith(void Function(Typing) updates) =>
      super.copyWith((message) => updates(message as Typing)) as Typing;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Typing create() => Typing._();
  @$core.override
  Typing createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Typing getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Typing>(create);
  static Typing? _defaultInstance;

  /// True = composing started/ongoing; false = composing stopped.
  /// Senders typically emit `true` once on first keystroke after a
  /// quiet period and `false` after ~4s of inactivity (or on send).
  ///
  /// Channel, sender, and timestamp are all carried by the surrounding
  /// Envelope (`channel_id`, `sender_user_id`, `client_timestamp_ms`)
  /// and intentionally NOT duplicated here — keeping the typing payload
  /// a single byte on the wire (proto3 default-false is not encoded;
  /// is_typing=true encodes as 2 bytes).
  @$pb.TagNumber(1)
  $core.bool get isTyping => $_getBF(0);
  @$pb.TagNumber(1)
  set isTyping($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsTyping() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsTyping() => $_clearField(1);
}

class MessageStateChanged extends $pb.GeneratedMessage {
  factory MessageStateChanged({
    $core.String? channelId,
    $core.String? messageId,
    MessageStateValue? newState,
    $fixnum.Int64? changedAtMs,
    $core.String? recipientUserId,
  }) {
    final result = create();
    if (channelId != null) result.channelId = channelId;
    if (messageId != null) result.messageId = messageId;
    if (newState != null) result.newState = newState;
    if (changedAtMs != null) result.changedAtMs = changedAtMs;
    if (recipientUserId != null) result.recipientUserId = recipientUserId;
    return result;
  }

  MessageStateChanged._();

  factory MessageStateChanged.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MessageStateChanged.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MessageStateChanged',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'channelId')
    ..aOS(2, _omitFieldNames ? '' : 'messageId')
    ..aE<MessageStateValue>(3, _omitFieldNames ? '' : 'newState',
        enumValues: MessageStateValue.values)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'changedAtMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(5, _omitFieldNames ? '' : 'recipientUserId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessageStateChanged clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessageStateChanged copyWith(void Function(MessageStateChanged) updates) =>
      super.copyWith((message) => updates(message as MessageStateChanged))
          as MessageStateChanged;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MessageStateChanged create() => MessageStateChanged._();
  @$core.override
  MessageStateChanged createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MessageStateChanged getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MessageStateChanged>(create);
  static MessageStateChanged? _defaultInstance;

  /// Channel the original message was sent to.
  @$pb.TagNumber(1)
  $core.String get channelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set channelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => $_clearField(1);

  /// The original message_id (chat payload's message_id, NOT op_id).
  @$pb.TagNumber(2)
  $core.String get messageId => $_getSZ(1);
  @$pb.TagNumber(2)
  set messageId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessageId() => $_clearField(2);

  /// The state being transitioned INTO.
  @$pb.TagNumber(3)
  MessageStateValue get newState => $_getN(2);
  @$pb.TagNumber(3)
  set newState(MessageStateValue value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasNewState() => $_has(2);
  @$pb.TagNumber(3)
  void clearNewState() => $_clearField(3);

  /// When the server observed the transition, ms since epoch.
  @$pb.TagNumber(4)
  $fixnum.Int64 get changedAtMs => $_getI64(3);
  @$pb.TagNumber(4)
  set changedAtMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasChangedAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearChangedAtMs() => $_clearField(4);

  /// For per-recipient granularity in group DMs (v3.1+). Empty in v3.0
  /// one-to-one channels.
  @$pb.TagNumber(5)
  $core.String get recipientUserId => $_getSZ(4);
  @$pb.TagNumber(5)
  set recipientUserId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRecipientUserId() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecipientUserId() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
