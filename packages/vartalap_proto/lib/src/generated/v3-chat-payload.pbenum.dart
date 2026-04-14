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

import 'package:protobuf/protobuf.dart' as $pb;

class ChatPayloadType extends $pb.ProtobufEnum {
  static const ChatPayloadType TYPE_UNSPECIFIED =
      ChatPayloadType._(0, _omitEnumNames ? '' : 'TYPE_UNSPECIFIED');

  /// A new message in the channel.
  static const ChatPayloadType TYPE_MESSAGE_CREATE =
      ChatPayloadType._(1, _omitEnumNames ? '' : 'TYPE_MESSAGE_CREATE');

  /// Replace the body / content_type / attachments of an existing
  /// message. Recipient enforces "sender is the original author"
  /// (per SYNC_PROTOCOL.md §6a.3); silently dropped otherwise.
  static const ChatPayloadType TYPE_MESSAGE_UPDATE =
      ChatPayloadType._(2, _omitEnumNames ? '' : 'TYPE_MESSAGE_UPDATE');

  /// Tombstone an existing message. Recipient enforces author check;
  /// silently dropped otherwise.
  static const ChatPayloadType TYPE_MESSAGE_DELETE =
      ChatPayloadType._(3, _omitEnumNames ? '' : 'TYPE_MESSAGE_DELETE');

  /// Add the named emoji as a reaction from the sender on the target
  /// message. Idempotent — duplicate adds are no-ops on recipients.
  static const ChatPayloadType TYPE_REACTION_ADD =
      ChatPayloadType._(4, _omitEnumNames ? '' : 'TYPE_REACTION_ADD');

  /// Remove the named emoji reaction from the sender on the target
  /// message. Idempotent — removes for non-existent reactions are
  /// no-ops on recipients.
  static const ChatPayloadType TYPE_REACTION_REMOVE =
      ChatPayloadType._(5, _omitEnumNames ? '' : 'TYPE_REACTION_REMOVE');

  /// Forward an existing message into this channel as a new message.
  /// Identical to TYPE_MESSAGE_CREATE plus `forward_source` metadata
  /// for recipient UI ("Forwarded from …").
  static const ChatPayloadType TYPE_MESSAGE_FORWARD =
      ChatPayloadType._(6, _omitEnumNames ? '' : 'TYPE_MESSAGE_FORWARD');

  static const $core.List<ChatPayloadType> values = <ChatPayloadType>[
    TYPE_UNSPECIFIED,
    TYPE_MESSAGE_CREATE,
    TYPE_MESSAGE_UPDATE,
    TYPE_MESSAGE_DELETE,
    TYPE_REACTION_ADD,
    TYPE_REACTION_REMOVE,
    TYPE_MESSAGE_FORWARD,
  ];

  static final $core.List<ChatPayloadType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static ChatPayloadType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ChatPayloadType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
