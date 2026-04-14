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

import 'package:protobuf/protobuf.dart' as $pb;

class AckOutcome extends $pb.ProtobufEnum {
  static const AckOutcome ACK_OUTCOME_UNSPECIFIED =
      AckOutcome._(0, _omitEnumNames ? '' : 'ACK_OUTCOME_UNSPECIFIED');
  static const AckOutcome ACK_SUCCESS =
      AckOutcome._(1, _omitEnumNames ? '' : 'ACK_SUCCESS');
  static const AckOutcome ACK_TRANSIENT =
      AckOutcome._(2, _omitEnumNames ? '' : 'ACK_TRANSIENT');
  static const AckOutcome ACK_PERMANENT =
      AckOutcome._(3, _omitEnumNames ? '' : 'ACK_PERMANENT');
  static const AckOutcome ACK_AUTH_FAILURE =
      AckOutcome._(4, _omitEnumNames ? '' : 'ACK_AUTH_FAILURE');

  static const $core.List<AckOutcome> values = <AckOutcome>[
    ACK_OUTCOME_UNSPECIFIED,
    ACK_SUCCESS,
    ACK_TRANSIENT,
    ACK_PERMANENT,
    ACK_AUTH_FAILURE,
  ];

  static final $core.List<AckOutcome?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static AckOutcome? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AckOutcome._(super.value, super.name);
}

class WsType extends $pb.ProtobufEnum {
  static const WsType WS_TYPE_UNSPECIFIED =
      WsType._(0, _omitEnumNames ? '' : 'WS_TYPE_UNSPECIFIED');
  static const WsType WS_OP = WsType._(1, _omitEnumNames ? '' : 'WS_OP');
  static const WsType WS_ACK = WsType._(2, _omitEnumNames ? '' : 'WS_ACK');
  static const WsType WS_PUSH = WsType._(3, _omitEnumNames ? '' : 'WS_PUSH');
  static const WsType WS_REAUTH_REQUIRED =
      WsType._(4, _omitEnumNames ? '' : 'WS_REAUTH_REQUIRED');
  static const WsType WS_ERROR = WsType._(5, _omitEnumNames ? '' : 'WS_ERROR');

  static const $core.List<WsType> values = <WsType>[
    WS_TYPE_UNSPECIFIED,
    WS_OP,
    WS_ACK,
    WS_PUSH,
    WS_REAUTH_REQUIRED,
    WS_ERROR,
  ];

  static final $core.List<WsType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static WsType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const WsType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
