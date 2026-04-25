// This is a generated file - do not edit.
//
// Generated from v3-server-event-payload.proto.

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

@$core.Deprecated('Use serverEventTypeDescriptor instead')
const ServerEventType$json = {
  '1': 'ServerEventType',
  '2': [
    {'1': 'SERVER_EVENT_UNSPECIFIED', '2': 0},
    {'1': 'CHANNEL_CREATED', '2': 1},
    {'1': 'CHANNEL_MEMBER_ADDED', '2': 2},
    {'1': 'CHANNEL_MEMBER_REMOVED', '2': 3},
    {'1': 'CHANNEL_EDITED', '2': 4},
    {'1': 'CHANNEL_DELETED', '2': 5},
    {'1': 'PROFILE_EDITED', '2': 6},
    {'1': 'USERNAME_CHANGED', '2': 7},
  ],
};

/// Descriptor for `ServerEventType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List serverEventTypeDescriptor = $convert.base64Decode(
    'Cg9TZXJ2ZXJFdmVudFR5cGUSHAoYU0VSVkVSX0VWRU5UX1VOU1BFQ0lGSUVEEAASEwoPQ0hBTk'
    '5FTF9DUkVBVEVEEAESGAoUQ0hBTk5FTF9NRU1CRVJfQURERUQQAhIaChZDSEFOTkVMX01FTUJF'
    'Ul9SRU1PVkVEEAMSEgoOQ0hBTk5FTF9FRElURUQQBBITCg9DSEFOTkVMX0RFTEVURUQQBRISCg'
    '5QUk9GSUxFX0VESVRFRBAGEhQKEFVTRVJOQU1FX0NIQU5HRUQQBw==');

@$core.Deprecated('Use serverEventPayloadDescriptor instead')
const ServerEventPayload$json = {
  '1': 'ServerEventPayload',
  '2': [
    {'1': 'version', '3': 1, '4': 1, '5': 13, '10': 'version'},
    {
      '1': 'type',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.vartalap.v3.payload.ServerEventType',
      '10': 'type'
    },
    {
      '1': 'channel_created',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.payload.ChannelCreated',
      '9': 0,
      '10': 'channelCreated'
    },
    {
      '1': 'member_added',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.payload.ChannelMemberAdded',
      '9': 0,
      '10': 'memberAdded'
    },
    {
      '1': 'member_removed',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.payload.ChannelMemberRemoved',
      '9': 0,
      '10': 'memberRemoved'
    },
    {
      '1': 'channel_edited',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.payload.ChannelEdited',
      '9': 0,
      '10': 'channelEdited'
    },
    {
      '1': 'channel_deleted',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.payload.ChannelDeleted',
      '9': 0,
      '10': 'channelDeleted'
    },
    {
      '1': 'profile_edited',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.payload.ProfileEdited',
      '9': 0,
      '10': 'profileEdited'
    },
    {
      '1': 'username_changed',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.vartalap.v3.payload.UsernameChanged',
      '9': 0,
      '10': 'usernameChanged'
    },
  ],
  '8': [
    {'1': 'body'},
  ],
};

/// Descriptor for `ServerEventPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverEventPayloadDescriptor = $convert.base64Decode(
    'ChJTZXJ2ZXJFdmVudFBheWxvYWQSGAoHdmVyc2lvbhgBIAEoDVIHdmVyc2lvbhI4CgR0eXBlGA'
    'IgASgOMiQudmFydGFsYXAudjMucGF5bG9hZC5TZXJ2ZXJFdmVudFR5cGVSBHR5cGUSTgoPY2hh'
    'bm5lbF9jcmVhdGVkGAogASgLMiMudmFydGFsYXAudjMucGF5bG9hZC5DaGFubmVsQ3JlYXRlZE'
    'gAUg5jaGFubmVsQ3JlYXRlZBJMCgxtZW1iZXJfYWRkZWQYCyABKAsyJy52YXJ0YWxhcC52My5w'
    'YXlsb2FkLkNoYW5uZWxNZW1iZXJBZGRlZEgAUgttZW1iZXJBZGRlZBJSCg5tZW1iZXJfcmVtb3'
    'ZlZBgMIAEoCzIpLnZhcnRhbGFwLnYzLnBheWxvYWQuQ2hhbm5lbE1lbWJlclJlbW92ZWRIAFIN'
    'bWVtYmVyUmVtb3ZlZBJLCg5jaGFubmVsX2VkaXRlZBgNIAEoCzIiLnZhcnRhbGFwLnYzLnBheW'
    'xvYWQuQ2hhbm5lbEVkaXRlZEgAUg1jaGFubmVsRWRpdGVkEk4KD2NoYW5uZWxfZGVsZXRlZBgO'
    'IAEoCzIjLnZhcnRhbGFwLnYzLnBheWxvYWQuQ2hhbm5lbERlbGV0ZWRIAFIOY2hhbm5lbERlbG'
    'V0ZWQSSwoOcHJvZmlsZV9lZGl0ZWQYDyABKAsyIi52YXJ0YWxhcC52My5wYXlsb2FkLlByb2Zp'
    'bGVFZGl0ZWRIAFINcHJvZmlsZUVkaXRlZBJRChB1c2VybmFtZV9jaGFuZ2VkGBAgASgLMiQudm'
    'FydGFsYXAudjMucGF5bG9hZC5Vc2VybmFtZUNoYW5nZWRIAFIPdXNlcm5hbWVDaGFuZ2VkQgYK'
    'BGJvZHk=');

@$core.Deprecated('Use channelCreatedDescriptor instead')
const ChannelCreated$json = {
  '1': 'ChannelCreated',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 9, '10': 'channelId'},
    {'1': 'kind', '3': 2, '4': 1, '5': 9, '10': 'kind'},
    {'1': 'name', '3': 3, '4': 1, '5': 9, '10': 'name'},
    {'1': 'members', '3': 4, '4': 3, '5': 9, '10': 'members'},
    {'1': 'creator', '3': 5, '4': 1, '5': 9, '10': 'creator'},
    {'1': 'created_at_ms', '3': 6, '4': 1, '5': 3, '10': 'createdAtMs'},
  ],
};

/// Descriptor for `ChannelCreated`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelCreatedDescriptor = $convert.base64Decode(
    'Cg5DaGFubmVsQ3JlYXRlZBIdCgpjaGFubmVsX2lkGAEgASgJUgljaGFubmVsSWQSEgoEa2luZB'
    'gCIAEoCVIEa2luZBISCgRuYW1lGAMgASgJUgRuYW1lEhgKB21lbWJlcnMYBCADKAlSB21lbWJl'
    'cnMSGAoHY3JlYXRvchgFIAEoCVIHY3JlYXRvchIiCg1jcmVhdGVkX2F0X21zGAYgASgDUgtjcm'
    'VhdGVkQXRNcw==');

@$core.Deprecated('Use channelMemberAddedDescriptor instead')
const ChannelMemberAdded$json = {
  '1': 'ChannelMemberAdded',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 9, '10': 'channelId'},
    {'1': 'members', '3': 2, '4': 3, '5': 9, '10': 'members'},
    {'1': 'added_at_ms', '3': 3, '4': 1, '5': 3, '10': 'addedAtMs'},
  ],
};

/// Descriptor for `ChannelMemberAdded`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelMemberAddedDescriptor = $convert.base64Decode(
    'ChJDaGFubmVsTWVtYmVyQWRkZWQSHQoKY2hhbm5lbF9pZBgBIAEoCVIJY2hhbm5lbElkEhgKB2'
    '1lbWJlcnMYAiADKAlSB21lbWJlcnMSHgoLYWRkZWRfYXRfbXMYAyABKANSCWFkZGVkQXRNcw==');

@$core.Deprecated('Use channelMemberRemovedDescriptor instead')
const ChannelMemberRemoved$json = {
  '1': 'ChannelMemberRemoved',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 9, '10': 'channelId'},
    {'1': 'member', '3': 2, '4': 1, '5': 9, '10': 'member'},
    {'1': 'removed_at_ms', '3': 3, '4': 1, '5': 3, '10': 'removedAtMs'},
  ],
};

/// Descriptor for `ChannelMemberRemoved`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelMemberRemovedDescriptor = $convert.base64Decode(
    'ChRDaGFubmVsTWVtYmVyUmVtb3ZlZBIdCgpjaGFubmVsX2lkGAEgASgJUgljaGFubmVsSWQSFg'
    'oGbWVtYmVyGAIgASgJUgZtZW1iZXISIgoNcmVtb3ZlZF9hdF9tcxgDIAEoA1ILcmVtb3ZlZEF0'
    'TXM=');

@$core.Deprecated('Use channelEditedDescriptor instead')
const ChannelEdited$json = {
  '1': 'ChannelEdited',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 9, '10': 'channelId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'name', '17': true},
    {
      '1': 'avatar_url',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'avatarUrl',
      '17': true
    },
    {'1': 'edited_at_ms', '3': 4, '4': 1, '5': 3, '10': 'editedAtMs'},
  ],
  '8': [
    {'1': '_name'},
    {'1': '_avatar_url'},
  ],
};

/// Descriptor for `ChannelEdited`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelEditedDescriptor = $convert.base64Decode(
    'Cg1DaGFubmVsRWRpdGVkEh0KCmNoYW5uZWxfaWQYASABKAlSCWNoYW5uZWxJZBIXCgRuYW1lGA'
    'IgASgJSABSBG5hbWWIAQESIgoKYXZhdGFyX3VybBgDIAEoCUgBUglhdmF0YXJVcmyIAQESIAoM'
    'ZWRpdGVkX2F0X21zGAQgASgDUgplZGl0ZWRBdE1zQgcKBV9uYW1lQg0KC19hdmF0YXJfdXJs');

@$core.Deprecated('Use channelDeletedDescriptor instead')
const ChannelDeleted$json = {
  '1': 'ChannelDeleted',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 9, '10': 'channelId'},
    {'1': 'deleted_at_ms', '3': 2, '4': 1, '5': 3, '10': 'deletedAtMs'},
  ],
};

/// Descriptor for `ChannelDeleted`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelDeletedDescriptor = $convert.base64Decode(
    'Cg5DaGFubmVsRGVsZXRlZBIdCgpjaGFubmVsX2lkGAEgASgJUgljaGFubmVsSWQSIgoNZGVsZX'
    'RlZF9hdF9tcxgCIAEoA1ILZGVsZXRlZEF0TXM=');

@$core.Deprecated('Use profileEditedDescriptor instead')
const ProfileEdited$json = {
  '1': 'ProfileEdited',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {
      '1': 'display_name',
      '3': 2,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'displayName',
      '17': true
    },
    {
      '1': 'avatar_url',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'avatarUrl',
      '17': true
    },
    {
      '1': 'status_text',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 2,
      '10': 'statusText',
      '17': true
    },
    {'1': 'edited_at_ms', '3': 5, '4': 1, '5': 3, '10': 'editedAtMs'},
  ],
  '8': [
    {'1': '_display_name'},
    {'1': '_avatar_url'},
    {'1': '_status_text'},
  ],
};

/// Descriptor for `ProfileEdited`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List profileEditedDescriptor = $convert.base64Decode(
    'Cg1Qcm9maWxlRWRpdGVkEhcKB3VzZXJfaWQYASABKAlSBnVzZXJJZBImCgxkaXNwbGF5X25hbW'
    'UYAiABKAlIAFILZGlzcGxheU5hbWWIAQESIgoKYXZhdGFyX3VybBgDIAEoCUgBUglhdmF0YXJV'
    'cmyIAQESJAoLc3RhdHVzX3RleHQYBCABKAlIAlIKc3RhdHVzVGV4dIgBARIgCgxlZGl0ZWRfYX'
    'RfbXMYBSABKANSCmVkaXRlZEF0TXNCDwoNX2Rpc3BsYXlfbmFtZUINCgtfYXZhdGFyX3VybEIO'
    'Cgxfc3RhdHVzX3RleHQ=');

@$core.Deprecated('Use usernameChangedDescriptor instead')
const UsernameChanged$json = {
  '1': 'UsernameChanged',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'new_username', '3': 2, '4': 1, '5': 9, '10': 'newUsername'},
    {'1': 'changed_at_ms', '3': 3, '4': 1, '5': 3, '10': 'changedAtMs'},
  ],
};

/// Descriptor for `UsernameChanged`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List usernameChangedDescriptor = $convert.base64Decode(
    'Cg9Vc2VybmFtZUNoYW5nZWQSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklkEiEKDG5ld191c2Vybm'
    'FtZRgCIAEoCVILbmV3VXNlcm5hbWUSIgoNY2hhbmdlZF9hdF9tcxgDIAEoA1ILY2hhbmdlZEF0'
    'TXM=');
