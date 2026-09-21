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
  rest,

  /// Never reaches the chat server. [OpKind.assetUpload] ops ride the
  /// media-ms presign/PUT/status dance instead — routed to the
  /// scheduler's asset adapter, but otherwise an op like any other
  /// (retry, backoff, dead letter).
  asset;

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

  /// Message mutations. All three ride the same WS `ChatPayload` wire
  /// shape as [chatPayload] — the server never parses any of them
  /// (V3_ARCHITECTURE decision 12). The distinct `kind` exists purely
  /// so the local store knows which projection to finalize on ACK and
  /// which to roll back on a terminal reject (decision 11): a create
  /// flips to `rejected`, an edit restores its pre-edit body, a delete
  /// lifts its tombstone.
  static const String messageEdit = 'message_edit';
  static const String messageDelete = 'message_delete';
  static const String messageReaction = 'message_reaction';
  static const String createChannel = 'create_channel';
  static const String addMembers = 'add_members';
  static const String removeMember = 'remove_member';

  /// Decision 80 — `PATCH /v3.0/channels/{id}/members/{user_id}`.
  /// Distinct from [editChannel] so a terminal reject knows to put the
  /// member's role back.
  static const String setMemberRole = 'set_member_role';
  static const String editChannel = 'edit_channel';
  static const String deleteChannel = 'delete_channel';
  static const String editProfile = 'edit_profile';
  static const String registerPushTopic = 'register_push_topic';

  /// Local-only: upload one picked file to media-ms. Its ACK is what
  /// enqueues the real op (a MESSAGE_CREATE carrying the fileId, or an
  /// avatar PATCH), because the fileId does not exist until the upload
  /// has happened. Runs on [OpTransport.asset].
  static const String assetUpload = 'asset_upload';
}

class OutboundOpRow {
  final String opId;
  final OpTransport transport;
  final String kind;
  final String? restMethod;
  final String? restPath;
  final String resourceId;

  /// §6 per-resource sequence. Assigned by [ChatStore.enqueueOutboundOp]
  /// / [ChatStore.enqueueLocalMessage] from the monotonic `resource_seq`
  /// counter; the value carried by a not-yet-enqueued row is ignored.
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
    this.resourceSeq = 0,
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

/// One row of the `reactions` table, joined onto its message by the
/// channel-view query. Grouping by emoji for display is the UI's job.
class MessageReaction {
  final String emoji;
  final String userId;

  const MessageReaction({required this.emoji, required this.userId});
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

  /// Non-null while the 5-second Undo window is open (V3_ARCHITECTURE
  /// decision 11). The row is already `tombstoned`; nothing has been
  /// enqueued yet, so an Undo inside the window costs no network op.
  final int? tombstonePendingUntil;

  /// Raw `messages.attachments` BLOB — a `ChatPayload` protobuf whose
  /// only populated field is `attachments`, exactly as InboundReceiver
  /// stored it. The store does not depend on the proto package, so
  /// callers decode. Null when the message carries none.
  final List<int>? attachments;

  /// Reactions on this message. Populated by the channel-view query
  /// ([ChatStore.fetchChannelMessages]); empty from every other read.
  final List<MessageReaction> reactions;

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
    this.attachments,
    this.reactions = const [],
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
  /// contact-book name → `@username` → server displayName → userId.
  ///
  /// `userId` is the ultimate fallback so non-UI callers (logging,
  /// sorting, debugging) always get a non-empty, stable string. UI
  /// surfaces should use [displayLabel] instead — exposing a raw
  /// 9-hex-char user_id to the user is jarring.
  String get resolvedName =>
      contactBookName ?? (username == null ? null : '@$username') ??
          displayName ?? userId;

  /// **The** display-name resolver for another user — AUTH_CONTRACT
  /// §2.4. Every UI surface that labels someone other than the signed-in
  /// user routes through here (directly, or via [ChannelListEntry.title]
  /// for a channel row). The order is the contract's:
  ///
  /// 1. contact-book name — the viewer chose what to call this person;
  /// 2. `@username` — the required public identifier;
  /// 3. the server-side displayName — only reachable for a contact we
  ///    learned about through a `ProfileEdited` fanout before their
  ///    handle ever landed;
  /// 4. a generic placeholder.
  ///
  /// A phone number is never in this chain, in any form (§2.5) — the
  /// client does not hold another user's number at all.
  String get displayLabel {
    if (contactBookName != null && contactBookName!.isNotEmpty) {
      return contactBookName!;
    }
    if (username != null && username!.isNotEmpty) {
      return '@$username';
    }
    if (displayName != null && displayName!.isNotEmpty) {
      return displayName!;
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

  /// Local-only pin flag. Pinned rows sort above everything else.
  final bool pinned;

  /// Local-only mute expiry in epoch ms. `null` = not muted; a
  /// far-future value is the "Always" option from the mute sheet.
  final int? mutedUntilMs;

  /// `true` when at least one outbound op targeting this channel is in
  /// `dead_letter` — the chat list shows a "Not sent" indicator.
  final bool hasFailedOp;

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

  /// For a `one_to_one` channel: the peer's local `contacts` row, when
  /// we have one. Null for groups and for peers we have never
  /// discovered. Exists so [title] can run the AUTH_CONTRACT §2.4
  /// resolver live instead of trusting the `channels.name` snapshot,
  /// which is frozen at creation time and, for a DM the *peer* created,
  /// carries their label for us rather than ours for them.
  final ContactRow? peerContact;

  /// Muted *right now*. An expired `muted_until_ms` reads as unmuted
  /// without needing a sweep job.
  bool isMutedAt(int nowMs) => mutedUntilMs != null && mutedUntilMs! > nowMs;

  const ChannelListEntry({
    required this.channelId,
    required this.kind,
    required this.name,
    required this.avatarUrl,
    required this.lastActivityMs,
    required this.unreadCount,
    this.pinned = false,
    this.mutedUntilMs,
    this.hasFailedOp = false,
    required this.lastMessagePreview,
    required this.lastMessageAuthor,
    required this.lastMessageTombstoned,
    this.peerContact,
  });

  /// The label to render for this row. Groups own their name; a DM
  /// defers to the one resolver ([ContactRow.displayLabel]) and only
  /// falls back to the stored snapshot when the peer is undiscovered.
  /// Never the raw channel_id, never a phone number.
  String get title {
    if (kind == 'one_to_one') {
      final resolved = peerContact?.displayLabel;
      if (resolved != null && resolved != 'Unknown') return resolved;
      return name ?? 'Unknown';
    }
    return name ?? 'Unnamed group';
  }
}
