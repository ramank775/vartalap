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

import 'package:protobuf/protobuf.dart' as $pb;

class ServerEventType extends $pb.ProtobufEnum {
  static const ServerEventType SERVER_EVENT_UNSPECIFIED =
      ServerEventType._(0, _omitEnumNames ? '' : 'SERVER_EVENT_UNSPECIFIED');
  static const ServerEventType CHANNEL_CREATED =
      ServerEventType._(1, _omitEnumNames ? '' : 'CHANNEL_CREATED');
  static const ServerEventType CHANNEL_MEMBER_ADDED =
      ServerEventType._(2, _omitEnumNames ? '' : 'CHANNEL_MEMBER_ADDED');
  static const ServerEventType CHANNEL_MEMBER_REMOVED =
      ServerEventType._(3, _omitEnumNames ? '' : 'CHANNEL_MEMBER_REMOVED');
  static const ServerEventType CHANNEL_EDITED =
      ServerEventType._(4, _omitEnumNames ? '' : 'CHANNEL_EDITED');
  static const ServerEventType CHANNEL_DELETED =
      ServerEventType._(5, _omitEnumNames ? '' : 'CHANNEL_DELETED');
  static const ServerEventType PROFILE_EDITED =
      ServerEventType._(6, _omitEnumNames ? '' : 'PROFILE_EDITED');
  static const ServerEventType USERNAME_CHANGED =
      ServerEventType._(7, _omitEnumNames ? '' : 'USERNAME_CHANGED');
  static const ServerEventType MESSAGE_STATE_CHANGED =
      ServerEventType._(8, _omitEnumNames ? '' : 'MESSAGE_STATE_CHANGED');
  static const ServerEventType TYPING =
      ServerEventType._(9, _omitEnumNames ? '' : 'TYPING');

  static const $core.List<ServerEventType> values = <ServerEventType>[
    SERVER_EVENT_UNSPECIFIED,
    CHANNEL_CREATED,
    CHANNEL_MEMBER_ADDED,
    CHANNEL_MEMBER_REMOVED,
    CHANNEL_EDITED,
    CHANNEL_DELETED,
    PROFILE_EDITED,
    USERNAME_CHANGED,
    MESSAGE_STATE_CHANGED,
    TYPING,
  ];

  static final $core.List<ServerEventType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 9);
  static ServerEventType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ServerEventType._(super.value, super.name);
}

/// Receipt lifecycle a message can transition through after the author's
/// initial `sent`. Sent back to the AUTHOR only — not fanned to other
/// recipients (those see the actual message via WS_PUSH already).
///
/// Adding a new state is additive (recipients tolerate unknown enum
/// values, falling back to MESSAGE_STATE_UNSPECIFIED → no-op).
class MessageStateValue extends $pb.ProtobufEnum {
  static const MessageStateValue MESSAGE_STATE_UNSPECIFIED =
      MessageStateValue._(0, _omitEnumNames ? '' : 'MESSAGE_STATE_UNSPECIFIED');

  /// Server fanned to at least one other recipient's WS, OR the
  /// recipient drained it from the undelivered queue. Author's local
  /// tick goes single → double.
  static const MessageStateValue MESSAGE_STATE_DELIVERED =
      MessageStateValue._(1, _omitEnumNames ? '' : 'MESSAGE_STATE_DELIVERED');

  /// Recipient marked as read. Author's tick goes double → blue-double.
  static const MessageStateValue MESSAGE_STATE_READ =
      MessageStateValue._(2, _omitEnumNames ? '' : 'MESSAGE_STATE_READ');

  /// Server permanently rejected the message after the initial ACK.
  /// Reserved for moderation / quota / banned-content paths.
  static const MessageStateValue MESSAGE_STATE_REJECTED =
      MessageStateValue._(3, _omitEnumNames ? '' : 'MESSAGE_STATE_REJECTED');

  static const $core.List<MessageStateValue> values = <MessageStateValue>[
    MESSAGE_STATE_UNSPECIFIED,
    MESSAGE_STATE_DELIVERED,
    MESSAGE_STATE_READ,
    MESSAGE_STATE_REJECTED,
  ];

  static final $core.List<MessageStateValue?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static MessageStateValue? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const MessageStateValue._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
