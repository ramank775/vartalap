/// Shared value types for the local store.
///
/// These are deliberately thin: rows in and rows out. Domain logic
/// (optimistic send, tombstone+undo, projection maintenance) lives in
/// the repositories in [src/repositories/].
library vartalap_store.types;

/// `messages.message_state` — SPIKE_A_SCHEMA.md §5.1.
enum MessageState {
  /// Local author tapped send; sitting in undo window or queued but
  /// awaiting transport availability. Not on the wire.
  pending,

  /// Dispatched; awaiting server Ack.
  sending,

  /// Server acked (local author) OR arrived via fanout (inbound).
  sent,

  /// v3.1 reserved. Recipient confirmed receipt.
  delivered,

  /// Dual use: v3.1 read-receipt, or local "user opened the chat past this message."
  read,

  /// Permanent server reject; projection rolled back; UI shows retry.
  rejected;

  String get wire => name;

  static MessageState fromWire(String s) =>
      MessageState.values.firstWhere((e) => e.name == s,
          orElse: () => throw ArgumentError('Unknown message_state: $s'));
}

/// `outbound_ops.transport` — SPIKE_B_SYNC.md §3, §7a.
enum OpTransport {
  ws,
  rest;

  String get wire => name;

  static OpTransport fromWire(String s) =>
      OpTransport.values.firstWhere((e) => e.name == s,
          orElse: () => throw ArgumentError('Unknown transport: $s'));
}

/// `outbound_ops.status` — SPIKE_B_SYNC.md §3.
enum OpStatus {
  pending,
  inFlight,
  retrying,
  rejected,
  deadLetter,
  cascadedRejection;

  String get wire => switch (this) {
        OpStatus.pending => 'pending',
        OpStatus.inFlight => 'in_flight',
        OpStatus.retrying => 'retrying',
        OpStatus.rejected => 'rejected',
        OpStatus.deadLetter => 'dead_letter',
        OpStatus.cascadedRejection => 'cascaded_rejection',
      };

  static OpStatus fromWire(String s) => switch (s) {
        'pending' => OpStatus.pending,
        'in_flight' => OpStatus.inFlight,
        'retrying' => OpStatus.retrying,
        'rejected' => OpStatus.rejected,
        'dead_letter' => OpStatus.deadLetter,
        'cascaded_rejection' => OpStatus.cascadedRejection,
        _ => throw ArgumentError('Unknown outbound_ops.status: $s'),
      };
}

/// `outbound_ops.kind` values legal for each transport — SPIKE_B_SYNC.md §3.
class OpKind {
  static const String chatPayload = 'chat_payload';
  static const String createChannel = 'create_channel';
  static const String addMembers = 'add_members';
  static const String removeMember = 'remove_member';
  static const String editChannel = 'edit_channel';
  static const String deleteChannel = 'delete_channel';
  static const String editProfile = 'edit_profile';
  static const String registerPushTopic = 'register_push_topic';
}

class OutboundOpRow {
  final String opId;
  final OpTransport transport;
  final String kind;
  final String? restMethod;
  final String? restPath;
  final String resourceId;
  final int resourceSeq;
  final List<int> payload;
  final OpStatus status;
  final int attempts;
  final int nextRetryAt;
  final int? dispatchedAt;
  final String? lastError;
  final int? acknowledgedAt;
  final int createdAt;
  final String? targetMessageId;
  final String? targetChannelId;

  const OutboundOpRow({
    required this.opId,
    required this.transport,
    required this.kind,
    required this.restMethod,
    required this.restPath,
    required this.resourceId,
    required this.resourceSeq,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.nextRetryAt,
    required this.dispatchedAt,
    required this.lastError,
    required this.acknowledgedAt,
    required this.createdAt,
    required this.targetMessageId,
    required this.targetChannelId,
  });
}

class MessageRow {
  final String messageId;
  final String channelId;
  final String authorUserId;
  final String? body;
  final String? contentType;
  final String? replyToMessageId;
  final int clientTimestampMs;
  final int? serverTimestampMs;
  final int? deliverySequence;
  final MessageState state;
  final int stateUpdatedAt;
  final bool isEdited;
  final int? lastEditMs;
  final bool tombstoned;
  final int? tombstonePendingUntil;

  const MessageRow({
    required this.messageId,
    required this.channelId,
    required this.authorUserId,
    required this.body,
    required this.contentType,
    required this.replyToMessageId,
    required this.clientTimestampMs,
    required this.serverTimestampMs,
    required this.deliverySequence,
    required this.state,
    required this.stateUpdatedAt,
    required this.isEdited,
    required this.lastEditMs,
    required this.tombstoned,
    required this.tombstonePendingUntil,
  });
}

/// One member of a channel, joined with the contact row when known.
///
/// `contact` is null for members not yet discovered locally — the UI
/// should fall back to a userId-derived label.
class ChannelMemberRow {
  final String channelId;
  final String userId;
  final String role;
  final int joinedAt;
  final ContactRow? contact;

  const ChannelMemberRow({
    required this.channelId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    required this.contact,
  });
}

/// Row from the `contacts` table — §7.
class ContactRow {
  final String userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? statusText;
  final String? phoneHash;
  final String? contactBookName;
  final int lastRefreshedMs;

  const ContactRow({
    required this.userId,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.statusText,
    this.phoneHash,
    this.contactBookName,
    required this.lastRefreshedMs,
  });

  /// Display name resolution per AUTH_CONTRACT §2.4:
  /// contact-book name → username → userId fallback.
  ///
  /// `userId` is the ultimate fallback so non-UI callers (logging,
  /// sorting, debugging) always get a non-empty, stable string. UI
  /// surfaces should use [displayLabel] instead — exposing a raw
  /// 9-hex-char user_id to the user is jarring.
  String get resolvedName =>
      contactBookName ?? displayName ?? username ?? userId;

  /// UI-safe variant of [resolvedName]. Returns the contact-book name,
  /// then displayName, then `@username`, and finally a generic
  /// placeholder — never the raw user_id.
  String get displayLabel {
    if (contactBookName != null && contactBookName!.isNotEmpty) {
      return contactBookName!;
    }
    if (displayName != null && displayName!.isNotEmpty) {
      return displayName!;
    }
    if (username != null && username!.isNotEmpty) {
      return '@$username';
    }
    return 'Unknown';
  }
}

/// Denormalized chat-list row — SPIKE_A_SCHEMA.md §13.1.
///
/// Result shape of the JOIN between `channels` and the latest
/// `messages` row pointed at by `channels.last_message_id`. The UI
/// renders one `ChannelListEntry` per row in the chat list with no
/// further lookups.
class ChannelListEntry {
  final String channelId;
  final String kind; // 'one_to_one' | 'group'
  final String? name;
  final String? avatarUrl;
  final int lastActivityMs;
  final int unreadCount;

  /// Body text of the last non-tombstoned message. `null` if the
  /// channel has no messages yet (or the last message row is missing).
  final String? lastMessagePreview;

  /// Author of the preview-bearing message. Caller resolves the
  /// display name against its own contacts cache.
  final String? lastMessageAuthor;

  /// `true` if the channel's `last_message_id` points at a tombstoned
  /// row (e.g., the last message was deleted while still the newest).
  /// UI renders as "message deleted" rather than empty.
  final bool lastMessageTombstoned;

  const ChannelListEntry({
    required this.channelId,
    required this.kind,
    required this.name,
    required this.avatarUrl,
    required this.lastActivityMs,
    required this.unreadCount,
    required this.lastMessagePreview,
    required this.lastMessageAuthor,
    required this.lastMessageTombstoned,
  });
}
