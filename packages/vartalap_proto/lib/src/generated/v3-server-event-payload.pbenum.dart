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

  static const $core.List<ServerEventType> values = <ServerEventType>[
    SERVER_EVENT_UNSPECIFIED,
    CHANNEL_CREATED,
    CHANNEL_MEMBER_ADDED,
    CHANNEL_MEMBER_REMOVED,
    CHANNEL_EDITED,
    CHANNEL_DELETED,
    PROFILE_EDITED,
    USERNAME_CHANGED,
  ];

  static final $core.List<ServerEventType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static ServerEventType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ServerEventType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
