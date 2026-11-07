// This is a generated file - do not edit.
//
// Generated from v3-chat-payload.proto.

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

@$core.Deprecated('Use chatPayloadTypeDescriptor instead')
const ChatPayloadType$json = {
  '1': 'ChatPayloadType',
  '2': [
    {'1': 'TYPE_UNSPECIFIED', '2': 0},
    {'1': 'TYPE_MESSAGE_CREATE', '2': 1},
    {'1': 'TYPE_MESSAGE_UPDATE', '2': 2},
    {'1': 'TYPE_MESSAGE_DELETE', '2': 3},
    {'1': 'TYPE_REACTION_ADD', '2': 4},
    {'1': 'TYPE_REACTION_REMOVE', '2': 5},
    {'1': 'TYPE_MESSAGE_FORWARD', '2': 6},
    {'1': 'TYPE_READ_RECEIPT', '2': 7},
    {'1': 'TYPE_TYPING', '2': 8},
    {'1': 'TYPE_DELIVERY_RECEIPT', '2': 9},
    {'1': 'TYPE_LIVE_LOCATION_UPDATE', '2': 40},
    {'1': 'TYPE_LIVE_LOCATION_STOP', '2': 41},
    {'1': 'TYPE_LIVE_LOCATION_CONTROL', '2': 42},
    {'1': 'TYPE_LIVE_LOCATION_PERMISSION', '2': 43},
  ],
};

/// Descriptor for `ChatPayloadType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List chatPayloadTypeDescriptor = $convert.base64Decode(
    'Cg9DaGF0UGF5bG9hZFR5cGUSFAoQVFlQRV9VTlNQRUNJRklFRBAAEhcKE1RZUEVfTUVTU0FHRV'
    '9DUkVBVEUQARIXChNUWVBFX01FU1NBR0VfVVBEQVRFEAISFwoTVFlQRV9NRVNTQUdFX0RFTEVU'
    'RRADEhUKEVRZUEVfUkVBQ1RJT05fQUREEAQSGAoUVFlQRV9SRUFDVElPTl9SRU1PVkUQBRIYCh'
    'RUWVBFX01FU1NBR0VfRk9SV0FSRBAGEhUKEVRZUEVfUkVBRF9SRUNFSVBUEAcSDwoLVFlQRV9U'
    'WVBJTkcQCBIZChVUWVBFX0RFTElWRVJZX1JFQ0VJUFQQCRIdChlUWVBFX0xJVkVfTE9DQVRJT0'
    '5fVVBEQVRFECgSGwoXVFlQRV9MSVZFX0xPQ0FUSU9OX1NUT1AQKRIeChpUWVBFX0xJVkVfTE9D'
    'QVRJT05fQ09OVFJPTBAqEiEKHVRZUEVfTElWRV9MT0NBVElPTl9QRVJNSVNTSU9OECs=');

@$core.Deprecated('Use chatPayloadDescriptor instead')
const ChatPayload$json = {
  '1': 'ChatPayload',
  '2': [
    {'1': 'version', '3': 1, '4': 1, '5': 13, '10': 'version'},
    {
      '1': 'type',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.vartalap.v3.payload.ChatPayloadType',
      '10': 'type'
    },
    {'1': 'message_id', '3': 4, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'group_id', '3': 5, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'body', '3': 10, '4': 1, '5': 9, '10': 'body'},
    {'1': 'content_type', '3': 11, '4': 1, '5': 9, '10': 'contentType'},
    {
      '1': 'attachments',
      '3': 12,
      '4': 3,
      '5': 11,
      '6': '.vartalap.v3.payload.Attachment',
      '10': 'attachments'
    },
    {
      '1': 'reply_to_message_id',
      '3': 21,
      '4': 1,
      '5': 12,
      '10': 'replyToMessageId'
    },
    {'1': 'emoji', '3': 30, '4': 1, '5': 9, '10': 'emoji'},
    {
      '1': 'forward_source',
      '3': 40,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.payload.ForwardSource',
      '10': 'forwardSource'
    },
    {'1': 'is_typing', '3': 50, '4': 1, '5': 8, '10': 'isTyping'},
    {
      '1': 'marker_server_timestamp_ms',
      '3': 60,
      '4': 1,
      '5': 4,
      '10': 'markerServerTimestampMs'
    },
    {'1': 'timer_sec', '3': 70, '4': 1, '5': 13, '10': 'timerSec'},
    {'1': 'secure_box', '3': 71, '4': 1, '5': 12, '10': 'secureBox'},
    {'1': 'secure_key', '3': 72, '4': 1, '5': 12, '10': 'secureKey'},
    {
      '1': 'live_location_point',
      '3': 130,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.payload.LiveLocationPoint',
      '10': 'liveLocationPoint'
    },
    {
      '1': 'live_location_duration_sec',
      '3': 131,
      '4': 1,
      '5': 13,
      '10': 'liveLocationDurationSec'
    },
    {
      '1': 'live_location_allowed',
      '3': 132,
      '4': 1,
      '5': 8,
      '10': 'liveLocationAllowed'
    },
    {
      '1': 'meta',
      '3': 100,
      '4': 3,
      '5': 11,
      '6': '.vartalap.v3.payload.ChatPayload.MetaEntry',
      '10': 'meta'
    },
  ],
  '3': [ChatPayload_MetaEntry$json],
  '9': [
    {'1': 3, '2': 4},
    {'1': 20, '2': 21},
  ],
};

@$core.Deprecated('Use chatPayloadDescriptor instead')
const ChatPayload_MetaEntry$json = {
  '1': 'MetaEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ChatPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatPayloadDescriptor = $convert.base64Decode(
    'CgtDaGF0UGF5bG9hZBIYCgd2ZXJzaW9uGAEgASgNUgd2ZXJzaW9uEjgKBHR5cGUYAiABKA4yJC'
    '52YXJ0YWxhcC52My5wYXlsb2FkLkNoYXRQYXlsb2FkVHlwZVIEdHlwZRIdCgptZXNzYWdlX2lk'
    'GAQgASgMUgltZXNzYWdlSWQSGQoIZ3JvdXBfaWQYBSABKAxSB2dyb3VwSWQSEgoEYm9keRgKIA'
    'EoCVIEYm9keRIhCgxjb250ZW50X3R5cGUYCyABKAlSC2NvbnRlbnRUeXBlEkEKC2F0dGFjaG1l'
    'bnRzGAwgAygLMh8udmFydGFsYXAudjMucGF5bG9hZC5BdHRhY2htZW50UgthdHRhY2htZW50cx'
    'ItChNyZXBseV90b19tZXNzYWdlX2lkGBUgASgMUhByZXBseVRvTWVzc2FnZUlkEhQKBWVtb2pp'
    'GB4gASgJUgVlbW9qaRJJCg5mb3J3YXJkX3NvdXJjZRgoIAEoCzIiLnZhcnRhbGFwLnYzLnBheW'
    'xvYWQuRm9yd2FyZFNvdXJjZVINZm9yd2FyZFNvdXJjZRIbCglpc190eXBpbmcYMiABKAhSCGlz'
    'VHlwaW5nEjsKGm1hcmtlcl9zZXJ2ZXJfdGltZXN0YW1wX21zGDwgASgEUhdtYXJrZXJTZXJ2ZX'
    'JUaW1lc3RhbXBNcxIbCgl0aW1lcl9zZWMYRiABKA1SCHRpbWVyU2VjEh0KCnNlY3VyZV9ib3gY'
    'RyABKAxSCXNlY3VyZUJveBIdCgpzZWN1cmVfa2V5GEggASgMUglzZWN1cmVLZXkSVwoTbGl2ZV'
    '9sb2NhdGlvbl9wb2ludBiCASABKAsyJi52YXJ0YWxhcC52My5wYXlsb2FkLkxpdmVMb2NhdGlv'
    'blBvaW50UhFsaXZlTG9jYXRpb25Qb2ludBI8ChpsaXZlX2xvY2F0aW9uX2R1cmF0aW9uX3NlYx'
    'iDASABKA1SF2xpdmVMb2NhdGlvbkR1cmF0aW9uU2VjEjMKFWxpdmVfbG9jYXRpb25fYWxsb3dl'
    'ZBiEASABKAhSE2xpdmVMb2NhdGlvbkFsbG93ZWQSPgoEbWV0YRhkIAMoCzIqLnZhcnRhbGFwLn'
    'YzLnBheWxvYWQuQ2hhdFBheWxvYWQuTWV0YUVudHJ5UgRtZXRhGjcKCU1ldGFFbnRyeRIQCgNr'
    'ZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEoCVIFdmFsdWU6AjgBSgQIAxAESgQIFBAV');

@$core.Deprecated('Use liveLocationPointDescriptor instead')
const LiveLocationPoint$json = {
  '1': 'LiveLocationPoint',
  '2': [
    {'1': 'lat', '3': 1, '4': 1, '5': 1, '10': 'lat'},
    {'1': 'lng', '3': 2, '4': 1, '5': 1, '10': 'lng'},
    {'1': 'accuracy_m', '3': 3, '4': 1, '5': 13, '10': 'accuracyM'},
    {'1': 'at_ms', '3': 4, '4': 1, '5': 4, '10': 'atMs'},
  ],
};

/// Descriptor for `LiveLocationPoint`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List liveLocationPointDescriptor = $convert.base64Decode(
    'ChFMaXZlTG9jYXRpb25Qb2ludBIQCgNsYXQYASABKAFSA2xhdBIQCgNsbmcYAiABKAFSA2xuZx'
    'IdCgphY2N1cmFjeV9tGAMgASgNUglhY2N1cmFjeU0SEwoFYXRfbXMYBCABKARSBGF0TXM=');

@$core.Deprecated('Use attachmentDescriptor instead')
const Attachment$json = {
  '1': 'Attachment',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    {'1': 'mime_type', '3': 2, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'size_bytes', '3': 3, '4': 1, '5': 4, '10': 'sizeBytes'},
    {'1': 'sha256', '3': 4, '4': 1, '5': 9, '10': 'sha256'},
    {'1': 'filename', '3': 5, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'width', '3': 10, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 11, '4': 1, '5': 13, '10': 'height'},
    {'1': 'duration_ms', '3': 12, '4': 1, '5': 13, '10': 'durationMs'},
  ],
};

/// Descriptor for `Attachment`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List attachmentDescriptor = $convert.base64Decode(
    'CgpBdHRhY2htZW50EhAKA3VybBgBIAEoCVIDdXJsEhsKCW1pbWVfdHlwZRgCIAEoCVIIbWltZV'
    'R5cGUSHQoKc2l6ZV9ieXRlcxgDIAEoBFIJc2l6ZUJ5dGVzEhYKBnNoYTI1NhgEIAEoCVIGc2hh'
    'MjU2EhoKCGZpbGVuYW1lGAUgASgJUghmaWxlbmFtZRIUCgV3aWR0aBgKIAEoDVIFd2lkdGgSFg'
    'oGaGVpZ2h0GAsgASgNUgZoZWlnaHQSHwoLZHVyYXRpb25fbXMYDCABKA1SCmR1cmF0aW9uTXM=');

@$core.Deprecated('Use forwardSourceDescriptor instead')
const ForwardSource$json = {
  '1': 'ForwardSource',
  '2': [
    {
      '1': 'source_channel_id',
      '3': 3,
      '4': 1,
      '5': 12,
      '10': 'sourceChannelId'
    },
    {
      '1': 'source_message_id',
      '3': 4,
      '4': 1,
      '5': 12,
      '10': 'sourceMessageId'
    },
    {'1': 'forward_count', '3': 5, '4': 1, '5': 13, '10': 'forwardCount'},
  ],
  '9': [
    {'1': 1, '2': 2},
    {'1': 2, '2': 3},
  ],
};

/// Descriptor for `ForwardSource`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List forwardSourceDescriptor = $convert.base64Decode(
    'Cg1Gb3J3YXJkU291cmNlEioKEXNvdXJjZV9jaGFubmVsX2lkGAMgASgMUg9zb3VyY2VDaGFubm'
    'VsSWQSKgoRc291cmNlX21lc3NhZ2VfaWQYBCABKAxSD3NvdXJjZU1lc3NhZ2VJZBIjCg1mb3J3'
    'YXJkX2NvdW50GAUgASgNUgxmb3J3YXJkQ291bnRKBAgBEAJKBAgCEAM=');
