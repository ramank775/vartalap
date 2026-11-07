// This is a generated file - do not edit.
//
// Generated from v3-chat-payload.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'v3-chat-payload.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'v3-chat-payload.pbenum.dart';

/// -----------------------------------------------------------------------------
/// ChatPayload — what clients put inside Envelope.payload bytes.
/// -----------------------------------------------------------------------------
///
/// Every chat-content event the user takes (send a message, edit one,
/// delete one, react, unreact, forward) serializes to a ChatPayload,
/// which is then encoded as bytes and stuffed into Envelope.payload.
///
/// The server sees only the encoded bytes. Recipients decode and
/// dispatch on `type`.
class ChatPayload extends $pb.GeneratedMessage {
  factory ChatPayload({
    $core.int? version,
    ChatPayloadType? type,
    $core.List<$core.int>? messageId,
    $core.List<$core.int>? groupId,
    $core.String? body,
    $core.String? contentType,
    $core.Iterable<Attachment>? attachments,
    $core.List<$core.int>? replyToMessageId,
    $core.String? emoji,
    ForwardSource? forwardSource,
    $core.bool? isTyping,
    $fixnum.Int64? markerServerTimestampMs,
    $core.int? timerSec,
    $core.List<$core.int>? secureBox,
    $core.List<$core.int>? secureKey,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? meta,
    LiveLocationPoint? liveLocationPoint,
    $core.int? liveLocationDurationSec,
    $core.bool? liveLocationAllowed,
  }) {
    final result = create();
    if (version != null) result.version = version;
    if (type != null) result.type = type;
    if (messageId != null) result.messageId = messageId;
    if (groupId != null) result.groupId = groupId;
    if (body != null) result.body = body;
    if (contentType != null) result.contentType = contentType;
    if (attachments != null) result.attachments.addAll(attachments);
    if (replyToMessageId != null) result.replyToMessageId = replyToMessageId;
    if (emoji != null) result.emoji = emoji;
    if (forwardSource != null) result.forwardSource = forwardSource;
    if (isTyping != null) result.isTyping = isTyping;
    if (markerServerTimestampMs != null)
      result.markerServerTimestampMs = markerServerTimestampMs;
    if (timerSec != null) result.timerSec = timerSec;
    if (secureBox != null) result.secureBox = secureBox;
    if (secureKey != null) result.secureKey = secureKey;
    if (meta != null) result.meta.addEntries(meta);
    if (liveLocationPoint != null) result.liveLocationPoint = liveLocationPoint;
    if (liveLocationDurationSec != null)
      result.liveLocationDurationSec = liveLocationDurationSec;
    if (liveLocationAllowed != null)
      result.liveLocationAllowed = liveLocationAllowed;
    return result;
  }

  ChatPayload._();

  factory ChatPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatPayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'version', fieldType: $pb.PbFieldType.OU3)
    ..aE<ChatPayloadType>(2, _omitFieldNames ? '' : 'type',
        enumValues: ChatPayloadType.values)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..aOS(10, _omitFieldNames ? '' : 'body')
    ..aOS(11, _omitFieldNames ? '' : 'contentType')
    ..pPM<Attachment>(12, _omitFieldNames ? '' : 'attachments',
        subBuilder: Attachment.create)
    ..a<$core.List<$core.int>>(
        21, _omitFieldNames ? '' : 'replyToMessageId', $pb.PbFieldType.OY)
    ..aOS(30, _omitFieldNames ? '' : 'emoji')
    ..aOM<ForwardSource>(40, _omitFieldNames ? '' : 'forwardSource',
        subBuilder: ForwardSource.create)
    ..aOB(50, _omitFieldNames ? '' : 'isTyping')
    ..a<$fixnum.Int64>(60, _omitFieldNames ? '' : 'markerServerTimestampMs',
        $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(70, _omitFieldNames ? '' : 'timerSec', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        71, _omitFieldNames ? '' : 'secureBox', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        72, _omitFieldNames ? '' : 'secureKey', $pb.PbFieldType.OY)
    ..m<$core.String, $core.String>(100, _omitFieldNames ? '' : 'meta',
        entryClassName: 'ChatPayload.MetaEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('vartalap.v3.payload'))
    ..aOM<LiveLocationPoint>(130, _omitFieldNames ? '' : 'liveLocationPoint',
        subBuilder: LiveLocationPoint.create)
    ..aI(131, _omitFieldNames ? '' : 'liveLocationDurationSec',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(132, _omitFieldNames ? '' : 'liveLocationAllowed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatPayload copyWith(void Function(ChatPayload) updates) =>
      super.copyWith((message) => updates(message as ChatPayload))
          as ChatPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatPayload create() => ChatPayload._();
  @$core.override
  ChatPayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatPayload>(create);
  static ChatPayload? _defaultInstance;

  /// Client-to-client schema version. Allows clients to evolve this
  /// file and detect peers that don't speak the new version.
  @$pb.TagNumber(1)
  $core.int get version => $_getIZ(0);
  @$pb.TagNumber(1)
  set version($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => $_clearField(1);

  /// What kind of chat-content event this is.
  @$pb.TagNumber(2)
  ChatPayloadType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(ChatPayloadType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  /// The message this payload acts on, its UUIDv7 as 16 bytes. For
  /// TYPE_MESSAGE_CREATE and TYPE_MESSAGE_FORWARD, this is the new
  /// message's id (client-generated). For UPDATE / DELETE / REACTION_*,
  /// this is the existing message being targeted. Unused (empty) for
  /// TYPE_TYPING and for receipts, which carry only
  /// `marker_server_timestamp_ms`.
  @$pb.TagNumber(4)
  $core.List<$core.int> get messageId => $_getN(2);
  @$pb.TagNumber(4)
  set messageId($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(4)
  $core.bool hasMessageId() => $_has(2);
  @$pb.TagNumber(4)
  void clearMessageId() => $_clearField(4);

  /// For TYPE_READ_RECEIPT, TYPE_DELIVERY_RECEIPT sent over a 1:1
  /// channel on behalf of a group (decision 218): the group's channel
  /// id, 16 bytes. A group receipt goes only to the members whose
  /// messages it acknowledges, each over their 1:1 channel; the author
  /// applies it to their own messages in this group. Empty for a DM's
  /// own receipt.
  @$pb.TagNumber(5)
  $core.List<$core.int> get groupId => $_getN(3);
  @$pb.TagNumber(5)
  set groupId($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(5)
  $core.bool hasGroupId() => $_has(3);
  @$pb.TagNumber(5)
  void clearGroupId() => $_clearField(5);

  /// For TYPE_MESSAGE_CREATE, TYPE_MESSAGE_UPDATE, TYPE_MESSAGE_FORWARD.
  @$pb.TagNumber(10)
  $core.String get body => $_getSZ(4);
  @$pb.TagNumber(10)
  set body($core.String value) => $_setString(4, value);
  @$pb.TagNumber(10)
  $core.bool hasBody() => $_has(4);
  @$pb.TagNumber(10)
  void clearBody() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get contentType => $_getSZ(5);
  @$pb.TagNumber(11)
  set contentType($core.String value) => $_setString(5, value);
  @$pb.TagNumber(11)
  $core.bool hasContentType() => $_has(5);
  @$pb.TagNumber(11)
  void clearContentType() => $_clearField(11);

  /// With attachments: the first one's type, except
  /// "audio/x-vartalap-voice" for a voice note recorded in the app (the
  /// attachment keeps its own audio type); any other audio/* is an audio
  /// file. Without: "text/vcard", "text/x-geo" and "text/calendar" mark
  /// contact, location and event messages, standard text in `body`.
  @$pb.TagNumber(12)
  $pb.PbList<Attachment> get attachments => $_getList(6);

  /// For TYPE_MESSAGE_CREATE, TYPE_MESSAGE_FORWARD: the quoted
  /// message's id, 16 bytes.
  @$pb.TagNumber(21)
  $core.List<$core.int> get replyToMessageId => $_getN(7);
  @$pb.TagNumber(21)
  set replyToMessageId($core.List<$core.int> value) => $_setBytes(7, value);
  @$pb.TagNumber(21)
  $core.bool hasReplyToMessageId() => $_has(7);
  @$pb.TagNumber(21)
  void clearReplyToMessageId() => $_clearField(21);

  /// For TYPE_REACTION_ADD, TYPE_REACTION_REMOVE.
  @$pb.TagNumber(30)
  $core.String get emoji => $_getSZ(8);
  @$pb.TagNumber(30)
  set emoji($core.String value) => $_setString(8, value);
  @$pb.TagNumber(30)
  $core.bool hasEmoji() => $_has(8);
  @$pb.TagNumber(30)
  void clearEmoji() => $_clearField(30);

  /// For TYPE_MESSAGE_FORWARD.
  @$pb.TagNumber(40)
  ForwardSource get forwardSource => $_getN(9);
  @$pb.TagNumber(40)
  set forwardSource(ForwardSource value) => $_setField(40, value);
  @$pb.TagNumber(40)
  $core.bool hasForwardSource() => $_has(9);
  @$pb.TagNumber(40)
  void clearForwardSource() => $_clearField(40);
  @$pb.TagNumber(40)
  ForwardSource ensureForwardSource() => $_ensure(9);

  /// For TYPE_TYPING. False means "stopped typing".
  @$pb.TagNumber(50)
  $core.bool get isTyping => $_getBF(10);
  @$pb.TagNumber(50)
  set isTyping($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(50)
  $core.bool hasIsTyping() => $_has(10);
  @$pb.TagNumber(50)
  void clearIsTyping() => $_clearField(50);

  /// For TYPE_READ_RECEIPT, TYPE_DELIVERY_RECEIPT. The server timestamp
  /// of the newest peer message being acknowledged. Recipients flip
  /// their OWN messages with server_timestamp_ms <= this value, so the
  /// receipt needs no message id and works for one still in transit.
  @$pb.TagNumber(60)
  $fixnum.Int64 get markerServerTimestampMs => $_getI64(11);
  @$pb.TagNumber(60)
  set markerServerTimestampMs($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(60)
  $core.bool hasMarkerServerTimestampMs() => $_has(11);
  @$pb.TagNumber(60)
  void clearMarkerServerTimestampMs() => $_clearField(60);

  /// Decision 222 (fields 70-79 are the chat track's).
  ///
  /// For TYPE_MESSAGE_CREATE: a timed message. Both phones delete it this
  /// many seconds after its server_timestamp_ms, and ignore edits,
  /// reactions and replies to it from then on. The envelope's ttl_sec
  /// carries the same value, so the server drops a copy still undelivered
  /// then. 0: not timed. SYNC_PROTOCOL §20.3.
  @$pb.TagNumber(70)
  $core.int get timerSec => $_getIZ(12);
  @$pb.TagNumber(70)
  set timerSec($core.int value) => $_setUnsignedInt32(12, value);
  @$pb.TagNumber(70)
  $core.bool hasTimerSec() => $_has(12);
  @$pb.TagNumber(70)
  void clearTimerSec() => $_clearField(70);

  /// For TYPE_MESSAGE_CREATE with content_type
  /// "application/x-vartalap-secure" (body empty): a secure message, its
  /// secret sealed on its own, as one unit so a forward copies it unchanged
  /// and a traceability hash can be taken over it: version (1), unlock (1
  /// the receiving phone's screen lock, 2 a password), a password's 16-byte
  /// salt, a 12-byte nonce, then the ChaCha20-Poly1305 ciphertext and tag.
  /// SYNC_PROTOCOL §20.4.
  @$pb.TagNumber(71)
  $core.List<$core.int> get secureBox => $_getN(13);
  @$pb.TagNumber(71)
  set secureBox($core.List<$core.int> value) => $_setBytes(13, value);
  @$pb.TagNumber(71)
  $core.bool hasSecureBox() => $_has(13);
  @$pb.TagNumber(71)
  void clearSecureBox() => $_clearField(71);

  /// The random key that opens secure_box when it unlocks with the
  /// receiving phone's screen lock; unset for a password (Argon2id of it,
  /// never sent).
  @$pb.TagNumber(72)
  $core.List<$core.int> get secureKey => $_getN(14);
  @$pb.TagNumber(72)
  set secureKey($core.List<$core.int> value) => $_setBytes(14, value);
  @$pb.TagNumber(72)
  $core.bool hasSecureKey() => $_has(14);
  @$pb.TagNumber(72)
  void clearSecureKey() => $_clearField(72);

  /// Free-form client metadata. Other clients MAY ignore unknown keys.
  /// Reserved keys:
  ///   "client_version"  — UI hint about sender's client (advisory)
  ///   "edit_reason"     — optional reason for an UPDATE
  @$pb.TagNumber(100)
  $pb.PbMap<$core.String, $core.String> get meta => $_getMap(15);

  /// Live location (SYNC_PROTOCOL.md §21, decision 223; fields 130-139).
  /// For TYPE_LIVE_LOCATION_UPDATE: the sharer's newest position.
  @$pb.TagNumber(130)
  LiveLocationPoint get liveLocationPoint => $_getN(16);
  @$pb.TagNumber(130)
  set liveLocationPoint(LiveLocationPoint value) => $_setField(130, value);
  @$pb.TagNumber(130)
  $core.bool hasLiveLocationPoint() => $_has(16);
  @$pb.TagNumber(130)
  void clearLiveLocationPoint() => $_clearField(130);
  @$pb.TagNumber(130)
  LiveLocationPoint ensureLiveLocationPoint() => $_ensure(16);

  /// For TYPE_LIVE_LOCATION_CONTROL: turn the receiver's live location in
  /// this 1:1 chat on (for `duration_sec`) or off (0).
  @$pb.TagNumber(131)
  $core.int get liveLocationDurationSec => $_getIZ(17);
  @$pb.TagNumber(131)
  set liveLocationDurationSec($core.int value) => $_setUnsignedInt32(17, value);
  @$pb.TagNumber(131)
  $core.bool hasLiveLocationDurationSec() => $_has(17);
  @$pb.TagNumber(131)
  void clearLiveLocationDurationSec() => $_clearField(131);

  /// For TYPE_LIVE_LOCATION_PERMISSION: may the receiver turn the
  /// sender's live location on and off from now on.
  @$pb.TagNumber(132)
  $core.bool get liveLocationAllowed => $_getBF(18);
  @$pb.TagNumber(132)
  set liveLocationAllowed($core.bool value) => $_setBool(18, value);
  @$pb.TagNumber(132)
  $core.bool hasLiveLocationAllowed() => $_has(18);
  @$pb.TagNumber(132)
  void clearLiveLocationAllowed() => $_clearField(132);
}

/// One position of a live location share.
class LiveLocationPoint extends $pb.GeneratedMessage {
  factory LiveLocationPoint({
    $core.double? lat,
    $core.double? lng,
    $core.int? accuracyM,
    $fixnum.Int64? atMs,
  }) {
    final result = create();
    if (lat != null) result.lat = lat;
    if (lng != null) result.lng = lng;
    if (accuracyM != null) result.accuracyM = accuracyM;
    if (atMs != null) result.atMs = atMs;
    return result;
  }

  LiveLocationPoint._();

  factory LiveLocationPoint.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LiveLocationPoint.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LiveLocationPoint',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'lat')
    ..aD(2, _omitFieldNames ? '' : 'lng')
    ..aI(3, _omitFieldNames ? '' : 'accuracyM', fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'atMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LiveLocationPoint clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LiveLocationPoint copyWith(void Function(LiveLocationPoint) updates) =>
      super.copyWith((message) => updates(message as LiveLocationPoint))
          as LiveLocationPoint;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LiveLocationPoint create() => LiveLocationPoint._();
  @$core.override
  LiveLocationPoint createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LiveLocationPoint getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LiveLocationPoint>(create);
  static LiveLocationPoint? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get lat => $_getN(0);
  @$pb.TagNumber(1)
  set lat($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLat() => $_has(0);
  @$pb.TagNumber(1)
  void clearLat() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get lng => $_getN(1);
  @$pb.TagNumber(2)
  set lng($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLng() => $_has(1);
  @$pb.TagNumber(2)
  void clearLng() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get accuracyM => $_getIZ(2);
  @$pb.TagNumber(3)
  set accuracyM($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccuracyM() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccuracyM() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get atMs => $_getI64(3);
  @$pb.TagNumber(4)
  set atMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearAtMs() => $_clearField(4);
}

class Attachment extends $pb.GeneratedMessage {
  factory Attachment({
    $core.String? url,
    $core.String? mimeType,
    $fixnum.Int64? sizeBytes,
    $core.String? sha256,
    $core.String? filename,
    $core.int? width,
    $core.int? height,
    $core.int? durationMs,
  }) {
    final result = create();
    if (url != null) result.url = url;
    if (mimeType != null) result.mimeType = mimeType;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (sha256 != null) result.sha256 = sha256;
    if (filename != null) result.filename = filename;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (durationMs != null) result.durationMs = durationMs;
    return result;
  }

  Attachment._();

  factory Attachment.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Attachment.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Attachment',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'mimeType')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'sizeBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(4, _omitFieldNames ? '' : 'sha256')
    ..aOS(5, _omitFieldNames ? '' : 'filename')
    ..aI(10, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(11, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..aI(12, _omitFieldNames ? '' : 'durationMs',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Attachment clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Attachment copyWith(void Function(Attachment) updates) =>
      super.copyWith((message) => updates(message as Attachment)) as Attachment;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Attachment create() => Attachment._();
  @$core.override
  Attachment createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Attachment getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Attachment>(create);
  static Attachment? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mimeType => $_getSZ(1);
  @$pb.TagNumber(2)
  set mimeType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMimeType() => $_has(1);
  @$pb.TagNumber(2)
  void clearMimeType() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sizeBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSizeBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearSizeBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sha256 => $_getSZ(3);
  @$pb.TagNumber(4)
  set sha256($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSha256() => $_has(3);
  @$pb.TagNumber(4)
  void clearSha256() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get filename => $_getSZ(4);
  @$pb.TagNumber(5)
  set filename($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFilename() => $_has(4);
  @$pb.TagNumber(5)
  void clearFilename() => $_clearField(5);

  @$pb.TagNumber(10)
  $core.int get width => $_getIZ(5);
  @$pb.TagNumber(10)
  set width($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(10)
  $core.bool hasWidth() => $_has(5);
  @$pb.TagNumber(10)
  void clearWidth() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get height => $_getIZ(6);
  @$pb.TagNumber(11)
  set height($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(11)
  $core.bool hasHeight() => $_has(6);
  @$pb.TagNumber(11)
  void clearHeight() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get durationMs => $_getIZ(7);
  @$pb.TagNumber(12)
  set durationMs($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(12)
  $core.bool hasDurationMs() => $_has(7);
  @$pb.TagNumber(12)
  void clearDurationMs() => $_clearField(12);
}

class ForwardSource extends $pb.GeneratedMessage {
  factory ForwardSource({
    $core.List<$core.int>? sourceChannelId,
    $core.List<$core.int>? sourceMessageId,
    $core.int? forwardCount,
  }) {
    final result = create();
    if (sourceChannelId != null) result.sourceChannelId = sourceChannelId;
    if (sourceMessageId != null) result.sourceMessageId = sourceMessageId;
    if (forwardCount != null) result.forwardCount = forwardCount;
    return result;
  }

  ForwardSource._();

  factory ForwardSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ForwardSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ForwardSource',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'vartalap.v3.payload'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'sourceChannelId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'sourceMessageId', $pb.PbFieldType.OY)
    ..aI(5, _omitFieldNames ? '' : 'forwardCount',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForwardSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForwardSource copyWith(void Function(ForwardSource) updates) =>
      super.copyWith((message) => updates(message as ForwardSource))
          as ForwardSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ForwardSource create() => ForwardSource._();
  @$core.override
  ForwardSource createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ForwardSource getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ForwardSource>(create);
  static ForwardSource? _defaultInstance;

  /// The chat and the message forwarded from, 16 bytes each. The app
  /// leaves both empty: a message id carries its author's user bits
  /// (decision 218) and a 1:1 chat id derives from the pair, so either
  /// would tell the receiver who wrote it first.
  @$pb.TagNumber(3)
  $core.List<$core.int> get sourceChannelId => $_getN(0);
  @$pb.TagNumber(3)
  set sourceChannelId($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceChannelId() => $_has(0);
  @$pb.TagNumber(3)
  void clearSourceChannelId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get sourceMessageId => $_getN(1);
  @$pb.TagNumber(4)
  set sourceMessageId($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(4)
  $core.bool hasSourceMessageId() => $_has(1);
  @$pb.TagNumber(4)
  void clearSourceMessageId() => $_clearField(4);

  /// How many forwards the content has been through, this one included:
  /// 1 when what was forwarded was not itself a forward.
  @$pb.TagNumber(5)
  $core.int get forwardCount => $_getIZ(2);
  @$pb.TagNumber(5)
  set forwardCount($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(5)
  $core.bool hasForwardCount() => $_has(2);
  @$pb.TagNumber(5)
  void clearForwardCount() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
