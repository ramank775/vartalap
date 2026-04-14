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
    $core.String? messageId,
    $core.String? body,
    $core.String? contentType,
    $core.Iterable<Attachment>? attachments,
    $core.String? replyToMessageId,
    $core.String? emoji,
    ForwardSource? forwardSource,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? meta,
  }) {
    final result = create();
    if (version != null) result.version = version;
    if (type != null) result.type = type;
    if (messageId != null) result.messageId = messageId;
    if (body != null) result.body = body;
    if (contentType != null) result.contentType = contentType;
    if (attachments != null) result.attachments.addAll(attachments);
    if (replyToMessageId != null) result.replyToMessageId = replyToMessageId;
    if (emoji != null) result.emoji = emoji;
    if (forwardSource != null) result.forwardSource = forwardSource;
    if (meta != null) result.meta.addEntries(meta);
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
    ..aOS(3, _omitFieldNames ? '' : 'messageId')
    ..aOS(10, _omitFieldNames ? '' : 'body')
    ..aOS(11, _omitFieldNames ? '' : 'contentType')
    ..pPM<Attachment>(12, _omitFieldNames ? '' : 'attachments',
        subBuilder: Attachment.create)
    ..aOS(20, _omitFieldNames ? '' : 'replyToMessageId')
    ..aOS(30, _omitFieldNames ? '' : 'emoji')
    ..aOM<ForwardSource>(40, _omitFieldNames ? '' : 'forwardSource',
        subBuilder: ForwardSource.create)
    ..m<$core.String, $core.String>(100, _omitFieldNames ? '' : 'meta',
        entryClassName: 'ChatPayload.MetaEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('vartalap.v3.payload'))
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

  /// The message this payload acts on. For TYPE_MESSAGE_CREATE and
  /// TYPE_MESSAGE_FORWARD, this is the new message's id (client-
  /// generated UUIDv7). For UPDATE / DELETE / REACTION_*, this is
  /// the existing message being targeted.
  @$pb.TagNumber(3)
  $core.String get messageId => $_getSZ(2);
  @$pb.TagNumber(3)
  set messageId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMessageId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessageId() => $_clearField(3);

  /// For TYPE_MESSAGE_CREATE, TYPE_MESSAGE_UPDATE, TYPE_MESSAGE_FORWARD.
  @$pb.TagNumber(10)
  $core.String get body => $_getSZ(3);
  @$pb.TagNumber(10)
  set body($core.String value) => $_setString(3, value);
  @$pb.TagNumber(10)
  $core.bool hasBody() => $_has(3);
  @$pb.TagNumber(10)
  void clearBody() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get contentType => $_getSZ(4);
  @$pb.TagNumber(11)
  set contentType($core.String value) => $_setString(4, value);
  @$pb.TagNumber(11)
  $core.bool hasContentType() => $_has(4);
  @$pb.TagNumber(11)
  void clearContentType() => $_clearField(11);

  @$pb.TagNumber(12)
  $pb.PbList<Attachment> get attachments => $_getList(5);

  /// For TYPE_MESSAGE_CREATE, TYPE_MESSAGE_FORWARD.
  @$pb.TagNumber(20)
  $core.String get replyToMessageId => $_getSZ(6);
  @$pb.TagNumber(20)
  set replyToMessageId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(20)
  $core.bool hasReplyToMessageId() => $_has(6);
  @$pb.TagNumber(20)
  void clearReplyToMessageId() => $_clearField(20);

  /// For TYPE_REACTION_ADD, TYPE_REACTION_REMOVE.
  @$pb.TagNumber(30)
  $core.String get emoji => $_getSZ(7);
  @$pb.TagNumber(30)
  set emoji($core.String value) => $_setString(7, value);
  @$pb.TagNumber(30)
  $core.bool hasEmoji() => $_has(7);
  @$pb.TagNumber(30)
  void clearEmoji() => $_clearField(30);

  /// For TYPE_MESSAGE_FORWARD.
  @$pb.TagNumber(40)
  ForwardSource get forwardSource => $_getN(8);
  @$pb.TagNumber(40)
  set forwardSource(ForwardSource value) => $_setField(40, value);
  @$pb.TagNumber(40)
  $core.bool hasForwardSource() => $_has(8);
  @$pb.TagNumber(40)
  void clearForwardSource() => $_clearField(40);
  @$pb.TagNumber(40)
  ForwardSource ensureForwardSource() => $_ensure(8);

  /// Free-form client metadata. Other clients MAY ignore unknown keys.
  /// Reserved keys:
  ///   "client_version"  — UI hint about sender's client (advisory)
  ///   "edit_reason"     — optional reason for an UPDATE
  @$pb.TagNumber(100)
  $pb.PbMap<$core.String, $core.String> get meta => $_getMap(9);
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
    $core.String? sourceChannelId,
    $core.String? sourceMessageId,
  }) {
    final result = create();
    if (sourceChannelId != null) result.sourceChannelId = sourceChannelId;
    if (sourceMessageId != null) result.sourceMessageId = sourceMessageId;
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
    ..aOS(1, _omitFieldNames ? '' : 'sourceChannelId')
    ..aOS(2, _omitFieldNames ? '' : 'sourceMessageId')
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

  @$pb.TagNumber(1)
  $core.String get sourceChannelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sourceChannelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSourceChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSourceChannelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sourceMessageId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourceMessageId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSourceMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourceMessageId() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
