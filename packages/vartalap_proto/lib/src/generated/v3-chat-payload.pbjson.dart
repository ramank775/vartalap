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
  ],
};

/// Descriptor for `ChatPayloadType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List chatPayloadTypeDescriptor = $convert.base64Decode(
    'Cg9DaGF0UGF5bG9hZFR5cGUSFAoQVFlQRV9VTlNQRUNJRklFRBAAEhcKE1RZUEVfTUVTU0FHRV'
    '9DUkVBVEUQARIXChNUWVBFX01FU1NBR0VfVVBEQVRFEAISFwoTVFlQRV9NRVNTQUdFX0RFTEVU'
    'RRADEhUKEVRZUEVfUkVBQ1RJT05fQUREEAQSGAoUVFlQRV9SRUFDVElPTl9SRU1PVkUQBRIYCh'
    'RUWVBFX01FU1NBR0VfRk9SV0FSRBAG');

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
    {'1': 'message_id', '3': 3, '4': 1, '5': 9, '10': 'messageId'},
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
      '3': 20,
      '4': 1,
      '5': 9,
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
    'GAMgASgJUgltZXNzYWdlSWQSEgoEYm9keRgKIAEoCVIEYm9keRIhCgxjb250ZW50X3R5cGUYCy'
    'ABKAlSC2NvbnRlbnRUeXBlEkEKC2F0dGFjaG1lbnRzGAwgAygLMh8udmFydGFsYXAudjMucGF5'
    'bG9hZC5BdHRhY2htZW50UgthdHRhY2htZW50cxItChNyZXBseV90b19tZXNzYWdlX2lkGBQgAS'
    'gJUhByZXBseVRvTWVzc2FnZUlkEhQKBWVtb2ppGB4gASgJUgVlbW9qaRJJCg5mb3J3YXJkX3Nv'
    'dXJjZRgoIAEoCzIiLnZhcnRhbGFwLnYzLnBheWxvYWQuRm9yd2FyZFNvdXJjZVINZm9yd2FyZF'
    'NvdXJjZRI+CgRtZXRhGGQgAygLMioudmFydGFsYXAudjMucGF5bG9hZC5DaGF0UGF5bG9hZC5N'
    'ZXRhRW50cnlSBG1ldGEaNwoJTWV0YUVudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbHVlGA'
    'IgASgJUgV2YWx1ZToCOAE=');

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
    {'1': 'source_channel_id', '3': 1, '4': 1, '5': 9, '10': 'sourceChannelId'},
    {'1': 'source_message_id', '3': 2, '4': 1, '5': 9, '10': 'sourceMessageId'},
  ],
};

/// Descriptor for `ForwardSource`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List forwardSourceDescriptor = $convert.base64Decode(
    'Cg1Gb3J3YXJkU291cmNlEioKEXNvdXJjZV9jaGFubmVsX2lkGAEgASgJUg9zb3VyY2VDaGFubm'
    'VsSWQSKgoRc291cmNlX21lc3NhZ2VfaWQYAiABKAlSD3NvdXJjZU1lc3NhZ2VJZA==');
