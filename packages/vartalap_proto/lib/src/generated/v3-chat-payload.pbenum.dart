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

  /// Forward an existing message into this channel as a new message
  /// (SYNC_PROTOCOL.md §25). Identical to TYPE_MESSAGE_CREATE plus
  /// `forward_source`, which recipients show as "Forwarded" (from 5
  /// forwards "Forwarded many times"); never who wrote it first. The
  /// content travels unchanged: attachments keep their url (the fileId
  /// is the capability, nothing is uploaded again), a secure message its
  /// `secure_box` and `secure_key` byte for byte (decision 222). No
  /// `reply_to_message_id`, no `timer_sec`.
  static const ChatPayloadType TYPE_MESSAGE_FORWARD =
      ChatPayloadType._(6, _omitEnumNames ? '' : 'TYPE_MESSAGE_FORWARD');

  /// Sender has read this channel up to and including the message
  /// stamped `marker_server_timestamp_ms`. Recipients flip their OWN
  /// authored messages at or before that marker to "read" — authorship
  /// gating per SYNC_PROTOCOL.md §6a.3 means a receipt never touches a
  /// third party's rows. In a group it goes to each author over 1:1
  /// with `group_id` set. Rides a normal (non-ephemeral) WS op, so it
  /// is ACKed like any other.
  static const ChatPayloadType TYPE_READ_RECEIPT =
      ChatPayloadType._(7, _omitEnumNames ? '' : 'TYPE_READ_RECEIPT');

  /// Ephemeral "is typing" signal. MUST ride an envelope with
  /// `ephemeral = true` (v3-envelope.proto): no ACK, no persistence,
  /// lossy by design. `is_typing` carries the state.
  static const ChatPayloadType TYPE_TYPING =
      ChatPayloadType._(8, _omitEnumNames ? '' : 'TYPE_TYPING');

  /// Sender's device has stored this channel's messages up to and
  /// including the one stamped `marker_server_timestamp_ms`.
  /// Recipients flip their OWN authored messages at or before that
  /// marker to "delivered" (grey double tick), never back from
  /// "read". Same authorship gating and transport as
  /// TYPE_READ_RECEIPT; sent once per burst of inbound
  /// messages per channel, not once per message, and skipped when a
  /// read receipt covering it goes out first. In a group, as with read,
  /// it goes to each author over 1:1 and a message flips once every
  /// member is past it (decision 202).
  static const ChatPayloadType TYPE_DELIVERY_RECEIPT =
      ChatPayloadType._(9, _omitEnumNames ? '' : 'TYPE_DELIVERY_RECEIPT');

  /// The sender's answer to an event message (decision 134, SYNC_PROTOCOL.md
  /// §25.3): `message_id` the event, `event_rsvp` the answer. Anyone in
  /// the chat may answer; their newest answer (by server time) counts.
  /// Class MUTATION, SILENT, like a reaction.
  static const ChatPayloadType TYPE_EVENT_RSVP =
      ChatPayloadType._(15, _omitEnumNames ? '' : 'TYPE_EVENT_RSVP');

  /// Live location (SYNC_PROTOCOL.md §21, decision 223; values 40-49). A
  /// share starts as a TYPE_MESSAGE_CREATE with content_type
  /// "application/x-vartalap-live-location" whose body is the share as
  /// JSON; these act on it (`message_id` = that message), except CONTROL
  /// and PERMISSION, which ride 1:1 chats and carry no message id. All
  /// ride Envelope class 7 LOCATION. Recipients enforce authorship as for
  /// an UPDATE.
  ///
  /// A newer position: `live_location_point`. SILENT, short ttl_sec.
  static const ChatPayloadType TYPE_LIVE_LOCATION_UPDATE =
      ChatPayloadType._(40, _omitEnumNames ? '' : 'TYPE_LIVE_LOCATION_UPDATE');

  /// The sharer stopped before the end time. SILENT.
  static const ChatPayloadType TYPE_LIVE_LOCATION_STOP =
      ChatPayloadType._(41, _omitEnumNames ? '' : 'TYPE_LIVE_LOCATION_STOP');

  /// Turn the receiver's live location on or off from the sender's phone.
  /// Wakes the phone. The receiver acts only if it has allowed the sender
  /// (it never trusts the frame), and always shows its own notification.
  static const ChatPayloadType TYPE_LIVE_LOCATION_CONTROL =
      ChatPayloadType._(42, _omitEnumNames ? '' : 'TYPE_LIVE_LOCATION_CONTROL');

  /// The sender allows (or no longer allows) the receiver to send
  /// CONTROL; informs the receiver's UI only. SILENT.
  static const ChatPayloadType TYPE_LIVE_LOCATION_PERMISSION =
      ChatPayloadType._(
          43, _omitEnumNames ? '' : 'TYPE_LIVE_LOCATION_PERMISSION');

  static const $core.List<ChatPayloadType> values = <ChatPayloadType>[
    TYPE_UNSPECIFIED,
    TYPE_MESSAGE_CREATE,
    TYPE_MESSAGE_UPDATE,
    TYPE_MESSAGE_DELETE,
    TYPE_REACTION_ADD,
    TYPE_REACTION_REMOVE,
    TYPE_MESSAGE_FORWARD,
    TYPE_READ_RECEIPT,
    TYPE_TYPING,
    TYPE_DELIVERY_RECEIPT,
    TYPE_EVENT_RSVP,
    TYPE_LIVE_LOCATION_UPDATE,
    TYPE_LIVE_LOCATION_STOP,
    TYPE_LIVE_LOCATION_CONTROL,
    TYPE_LIVE_LOCATION_PERMISSION,
  ];

  static final $core.Map<$core.int, ChatPayloadType> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static ChatPayloadType? valueOf($core.int value) => _byValue[value];

  const ChatPayloadType._(super.value, super.name);
}

/// An answer to an event (TYPE_EVENT_RSVP).
class EventRsvp extends $pb.ProtobufEnum {
  static const EventRsvp EVENT_RSVP_UNSPECIFIED =
      EventRsvp._(0, _omitEnumNames ? '' : 'EVENT_RSVP_UNSPECIFIED');
  static const EventRsvp EVENT_RSVP_GOING =
      EventRsvp._(1, _omitEnumNames ? '' : 'EVENT_RSVP_GOING');
  static const EventRsvp EVENT_RSVP_NOT_GOING =
      EventRsvp._(2, _omitEnumNames ? '' : 'EVENT_RSVP_NOT_GOING');

  static const $core.List<EventRsvp> values = <EventRsvp>[
    EVENT_RSVP_UNSPECIFIED,
    EVENT_RSVP_GOING,
    EVENT_RSVP_NOT_GOING,
  ];

  static final $core.List<EventRsvp?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static EventRsvp? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EventRsvp._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
