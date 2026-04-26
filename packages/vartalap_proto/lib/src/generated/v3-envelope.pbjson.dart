// This is a generated file - do not edit.
//
// Generated from v3-envelope.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use ackOutcomeDescriptor instead')
const AckOutcome$json = {
  '1': 'AckOutcome',
  '2': [
    {'1': 'ACK_OUTCOME_UNSPECIFIED', '2': 0},
    {'1': 'ACK_SUCCESS', '2': 1},
    {'1': 'ACK_TRANSIENT', '2': 2},
    {'1': 'ACK_PERMANENT', '2': 3},
    {'1': 'ACK_AUTH_FAILURE', '2': 4},
  ],
};

/// Descriptor for `AckOutcome`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List ackOutcomeDescriptor = $convert.base64Decode(
    'CgpBY2tPdXRjb21lEhsKF0FDS19PVVRDT01FX1VOU1BFQ0lGSUVEEAASDwoLQUNLX1NVQ0NFU1'
    'MQARIRCg1BQ0tfVFJBTlNJRU5UEAISEQoNQUNLX1BFUk1BTkVOVBADEhQKEEFDS19BVVRIX0ZB'
    'SUxVUkUQBA==');

@$core.Deprecated('Use wsTypeDescriptor instead')
const WsType$json = {
  '1': 'WsType',
  '2': [
    {'1': 'WS_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'WS_OP', '2': 1},
    {'1': 'WS_ACK', '2': 2},
    {'1': 'WS_PUSH', '2': 3},
    {'1': 'WS_REAUTH_REQUIRED', '2': 4},
    {'1': 'WS_ERROR', '2': 5},
  ],
};

/// Descriptor for `WsType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List wsTypeDescriptor = $convert.base64Decode(
    'CgZXc1R5cGUSFwoTV1NfVFlQRV9VTlNQRUNJRklFRBAAEgkKBVdTX09QEAESCgoGV1NfQUNLEA'
    'ISCwoHV1NfUFVTSBADEhYKEldTX1JFQVVUSF9SRVFVSVJFRBAEEgwKCFdTX0VSUk9SEAU=');

@$core.Deprecated('Use envelopeDescriptor instead')
const Envelope$json = {
  '1': 'Envelope',
  '2': [
    {'1': 'op_id', '3': 1, '4': 1, '5': 9, '10': 'opId'},
    {'1': 'channel_id', '3': 2, '4': 1, '5': 9, '10': 'channelId'},
    {'1': 'resource_seq', '3': 3, '4': 1, '5': 4, '10': 'resourceSeq'},
    {
      '1': 'client_timestamp_ms',
      '3': 4,
      '4': 1,
      '5': 4,
      '10': 'clientTimestampMs'
    },
    {'1': 'payload', '3': 5, '4': 1, '5': 12, '10': 'payload'},
    {'1': 'ephemeral', '3': 6, '4': 1, '5': 8, '10': 'ephemeral'},
    {'1': 'sender_user_id', '3': 20, '4': 1, '5': 9, '10': 'senderUserId'},
    {
      '1': 'server_timestamp_ms',
      '3': 21,
      '4': 1,
      '5': 4,
      '10': 'serverTimestampMs'
    },
    {
      '1': 'delivery_sequence',
      '3': 22,
      '4': 1,
      '5': 4,
      '10': 'deliverySequence'
    },
  ],
};

/// Descriptor for `Envelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List envelopeDescriptor = $convert.base64Decode(
    'CghFbnZlbG9wZRITCgVvcF9pZBgBIAEoCVIEb3BJZBIdCgpjaGFubmVsX2lkGAIgASgJUgljaG'
    'FubmVsSWQSIQoMcmVzb3VyY2Vfc2VxGAMgASgEUgtyZXNvdXJjZVNlcRIuChNjbGllbnRfdGlt'
    'ZXN0YW1wX21zGAQgASgEUhFjbGllbnRUaW1lc3RhbXBNcxIYCgdwYXlsb2FkGAUgASgMUgdwYX'
    'lsb2FkEhwKCWVwaGVtZXJhbBgGIAEoCFIJZXBoZW1lcmFsEiQKDnNlbmRlcl91c2VyX2lkGBQg'
    'ASgJUgxzZW5kZXJVc2VySWQSLgoTc2VydmVyX3RpbWVzdGFtcF9tcxgVIAEoBFIRc2VydmVyVG'
    'ltZXN0YW1wTXMSKwoRZGVsaXZlcnlfc2VxdWVuY2UYFiABKARSEGRlbGl2ZXJ5U2VxdWVuY2U=');

@$core.Deprecated('Use ackDescriptor instead')
const Ack$json = {
  '1': 'Ack',
  '2': [
    {'1': 'op_id', '3': 1, '4': 1, '5': 9, '10': 'opId'},
    {
      '1': 'outcome',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.vartalap.v3.AckOutcome',
      '10': 'outcome'
    },
    {'1': 'reason', '3': 3, '4': 1, '5': 9, '10': 'reason'},
    {'1': 'retry_after_ms', '3': 4, '4': 1, '5': 4, '10': 'retryAfterMs'},
    {
      '1': 'server_timestamp_ms',
      '3': 5,
      '4': 1,
      '5': 4,
      '10': 'serverTimestampMs'
    },
    {
      '1': 'delivery_sequence',
      '3': 6,
      '4': 1,
      '5': 4,
      '10': 'deliverySequence'
    },
  ],
};

/// Descriptor for `Ack`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ackDescriptor = $convert.base64Decode(
    'CgNBY2sSEwoFb3BfaWQYASABKAlSBG9wSWQSMQoHb3V0Y29tZRgCIAEoDjIXLnZhcnRhbGFwLn'
    'YzLkFja091dGNvbWVSB291dGNvbWUSFgoGcmVhc29uGAMgASgJUgZyZWFzb24SJAoOcmV0cnlf'
    'YWZ0ZXJfbXMYBCABKARSDHJldHJ5QWZ0ZXJNcxIuChNzZXJ2ZXJfdGltZXN0YW1wX21zGAUgAS'
    'gEUhFzZXJ2ZXJUaW1lc3RhbXBNcxIrChFkZWxpdmVyeV9zZXF1ZW5jZRgGIAEoBFIQZGVsaXZl'
    'cnlTZXF1ZW5jZQ==');

@$core.Deprecated('Use wsEnvelopeDescriptor instead')
const WsEnvelope$json = {
  '1': 'WsEnvelope',
  '2': [
    {
      '1': 'type',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.vartalap.v3.WsType',
      '10': 'type'
    },
    {
      '1': 'ops',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.EnvelopeBatch',
      '9': 0,
      '10': 'ops'
    },
    {
      '1': 'acks',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.AckBatch',
      '9': 0,
      '10': 'acks'
    },
    {
      '1': 'push',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.Envelope',
      '9': 0,
      '10': 'push'
    },
    {
      '1': 'reauth_required',
      '3': 13,
      '4': 1,
      '5': 8,
      '9': 0,
      '10': 'reauthRequired'
    },
    {
      '1': 'error',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.WsError',
      '9': 0,
      '10': 'error'
    },
  ],
  '8': [
    {'1': 'body'},
  ],
};

/// Descriptor for `WsEnvelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wsEnvelopeDescriptor = $convert.base64Decode(
    'CgpXc0VudmVsb3BlEicKBHR5cGUYASABKA4yEy52YXJ0YWxhcC52My5Xc1R5cGVSBHR5cGUSLg'
    'oDb3BzGAogASgLMhoudmFydGFsYXAudjMuRW52ZWxvcGVCYXRjaEgAUgNvcHMSKwoEYWNrcxgL'
    'IAEoCzIVLnZhcnRhbGFwLnYzLkFja0JhdGNoSABSBGFja3MSKwoEcHVzaBgMIAEoCzIVLnZhcn'
    'RhbGFwLnYzLkVudmVsb3BlSABSBHB1c2gSKQoPcmVhdXRoX3JlcXVpcmVkGA0gASgISABSDnJl'
    'YXV0aFJlcXVpcmVkEiwKBWVycm9yGA4gASgLMhQudmFydGFsYXAudjMuV3NFcnJvckgAUgVlcn'
    'JvckIGCgRib2R5');

@$core.Deprecated('Use envelopeBatchDescriptor instead')
const EnvelopeBatch$json = {
  '1': 'EnvelopeBatch',
  '2': [
    {
      '1': 'envelopes',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.vartalap.v3.Envelope',
      '10': 'envelopes'
    },
  ],
};

/// Descriptor for `EnvelopeBatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List envelopeBatchDescriptor = $convert.base64Decode(
    'Cg1FbnZlbG9wZUJhdGNoEjMKCWVudmVsb3BlcxgBIAMoCzIVLnZhcnRhbGFwLnYzLkVudmVsb3'
    'BlUgllbnZlbG9wZXM=');

@$core.Deprecated('Use ackBatchDescriptor instead')
const AckBatch$json = {
  '1': 'AckBatch',
  '2': [
    {
      '1': 'acks',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.vartalap.v3.Ack',
      '10': 'acks'
    },
  ],
};

/// Descriptor for `AckBatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ackBatchDescriptor = $convert.base64Decode(
    'CghBY2tCYXRjaBIkCgRhY2tzGAEgAygLMhAudmFydGFsYXAudjMuQWNrUgRhY2tz');

@$core.Deprecated('Use wsErrorDescriptor instead')
const WsError$json = {
  '1': 'WsError',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 9, '10': 'code'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `WsError`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wsErrorDescriptor = $convert.base64Decode(
    'CgdXc0Vycm9yEhIKBGNvZGUYASABKAlSBGNvZGUSGAoHbWVzc2FnZRgCIAEoCVIHbWVzc2FnZQ'
    '==');
