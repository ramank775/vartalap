/// v3 chat service adapter.
///
/// Thin wrapper around [ChatStore] + [SyncScheduler] that exposes the
/// handful of reactive queries and actions the UI needs. All reads
/// come off the local store's watch streams (offline-first per
/// V3_ARCHITECTURE.md decision 3); writes land locally first and
/// enqueue an outbound op so the scheduler takes it from there.
///
/// The v2 `ChatService` was a pile of static methods with its own
/// socket + SQLite entanglement. v3 inverts that: this class holds
/// nothing stateful beyond its constructor args; the store is the
/// source of truth.
library vartalap.services.chat_service;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter/foundation.dart'
    show ValueNotifier, listEquals, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/timeline_client.dart';
import 'package:vartalap/services/album_client.dart';
import 'dart:isolate';

import 'package:vartalap/services/message_crypto.dart';
import 'package:vartalap/utils/rich_message.dart' show kLiveLocationType;
import 'package:vartalap_crypto/vartalap_crypto.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

part 'timeline.dart';
part 'albums.dart';

/// Build the WS_OP payload for an outbound text message — a
/// `ChatPayload{TYPE_MESSAGE_CREATE}` protobuf (SYNC_PROTOCOL §6a.1,
/// docs/proto/v3-chat-payload.proto). This is what the server and
/// every recipient's InboundReceiver decode; anything else is
/// rejected `validation_failed`.
Uint8List _encodeChatPayload({
  required String messageId,
  required String body,
  String contentType = 'text/plain',
  String? replyToMessageId,
  int timerSec = 0,
  SealedSecret? secure,
}) =>
    pb.ChatPayload(
      version: 1,
      type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
      messageId: uuidBytes(messageId),
      // A secure message has none (decision 222); its [body] is its
      // title, which goes beside the box.
      body: body.isEmpty || secure != null ? null : body,
      // Plain text is the proto's default: not sent (decision 218), and a
      // receiver stores none, which reads as text.
      contentType: contentType == 'text/plain' ? null : contentType,
      replyToMessageId:
          replyToMessageId == null ? null : uuidBytes(replyToMessageId),
      timerSec: timerSec == 0 ? null : timerSec,
      secureBox: secure?.box,
      secureKey: secure?.key,
      secureTitle: secure == null || body.isEmpty ? null : body,
    ).writeToBuffer();

/// A secure message's sealed secret (decision 222, [sealSecret]).
typedef SealedSecret = ({Uint8List box, Uint8List? key});

// Argon2id takes a second or more: off the UI isolate. Top level, so the
// closure carries only its arguments across.
Future<SealedSecret> _sealWithPassword(String secret, String password) =>
    Isolate.run(() => sealSecret(secret, password: password));

Future<String> _openWithPassword(Uint8List box, String password) =>
    Isolate.run(() => openSecret(box, password: password));

/// SYNC_PROTOCOL §25: from this many forwards a message reads "Forwarded
/// many times" (WhatsApp's), and goes on to one chat at a time.
const int kForwardedManyTimes = 5;

/// Decision 222: the timers a message can be sent with, in seconds (0 is
/// Off), and how the composer names them.
const Map<int, String> kMessageTimers = {
  0: 'Off',
  60: '1 minute',
  300: '5 minutes',
  3600: '1 hour',
  86400: '1 day',
};

/// The other four ChatPayload types (SYNC_PROTOCOL §6a,
/// docs/proto/v3-chat-payload.proto). Same envelope, same opacity to
/// the server — recipients dispatch on `type` in InboundReceiver and
/// enforce authorship for UPDATE / DELETE themselves (§6a.3).
Uint8List _encodeChatOp({
  required pb.ChatPayloadType type,
  required String messageId,
  String? body,
  String? contentType,
  Iterable<pb.Attachment>? attachments,
  String? emoji,
}) =>
    pb.ChatPayload(
      version: 1,
      type: type,
      messageId: uuidBytes(messageId),
      body: body,
      contentType: contentType == 'text/plain' ? null : contentType,
      attachments: attachments,
      emoji: emoji,
    ).writeToBuffer();

/// Build the WS_OP payload for an outbound typing indicator — a
/// `ChatPayload{TYPE_TYPING}` (decision 56: the gateway refuses any
/// client-authored `0x53` server event, SYNC_PROTOCOL §10.2). The
/// routing distinguisher is the envelope's `ephemeral` flag, not the
/// payload bytes; channel/sender/timestamp ride on the envelope.
Uint8List _encodeTyping({required bool isTyping}) => pb.ChatPayload(
      version: 1,
      type: pb.ChatPayloadType.TYPE_TYPING,
      isTyping: isTyping,
    ).writeToBuffer();

/// Build the WS_OP payload for an outbound read or delivery receipt — a
/// `ChatPayload{TYPE_READ_RECEIPT | TYPE_DELIVERY_RECEIPT}` carrying only
/// the up-to message's server timestamp (decisions 56, 218). A normal,
/// non-ephemeral op: it is ACKed like any other. Every recipient flips
/// its OWN messages stamped at or before the marker. [groupId]: a
/// group's receipt, sent over 1:1 to one author.
Uint8List _encodeReceipt(pb.ChatPayloadType type, int marker,
        {String? groupId}) =>
    pb.ChatPayload(
      version: 1,
      type: type,
      markerServerTimestampMs: fixnum.Int64(marker),
      groupId: groupId == null ? null : uuidBytes(groupId),
    ).writeToBuffer();

/// A presence op's payload (SYNC_PROTOCOL §22): whether the app is on
/// screen, as the `0x53` `Presence` the server reads.
Uint8List _encodePresence(bool onScreen) => Uint8List.fromList([
      0x53,
      ...pb.ServerEventPayload(
        version: 1,
        type: pb.ServerEventType.PRESENCE,
        presence: pb.Presence(online: onScreen),
      ).writeToBuffer(),
    ]);

/// A DM peer's presence as the server lets this phone see it
/// (SYNC_PROTOCOL §22): online, else when last seen (ms since epoch).
typedef PeerPresence = ({bool online, int lastSeenMs});

/// SharedPreferences keys of the Settings › Privacy switches (decision 223).
const String kReadReceiptsPrefKey = 'privacy.read_receipts';
const String kTypingIndicatorPrefKey = 'privacy.typing_indicator';

/// AUTH_CONTRACT §7.2: the most phone hashes one lookup may carry.
const int kContactLookupBatch = 5000;

/// Decision 208: how long a number found not on Vartalap waits before
/// it is looked up again.
const Duration kContactLookupCooldown = Duration(minutes: 15);

class ChatService with TimelineService, AlbumService {
  /// Seals typing indicators (decision 188). Set by `main.dart`.
  MessageCrypto? crypto;

  /// The safety number to compare with [peerUserId] (decision 184), null
  /// until a message has gone between the two phones.
  Future<String?> safetyNumber(String peerUserId) async =>
      crypto?.crypto.safetyNumber(peerUserId);

  final ChatStore _store;
  final SyncScheduler _scheduler;
  final AuthClient _authClient;
  final Clock _clock;
  final WsTransport _wsTransport;

  /// Broadcast passthrough for inbound typing events. main.dart wires
  /// every InboundReceiver instance (built/rebuilt per login) into this
  /// controller via [bindTypingSource], so chat screens can subscribe
  /// once and stay correct across logout/login cycles.
  final StreamController<TypingEvent> _typingCtrl =
      StreamController<TypingEvent>.broadcast();
  StreamSubscription<TypingEvent>? _typingSub;
  StreamSubscription<String>? _deliverySub;
  final Map<String, Timer> _deliveryTimers = {};

  Stream<TypingEvent> get typingEvents => _typingCtrl.stream;

  /// Replace the inbound typing source. Cancels the previous bridge if
  /// any. Pass `null` to detach (e.g. on logout while the screen is
  /// already torn down). Idempotent.
  void bindTypingSource(Stream<TypingEvent>? source) {
    _typingSub?.cancel();
    _typingSub = null;
    if (source == null) return;
    _typingSub = source.listen((e) {
      // decision 223: typing off shows nobody's either
      if (typingIndicator.value && !_typingCtrl.isClosed) _typingCtrl.add(e);
    });
  }

  /// Replace the source of "a peer message was stored in channel X"
  /// (InboundReceiver.peerMessagesStored). Each burst per channel becomes
  /// one TYPE_DELIVERY_RECEIPT naming the newest peer message, so the
  /// author's tick goes grey ✓✓. Pass `null` to detach. Idempotent.
  void bindDeliverySource(Stream<String>? source) {
    _deliverySub?.cancel();
    _deliverySub = null;
    for (final t in _deliveryTimers.values) {
      t.cancel();
    }
    _deliveryTimers.clear();
    if (source == null) return;
    _deliverySub = source.listen((channelId) {
      // ponytail: in-memory 500 ms debounce per channel; a receipt still
      // pending when the process dies is lost, and the next peer message
      // or the read receipt covers it.
      _deliveryTimers[channelId]?.cancel();
      _deliveryTimers[channelId] = Timer(
        const Duration(milliseconds: 500),
        () {
          _deliveryTimers.remove(channelId);
          // Fire-and-forget: a failed receipt only costs the grey tick.
          _enqueueReceipt(channelId, pb.ChatPayloadType.TYPE_DELIVERY_RECEIPT)
              .catchError((Object e) {
            // ignore: avoid_print
            print('ChatService: delivery receipt for $channelId failed: $e');
          });
        },
      );
    });
  }

  /// The delivery receipts still waiting out their debounce, queued now:
  /// a push wake's engine may not live the 500 ms.
  Future<void> queueDeliveryReceiptsNow() async {
    final channels = _deliveryTimers.keys.toList();
    for (final t in _deliveryTimers.values) {
      t.cancel();
    }
    _deliveryTimers.clear();
    for (final channelId in channels) {
      await _enqueueReceipt(
          channelId, pb.ChatPayloadType.TYPE_DELIVERY_RECEIPT);
    }
  }

  /// Presigned-upload / download cache for attachments and avatars.
  /// Also published as [AssetCache.instance] for widgets that cannot
  /// reach a service (see [_installAssetPipeline]).
  late final AssetCache assets;

  /// Current op_id generator. Swapped via [reseedForUser] when the
  /// authenticated user changes — see the class doc on [reseedForUser]
  /// for why the `userIdBits` embedded in every op_id must match the
  /// signed-in session.
  Uuid7Gen _uuidGen;

  /// [uuidGen] must be seeded with the authenticated user's 36-bit
  /// user_id (SPIKE_B_SYNC.md §4). Before login `main.dart` passes a
  /// 0-seeded gen; the UI must not call [sendMessage] until
  /// [reseedForUser] has run with the real user_id from OTP verify.
  ChatService({
    required ChatStore store,
    required SyncScheduler scheduler,
    required AuthClient authClient,
    required WsTransport wsTransport,
    required Uuid7Gen uuidGen,
    required Clock clock,
  })  : _store = store,
        _scheduler = scheduler,
        _authClient = authClient,
        _wsTransport = wsTransport,
        _uuidGen = uuidGen,
        _clock = clock {
    _installAssetPipeline();
    _presenceSubs = [
      // a new socket starts off line: say again where we are
      _wsTransport.state.listen((s) {
        if (s == TransportState.connected) _sendPresence();
      }),
      _wsTransport.pushes.listen(_onPresence),
    ];
    // The socket starts with the app, so it can be up before an account
    // (and this service) opens: `state` has no replay, say it now.
    if (_wsTransport.currentState == TransportState.connected) {
      _sendPresence();
    }
    // Last seen by labels: a label's people changed (or a send failed
    // last time), so the server's list is stale.
    _presenceSubs.add(_store.tableChanges.listen((tables) {
      if (tables.contains('labels')) unawaited(_resendPresenceUsers());
    }));
    unawaited(_resendPresenceUsers());
  }

  // ---- Settings › Privacy (decision 223, track F) -----------------------

  /// Off: a 1:1 chat is sent delivered receipts only, and its peer's read
  /// receipts show as delivered (WhatsApp: who sends none sees none).
  /// Groups keep read receipts either way.
  final ValueNotifier<bool> readReceipts = ValueNotifier(true);

  /// Off: no "typing…" goes out, and none shows.
  final ValueNotifier<bool> typingIndicator = ValueNotifier(true);

  /// Read both switches. Per phone, like the theme. Unreadable: both on.
  Future<void> loadPrivacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      readReceipts.value = prefs.getBool(kReadReceiptsPrefKey) ?? true;
      typingIndicator.value = prefs.getBool(kTypingIndicatorPrefKey) ?? true;
    } catch (_) {/* no platform channel: a plain test, keep the defaults */}
  }

  Future<void> setReadReceipts(bool on) async {
    readReceipts.value = on;
    await (await SharedPreferences.getInstance())
        .setBool(kReadReceiptsPrefKey, on);
  }

  Future<void> setTypingIndicator(bool on) async {
    typingIndicator.value = on;
    await (await SharedPreferences.getInstance())
        .setBool(kTypingIndicatorPrefKey, on);
  }

  // ---- Last seen by labels (SYNC_PROTOCOL §22, decision 226) ------------

  String get _presenceLabelsKey =>
      'v3.presenceLabels.${_authClient.currentUserId}';

  /// The `only` / `except` setting as this phone made it: the labels
  /// picked and the user ids last sent for them. The server holds only
  /// the ids; null for a plain setting, or when nothing was saved here.
  Future<({String mode, Set<int> labels, List<String> users})?>
      presenceLabels() async {
    try {
      final saved =
          (await SharedPreferences.getInstance()).getString(_presenceLabelsKey);
      if (saved == null) return null;
      final json = jsonDecode(saved) as Map<String, dynamic>;
      return (
        mode: json['mode'] as String,
        labels: {for (final id in json['labels'] as List) id as int},
        users: [for (final u in json['users'] as List) u as String],
      );
    } catch (_) {
      return null; // no platform channel (a plain test), or unreadable
    }
  }

  /// Who sees our last seen and online: a plain [mode], or `only` /
  /// `except` with everyone in [labelIds], resolved here (the server
  /// never sees a label) and sent again whenever those labels change.
  /// Server first: throws when offline, and nothing changes.
  Future<void> setPresence(String mode, [Set<int>? labelIds]) async {
    final users = labelIds == null ? null : await _labelMembers(labelIds);
    await _authClient.patchOwnProfile(presence: mode, presenceUsers: users);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (labelIds == null) {
        await prefs.remove(_presenceLabelsKey);
      } else {
        await prefs.setString(_presenceLabelsKey,
            jsonEncode({'mode': mode, 'labels': [...labelIds], 'users': users}));
      }
    } catch (_) {
      // No platform channel (a plain test): the server has it; labels
      // changing later are not followed.
    }
  }

  /// Everyone carrying any of [labelIds], sorted. The server keeps to
  /// contacts, so no filtering here.
  Future<List<String>> _labelMembers(Set<int> labelIds) async => {
        for (final l in await _store.fetchLabels())
          if (labelIds.contains(l.labelId)) ...l.userIds,
      }.toList()
        ..sort();

  /// The saved labels' people differ from what the server has: send them.
  /// Offline, the next label change or account open tries again.
  Future<void> _resendPresenceUsers() async {
    final saved = await presenceLabels();
    if (saved == null) return;
    try {
      final users = await _labelMembers(saved.labels);
      if (listEquals(users, saved.users)) return;
      await setPresence(saved.mode, saved.labels);
    } catch (_) {}
  }

  // ---- Presence (SYNC_PROTOCOL §22) -------------------------------------

  /// The watched DM peer's presence as the server lets us see it; null:
  /// show nothing.
  final ValueNotifier<PeerPresence?> presence = ValueNotifier(null);
  String? _watchedChannel;
  String? _watchedPeer;
  bool _onScreen = true;
  List<StreamSubscription<Object?>> _presenceSubs = const [];

  /// The open chat: a DM's peer is watched (its presence lands in
  /// [presence]); a group, or null, watches nobody.
  Future<void> watchPresence(String? channelId) async {
    final me = _authClient.currentUserId;
    _watchedChannel = channelId;
    presence.value = null;
    final peer = channelId == null || me == null || !isDmChannelId(channelId)
        ? null
        : await _store.dmPeer(channelId, me);
    if (_watchedChannel != channelId) return; // another chat opened meanwhile
    _watchedPeer = peer;
    _sendPresence();
  }

  /// [channelId]'s screen closed: stop watching, unless another chat took
  /// over the watch.
  void unwatchPresence(String channelId) {
    if (_watchedChannel == channelId) unawaited(watchPresence(null));
  }

  /// The app came on screen or left it: online is the app on screen.
  void setOnScreen(bool onScreen) {
    if (_onScreen == onScreen) return;
    _onScreen = onScreen;
    _sendPresence();
  }

  /// Account closed: stop listening to the socket.
  void stopPresence() {
    for (final s in _presenceSubs) {
      s.cancel();
    }
    _presenceSubs = const [];
  }

  /// A presence op: on screen or not, and whom we watch (ourselves for
  /// nobody). Ephemeral, to the server only; dropped while offline, and
  /// sent again on every reconnect.
  void _sendPresence() {
    final me = _authClient.currentUserId;
    if (me == null || me.isEmpty) return;
    final peer = _watchedPeer ?? me;
    _wsTransport.sendEphemeral(
      opId: _uuidGen.next(nowMs: _clock.nowMs()),
      channelId: dmChannelId(me, peer),
      peer: peer,
      payload: _encodePresence(_onScreen),
      flags: FrameClass.presence.flags,
    );
  }

  void _onPresence(InboundEnvelope env) {
    final p = env.payload;
    if (!env.ephemeral ||
        (env.flags >> 1) & 15 != FrameClass.presence.index ||
        p.isEmpty ||
        p[0] != 0x53) {
      return;
    }
    final pb.Presence body;
    try {
      body = pb.ServerEventPayload.fromBuffer(p.sublist(1)).presence;
    } catch (_) {
      return;
    }
    if (body.userId != _watchedPeer) return;
    final lastSeen = body.lastSeenMs.toInt();
    presence.value = body.online || lastSeen > 0
        ? (online: body.online, lastSeenMs: lastSeen)
        : null;
  }

  /// Replace the internal op_id generator after login / phone rebind.
  ///
  /// Every outbound op embeds the signed-in user's 36-bit user_id in
  /// the UUIDv7 (SPIKE_B_SYNC.md §4) and the server rejects anything
  /// else as `prefix_mismatch` (SYNC_PROTOCOL.md §3). If a user logs
  /// in mid-session, the generator constructed at app boot still
  /// carries the pre-login zero bits; without this reseed the first
  /// send after login would be rejected.
  ///
  /// `main.dart` calls this on every `AuthService.authStateChange`
  /// emission where the user is now logged in.
  void reseedForUser(String userIdHex) {
    _uuidGen = Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(userIdHex));
    // Trim 4: the dispatcher names the other participant on every op
    // that targets a derived DM channel, and "other" is relative to
    // the signed-in user.
    _scheduler.selfUserId = userIdHex;
  }

  /// Chat list hot path — SPIKE_A_SCHEMA.md §13.1 via
  /// [ChatStore.watchChannelList].
  Stream<List<ChannelListEntry>> watchChannels({int limit = 100}) =>
      _store.watchChannelList(limit: limit);

  /// Messages in one channel, newest-first, pending rows on top —
  /// SPIKE_A_SCHEMA.md §13.2 via [ChatStore.watchChannelMessages].
  /// Pass a [window] for a growable page ("load older" without a
  /// second live query) — see [MessageWindow].
  Stream<List<MessageRow>> watchMessages(
    String channelId, {
    int limit = 200,
    MessageWindow? window,
  }) =>
      _store.watchChannelMessages(channelId, limit: limit, window: window);

  /// §5.3 optimistic send.
  ///
  /// 1. Builds a pending [MessageRow] with a fresh client UUIDv7 and
  ///    a matching `op_id` (both UUIDv7, distinct).
  /// 2. Calls [ChatStore.enqueueLocalMessage] which atomically inserts
  ///    the message, the outbound op, and bumps the channel's
  ///    `last_activity_ms`.
  /// 3. Nudges the scheduler so Flow A picks the op up immediately if
  ///    the WS transport is connected. If offline, the op sits in the
  ///    queue until reconnect.
  ///
  /// The UI sees the pending message in [watchMessages] synchronously
  /// (same frame as the send-button tap) — local commit is the
  /// critical-path latency target (<100ms, V3_ARCHITECTURE
  /// "Performance targets").
  /// [contentType] other than `text/plain` marks a contact, location
  /// or event carried as standard text in [body] (decision 133).
  /// [timerSec]: a timed message (decision 222), gone from both phones
  /// that long after the server takes it. [secure]: see [sendSecure];
  /// [body] is then its title, or empty.
  Future<void> sendMessage({
    required String channelId,
    required String body,
    required String authorUserId,
    String? replyToMessageId,
    String contentType = 'text/plain',
    int timerSec = 0,
    SealedSecret? secure,
  }) async {
    final now = _clock.nowMs();
    final messageId = _uuidGen.next(nowMs: now);
    final opId = _uuidGen.next(nowMs: now);

    final message = MessageRow(
      messageId: messageId,
      channelId: channelId,
      authorUserId: authorUserId,
      body: secure == null || body.isNotEmpty ? body : null,
      contentType: contentType,
      replyToMessageId: replyToMessageId,
      clientTimestampMs: now,
      serverTimestampMs: null,
      state: MessageState.pending,
      stateUpdatedAt: now,
      isEdited: false,
      lastEditMs: null,
      tombstoned: false,
      tombstonePendingUntil: null,
      timerSec: timerSec == 0 ? null : timerSec,
      secure: secure == null
          ? null
          : pb.ChatPayload(secureBox: secure.box, secureKey: secure.key)
              .writeToBuffer(),
    );

    final op = OutboundOpRow(
      opId: opId,
      transport: OpTransport.ws,
      kind: OpKind.chatPayload,
      restMethod: null,
      restPath: null,
      resourceId: channelId,
      payload: _encodeChatPayload(
        messageId: messageId,
        body: body,
        contentType: contentType,
        replyToMessageId: replyToMessageId,
        timerSec: timerSec,
        secure: secure,
      ),
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: now,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: now,
      targetMessageId: messageId,
      targetChannelId: channelId,
    );

    await _store.enqueueLocalMessage(
      message: message,
      op: op,
      nowMs: now,
    );
    _scheduler.tickSoon();
  }

  /// Decision 222: send [secret] as a secure message, hidden until opened.
  /// Without a [password] it opens with the receiving phone's screen lock
  /// (its random key rides inside the end-to-end encrypted payload); with
  /// one, only with that password (Argon2id, off this isolate), which the
  /// sender passes on another way. The secret is never in `body`; its
  /// optional [title] is (at most [kSecureTitleMax] characters), shown
  /// without unlocking (SYNC_PROTOCOL §20.4).
  Future<void> sendSecure({
    required String channelId,
    required String secret,
    required String authorUserId,
    String? password,
    String? title,
    String? replyToMessageId,
    int timerSec = 0,
  }) async =>
      sendMessage(
        channelId: channelId,
        body: secureTitle(title),
        authorUserId: authorUserId,
        replyToMessageId: replyToMessageId,
        contentType: kSecureType,
        timerSec: timerSec,
        secure: password == null
            ? sealSecret(secret)
            : await _sealWithPassword(secret, password),
      );

  /// The most chats one forward goes to (WhatsApp's); one at a time for a
  /// message already [kForwardedManyTimes] forwards along.
  static const int maxForwardChats = 5;

  /// SYNC_PROTOCOL §25: what may be forwarded. Not a deleted message or
  /// one still waiting to decrypt; not a live location (the sharer's, and
  /// live) or a timed message (its sender meant it to go); not an
  /// attachment still on its way up (its url is a file on this phone);
  /// not an album's note (only its own chat can open the album).
  static bool canForward(MessageRow m) {
    if (m.tombstoned ||
        m.timerSec != null ||
        const {
          kUndecryptedType,
          kGroupEventType,
          kLiveLocationType,
          kAlbumType,
        }.contains(m.contentType)) {
      return false;
    }
    final files = m.attachments == null
        ? const <pb.Attachment>[]
        : pb.ChatPayload.fromBuffer(m.attachments!).attachments;
    if (files.any((a) => a.url.startsWith('/'))) return false;
    return files.isNotEmpty || m.secure != null || (m.body ?? '').isNotEmpty;
  }

  /// How many forwards [m]'s content has been through; 0 for an original.
  static int forwardCount(MessageRow m) => m.forwardSource == null
      ? 0
      : max(1, pb.ForwardSource.fromBuffer(m.forwardSource!).forwardCount);

  /// Forward [messages] to each of [channelIds], oldest first: new
  /// messages with the same content, marked as forwards (SYNC_PROTOCOL
  /// §25). Attachments keep their url, so nothing is uploaded again; a
  /// secure message keeps its sealed box and key byte for byte, never
  /// re-sealed (decision 222). Throws [ArgumentError] for a message
  /// [canForward] refuses.
  Future<void> forwardMessages({
    required List<MessageRow> messages,
    required List<String> channelIds,
    required String authorUserId,
  }) async {
    if (!messages.every(canForward)) {
      throw ArgumentError('This message cannot be forwarded.');
    }
    final sorted = [...messages]
      ..sort((a, b) => a.displayTimestampMs.compareTo(b.displayTimestampMs));
    for (final channelId in channelIds) {
      for (final m in sorted) {
        final now = _clock.nowMs();
        final messageId = _uuidGen.next(nowMs: now);
        final source = pb.ForwardSource(forwardCount: forwardCount(m) + 1);
        final secure =
            m.secure == null ? null : pb.ChatPayload.fromBuffer(m.secure!);
        await _store.enqueueLocalMessage(
          message: MessageRow(
            messageId: messageId,
            channelId: channelId,
            authorUserId: authorUserId,
            body: m.body,
            contentType: m.contentType,
            replyToMessageId: null,
            clientTimestampMs: now,
            serverTimestampMs: null,
            state: MessageState.pending,
            stateUpdatedAt: now,
            isEdited: false,
            lastEditMs: null,
            tombstoned: false,
            tombstonePendingUntil: null,
            attachments: m.attachments,
            secure: m.secure,
            forwardSource: source.writeToBuffer(),
          ),
          op: _chatOp(
            kind: OpKind.chatPayload,
            channelId: channelId,
            messageId: messageId,
            nowMs: now,
            payload: pb.ChatPayload(
              version: 1,
              type: pb.ChatPayloadType.TYPE_MESSAGE_FORWARD,
              messageId: uuidBytes(messageId),
              // A secure message's body is its title (§20.4).
              body: (m.body ?? '').isEmpty || secure != null ? null : m.body,
              secureTitle:
                  secure == null || (m.body ?? '').isEmpty ? null : m.body,
              contentType: m.contentType == 'text/plain' ? null : m.contentType,
              attachments: m.attachments == null
                  ? null
                  : pb.ChatPayload.fromBuffer(m.attachments!).attachments,
              forwardSource: source,
              secureBox: secure?.secureBox,
              secureKey: secure != null && secure.hasSecureKey()
                  ? secure.secureKey
                  : null,
            ).writeToBuffer(),
          ),
          nowMs: now,
        );
      }
    }
    _scheduler.tickSoon();
  }

  /// Answer [messageId], an event, Going or Not going (decision 134,
  /// SYNC_PROTOCOL §25.3); a later answer replaces it. Rides the
  /// reaction's op kind: nothing to roll back if it fails.
  Future<void> rsvp({
    required String channelId,
    required String messageId,
    required String userId,
    required bool going,
  }) async {
    final now = _clock.nowMs();
    await _store.enqueueRsvp(
      messageId: messageId,
      userId: userId,
      going: going,
      nowMs: now,
      op: _chatOp(
        kind: OpKind.messageReaction,
        channelId: channelId,
        messageId: messageId,
        nowMs: now,
        payload: pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_EVENT_RSVP,
          messageId: uuidBytes(messageId),
          eventRsvp: going
              ? pb.EventRsvp.EVENT_RSVP_GOING
              : pb.EventRsvp.EVENT_RSVP_NOT_GOING,
        ).writeToBuffer(),
      ),
    );
    _scheduler.tickSoon();
  }

  /// Message info (SYNC_PROTOCOL §25.2) for our own [messageId]: who got
  /// it and read it, and when; again whenever a receipt lands.
  Stream<List<MessageReceipt>> watchMessageReceipts(String messageId) =>
      _store.watchTables(
          const {'receipt_marks', 'messages'},
          () => _store.fetchMessageReceipts(
              messageId, _authClient.currentUserId ?? ''));

  /// How [m], a secure message, opens; null when it is none this build
  /// can open.
  static SecureUnlock? secureUnlock(MessageRow m) {
    final box = m.secure == null
        ? null
        : pb.ChatPayload.fromBuffer(m.secure!).secureBox;
    try {
      return box == null ? null : secureUnlockOf(box);
    } on FormatException {
      return null;
    }
  }

  /// The secret in [m]. The caller has passed the screen lock, or asked
  /// for the [password]. Throws [SecretLocked] for a wrong password.
  Future<String> openSecure(MessageRow m, {String? password}) async {
    final p = pb.ChatPayload.fromBuffer(m.secure!);
    final box = Uint8List.fromList(p.secureBox);
    if (password == null) return openSecret(box, key: p.secureKey);
    return _openWithPassword(box, password);
  }

  /// Refresh the cached profile of a DM's peer from
  /// `GET /v3.0/users/{user_id}` (AUTH_CONTRACT §7.5).
  ///
  /// Trim 4 deleted the server-side DM row, and with it the server's
  /// only way to know that two people who have only ever DM'd share a
  /// conversation — so `PROFILE_EDITED` / `USERNAME_CHANGED` fanout
  /// (SYNC_PROTOCOL §10.3) reached group co-members only, and a DM-only
  /// peer's name, handle and avatar went stale until this pull. Since
  /// chat-server rc.5 (decision 237) the fanout reaches connections too,
  /// in under a second; this stays for an older server and for an event
  /// that expired unread.
  ///
  /// ponytail: pull on open instead of a subscription or a poll. One
  /// cheap read when the user looks at the chat is the whole fix; it
  /// is also the only moment the staleness is visible. Best-effort —
  /// offline or a 404 leaves the cached row alone. If a push-based
  /// answer is ever wanted it belongs on the server, not here.
  Future<void> refreshDmPeerProfile(String channelId) async {
    final localUserId = _authClient.currentUserId;
    if (localUserId == null || !isDmChannelId(channelId)) return;
    final peerUserId = await _store.dmPeer(channelId, localUserId);
    if (peerUserId == null) return;
    try {
      final profile = await _authClient.getUser(peerUserId);
      final existing = (await _store.fetchContacts())
          .where((c) => c.userId == peerUserId)
          .firstOrNull;
      await _store.upsertContact(
        userId: peerUserId,
        username: profile['username'] as String?,
        displayName: profile['displayName'] as String?,
        avatarUrl: profile['avatarUrl'] as String?,
        statusText: profile['statusText'] as String?,
        // upsertContact is INSERT OR REPLACE — the address-book fields
        // are ours, never the server's, so carry them forward.
        phoneHash: existing?.phoneHash,
        contactBookName: existing?.contactBookName,
        nowMs: _clock.nowMs(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('refreshDmPeerProfile($channelId) failed: $e');
    }
  }

  /// Create a **group** locally and enqueue a REST op to
  /// POST /v3.0/channels.
  ///
  /// The local channel row appears in [watchChannels] immediately; the
  /// REST op confirms it server-side. If the server rejects, the channel
  /// stays local (acceptable for v3.0 — no server-side delete yet).
  ///
  /// Trim 4: there is no `kind` to choose any more. A DM is never
  /// created — its id is derived from the pair (see
  /// [startDirectMessage]) and the server keeps no row for it — so
  /// `POST /v3.0/channels` takes groups and nothing else.
  Future<String> createChannel({
    required String ownerUserId,
    required List<String> memberUserIds,
    String? name,
  }) async {
    const kind = 'group';
    final now = _clock.nowMs();
    final channelId = _uuidGen.next(nowMs: now);
    final opId = _uuidGen.next(nowMs: now);

    await _store.insertChannel(
      channelId: channelId,
      kind: kind,
      ownerUserId: ownerUserId,
      createdAt: now,
      name: name,
    );

    final payload = utf8.encode(jsonEncode({
      'channel_id': channelId,
      'kind': kind,
      'name': name,
      // SYNC_PROTOCOL §11.3: the roster the server stores is the one it
      // is sent, and the creator must be in it — the real gateway
      // answers 403 `forbidden` ("creator must be in members") when it
      // isn't. A Set keeps the call idempotent if a caller passes the
      // owner in [memberUserIds] too.
      'members': <String>{ownerUserId, ...memberUserIds}.toList(),
    }));

    final op = OutboundOpRow(
      opId: opId,
      transport: OpTransport.rest,
      kind: OpKind.createChannel,
      restMethod: 'POST',
      restPath: '/v3.0/channels',
      resourceId: channelId,
      payload: payload,
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: now,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: now,
      targetMessageId: null,
      targetChannelId: channelId,
    );

    await _store.enqueueOutboundOp(op);
    _scheduler.tickSoon();
    return channelId;
  }

  /// Advances the local read marker, zeroes `unread_count`, and (if
  /// the user is logged in and the channel has at least one peer
  /// message) enqueues an outbound `ChatPayload{TYPE_READ_RECEIPT}` so
  /// the author's tick flips to read on their device. Best-effort: if
  /// the op enqueue fails the local read marker still moves.
  /// [clearNotification] false: a reply from the notification leaves it
  /// up a moment, showing what was sent.
  Future<void> markRead(String channelId,
      {bool clearNotification = true}) async {
    await _store.markChannelRead(channelId, _clock.nowMs());
    if (clearNotification) onRead?.call(channelId);
    await _enqueueReceipt(channelId, pb.ChatPayloadType.TYPE_READ_RECEIPT);
  }

  /// Set by `main.dart`: a chat was read, so its notification goes.
  void Function(String channelId)? onRead;

  /// Enqueues a read or delivery receipt up to the newest peer message in
  /// [channelId]; no-op when logged out or there is nothing new.
  ///
  /// A peer message's `message_state` (which draws no tick) records the
  /// receipts sent for it: `sent` none yet, then `delivered`, then `read`
  /// (a read covers delivery, so a chat read within the debounce sends
  /// only the read). A receipt goes only while some peer message up to
  /// the marker lacks one of its kind. A DM's goes to its peer; a
  /// group's (decision 218) goes over 1:1 to each member with such a
  /// message, so one that arrived late, stamped before the last receipt,
  /// still reaches its author.
  Future<void> _enqueueReceipt(
    String channelId,
    pb.ChatPayloadType type,
  ) async {
    // Decision 223: read receipts off, a 1:1 chat is only told delivered.
    if (type == pb.ChatPayloadType.TYPE_READ_RECEIPT &&
        isDmChannelId(channelId) &&
        !readReceipts.value) {
      type = pb.ChatPayloadType.TYPE_DELIVERY_RECEIPT;
    }
    final now = _clock.nowMs();
    final localUserId = _authClient.currentUserId;
    if (localUserId == null) return;
    final newest = await _store.latestPeerMessage(
      channelId: channelId,
      localUserId: localUserId,
    );
    if (newest == null) return;
    final marker = newest.serverTimestampMs;
    final read = type == pb.ChatPayloadType.TYPE_READ_RECEIPT;
    final unacked = '''
      channel_id = ? AND author_user_id != ? AND server_timestamp_ms <= ?
      AND message_state IN ('${MessageState.sent.wire}'
        ${read ? ", '${MessageState.delivered.wire}'" : ''})
      AND tombstoned = 0 AND content_type IS NOT '$kGroupEventType'
    ''';
    final authors = [
      for (final row in await _store.db.rawQuery(
          'SELECT DISTINCT author_user_id FROM messages WHERE $unacked',
          [channelId, localUserId, marker]))
        row['author_user_id'] as String
    ];
    if (authors.isEmpty) return;

    final group = !isDmChannelId(channelId);
    final targets = !group
        ? [(channelId, null)]
        : [for (final a in authors) (dmChannelId(localUserId, a), a)];
    for (final (channel, String? peer) in targets) {
      await _store.enqueueOutboundOp(OutboundOpRow(
        opId: _uuidGen.next(nowMs: now),
        transport: OpTransport.ws,
        kind: OpKind.chatPayload,
        restMethod: null,
        restPath: null,
        resourceId: channel,
        payload:
            _encodeReceipt(type, marker, groupId: group ? channelId : null),
        status: OpStatus.pending,
        attempts: 0,
        nextRetryAt: now,
        dispatchedAt: null,
        lastError: null,
        acknowledgedAt: null,
        createdAt: now,
        // A receipt doesn't target a local message row — the ACK just
        // deletes the op (scheduler's null-targetMessageId branch).
        targetMessageId: null,
        targetChannelId: channel,
        peer: peer,
      ));
    }
    // After the enqueue: a crash in between resends, never loses. A row
    // stored meanwhile by another author waits for the next receipt.
    await _store.db.rawUpdate(
      'UPDATE messages SET message_state = ? WHERE $unacked '
      'AND author_user_id IN (${List.filled(authors.length, '?').join(',')})',
      [
        (read ? MessageState.read : MessageState.delivered).wire,
        channelId,
        localUserId,
        marker,
        ...authors,
      ],
    );
    _scheduler.tickSoon();
  }

  /// Fire-and-forget typing indicator. Constructs an ephemeral envelope
  /// (no `outbound_ops` row, no retry, no ACK) and writes it directly
  /// to the WS. If the WS isn't connected the call is a no-op — the
  /// recipient's "is typing" indicator will time out on its own.
  void notifyTyping({
    required String channelId,
    required bool isTyping,
  }) {
    final localUserId = _authClient.currentUserId;
    if (localUserId == null || !typingIndicator.value) return;
    final now = _clock.nowMs();
    // localUserId is read only to gate the call (don't fire when
    // logged out — the embedded uuid_v7 user_id bits would be wrong).
    // It does not appear in the encoded payload — the server stamps
    // sender_user_id on the envelope at fanout.
    if (localUserId.isEmpty) return;
    final opId = _uuidGen.next(nowMs: now);
    final payload = _encodeTyping(isTyping: isTyping);
    // Encrypted like everything else (decision 188), but never worth
    // claiming keys or handing out a group key for: without that set up
    // the indicator is simply not sent. Trim 4: a DM names its peer even
    // on a typing frame. Fire-and-forget throughout.
    unawaited(() async {
      final peer = isDmChannelId(channelId)
          ? await _store.dmPeer(channelId, localUserId)
          : null;
      if (isDmChannelId(channelId) && peer == null) return;
      final crypto = this.crypto;
      final sealed = crypto == null
          ? payload
          : await crypto.sealTyping(
              opId: opId, channelId: channelId, peer: peer, payload: payload);
      if (sealed == null) return;
      _wsTransport.sendEphemeral(
        opId: opId,
        channelId: channelId,
        payload: sealed,
        peer: peer,
      );
    }()
        .catchError((Object _) {}));
  }

  /// Discover contacts from the server and cache locally.
  ///
  /// SHA-256-hashes each E.164 phone in [normalizedPhones] per
  /// AUTH_CONTRACT §7.2, calls `POST /v3.0/contacts/lookup`, then
  /// upserts each match into the local `contacts` table. Returns the
  /// full local contact list.
  ///
  /// If [normalizedPhones] is empty, returns the cached local list
  /// without firing a server call (the screen passes an empty list
  /// when contacts permission is denied or the address book has no
  /// phone numbers).
  /// The Vartalap user behind any of [normalizedPhones] (a shared
  /// contact card's numbers), via the same hashed lookup as
  /// [discoverContacts]; null if none of them is on Vartalap.
  Future<ContactRow?> findUserByPhone(
    List<String> normalizedPhones, {
    required String name,
  }) async {
    if (normalizedPhones.isEmpty) return null;
    final hashes = {
      for (final p in normalizedPhones) sha256.convert(utf8.encode(p)).toString(),
    };
    final known = await discoverContacts(
      normalizedPhones: normalizedPhones,
      contactBookNamesByPhone: {for (final p in normalizedPhones) p: name},
    );
    return known.where((c) => hashes.contains(c.phoneHash)).firstOrNull;
  }

  Future<List<ContactRow>> discoverContacts({
    List<String> normalizedPhones = const [],
    Map<String, String> contactBookNamesByPhone = const {},
  }) async {
    if (normalizedPhones.isEmpty) {
      return _store.fetchContacts();
    }
    // Hash each normalized phone, keeping a hash→name map so the
    // server's per-hash matches can recover the device-side label.
    final hashByName = <String, String>{};
    final hashes = normalizedPhones.map((p) {
      final h = sha256.convert(utf8.encode(p)).toString();
      final name = contactBookNamesByPhone[p];
      if (name != null && name.isNotEmpty) hashByName[h] = name;
      return h;
    }).toList();
    final now = _clock.nowMs();
    // Decision 208: only numbers not yet known to be on Vartalap, and a
    // miss only once its cooling period is over.
    final known = {
      for (final c in await _store.fetchContacts())
        if (c.phoneHash != null) c.phoneHash!,
    };
    await _store.setContactBookNamesByPhoneHash({
      for (final e in hashByName.entries)
        if (known.contains(e.key)) e.key: e.value,
    });
    final cooling = await _store.recentLookupMisses(
        now - kContactLookupCooldown.inMilliseconds);
    final unknown =
        hashes.toSet().difference(known).difference(cooling).toList();
    for (var i = 0; i < unknown.length; i += kContactLookupBatch) {
      final batch =
          unknown.sublist(i, min(i + kContactLookupBatch, unknown.length));
      final matches = await _authClient.lookupContacts(batch);
      for (final m in matches) {
        await _store.upsertContact(
          userId: m.userId,
          username: m.username,
          // AUTH_CONTRACT §7.2: a phone-hash match reveals user_id and
          // username, nothing else. Seeding display_name from the handle
          // would mask the §2.4 `@username` rung of the resolver.
          phoneHash: m.phoneHash,
          contactBookName: hashByName[m.phoneHash],
          nowMs: now,
        );
      }
      final found = {for (final m in matches) m.phoneHash};
      await _store.recordLookupMisses(
          batch.where((h) => !found.contains(h)), now);
    }
    return _store.fetchContacts();
  }

  /// Save contact (decision 153) — a name kept on this phone only.
  Future<void> saveContactName(String userId, String name) =>
      _store.setContactBookName(userId, name);

  /// `GET /v3.0/users/by-username/{username}` — AUTH_CONTRACT §7.6.
  ///
  /// The one network-bound discovery path for somebody who is not in
  /// the address book. Caches the resolved profile as a local contact
  /// row (no `contactBookName` — we have no address-book entry for
  /// them) and returns it, so the caller can open Contact info or start
  /// a DM straight away.
  ///
  /// Throws [AuthClientException]; `errorCode == 'USERNAME_KEY_REQUIRED'`
  /// means the handle exists but is gated by a 4-digit key (§4.5) and
  /// the caller should ask for one. A wrong key is indistinguishable
  /// from a nonexistent handle — both are a plain `USER_NOT_FOUND`.
  Future<ContactRow> findByUsername(String username, {String? key}) async {
    final profile = await _authClient.lookupByUsername(username, key: key);
    final userId = profile['user_id'] as String;
    final now = _clock.nowMs();
    final existing = (await _store.fetchContacts())
        .where((c) => c.userId == userId)
        .firstOrNull;
    await _store.upsertContact(
      userId: userId,
      username: profile['username'] as String?,
      displayName: profile['displayName'] as String?,
      avatarUrl: profile['avatarUrl'] as String?,
      statusText: profile['statusText'] as String?,
      // upsertContact is INSERT OR REPLACE — carry the address-book
      // fields forward so a handle lookup never erases them.
      phoneHash: existing?.phoneHash,
      contactBookName: existing?.contactBookName,
      nowMs: now,
    );
    return (await _store.fetchContacts())
        .firstWhere((c) => c.userId == userId);
  }

  /// Create a group channel locally with [creatorUserId] as owner and
  /// [memberUserIds] (creator excluded — server adds the creator
  /// implicitly per SYNC_PROTOCOL §11.3) as members. Returns channel_id.
  ///
  /// Local membership records both the creator (role `owner`) and every
  /// id in [memberUserIds] (role `member`) so a fresh subscribe to
  /// `watchMemberChannels` shows the new group for the creator. (Live
  /// observers attached during the call may see a transient empty
  /// emission — `insertChannelMember` does not notify, so the post-
  /// `insertChannel` emit JOINs an empty membership. In production the
  /// caller `pushReplacement`s into the chat screen so the Groups tab
  /// stream is re-subscribed before the user looks at it.)
  Future<String> createGroup({
    required String name,
    required String creatorUserId,
    required List<String> memberUserIds,
  }) async {
    final channelId = await createChannel(
      ownerUserId: creatorUserId,
      memberUserIds: memberUserIds,
      name: name,
    );

    final now = _clock.nowMs();
    await _store.insertChannelMember(
      channelId: channelId,
      userId: creatorUserId,
      role: 'owner',
      joinedAt: now,
    );
    // Decision 221: the others are invited, and members once they accept.
    for (final uid in memberUserIds) {
      await _store.putInvite(InviteRow(
        channelId: channelId,
        toUser: uid,
        fromUser: creatorUserId,
        createdAt: now,
      ));
    }
    await _store.insertGroupEvent(
      channelId: channelId,
      messageId: 'ge-$channelId',
      actorUserId: creatorUserId,
      event: GroupEvent(GroupEventKind.created, text: name),
      atMs: now,
    );
    if (memberUserIds.isNotEmpty) {
      await _store.insertGroupEvent(
        channelId: channelId,
        messageId: 'ge-$channelId-invited',
        actorUserId: creatorUserId,
        event: GroupEvent(GroupEventKind.invited, users: memberUserIds),
        atMs: now,
      );
    }
    return channelId;
  }

  /// Start or resume a DM with [peerUserId]. Returns the channel_id.
  ///
  /// Trim 4: the id is **derived** from the pair —
  /// `dmChannelId(localUserId, peerUserId)` — so this never talks to
  /// the network. There is no create op, no server-side row and no
  /// second id to reconcile: both sides compute the same channel
  /// offline, which is what makes "we both started this chat while
  /// offline" a non-event rather than a merge.
  ///
  /// All this does locally is make sure the projection rows exist so
  /// the chat list, the member list and the outbound peer lookup have
  /// something to read.
  Future<String> startDirectMessage({
    required String localUserId,
    required String peerUserId,
    required String peerName,
  }) async {
    final channelId = dmChannelId(localUserId, peerUserId);
    await _ensureDmChannel(
      channelId: channelId,
      localUserId: localUserId,
      peerUserId: peerUserId,
      peerName: peerName,
    );
    return channelId;
  }

  /// Idempotent local materialization of a derived DM channel.
  /// `INSERT OR IGNORE` semantics: re-opening an existing DM leaves its
  /// history, its unread count and its local flags alone.
  Future<void> _ensureDmChannel({
    required String channelId,
    required String localUserId,
    required String peerUserId,
    required String peerName,
  }) async {
    if (await _store.channelExists(channelId)) return;
    final now = _clock.nowMs();
    await _store.insertChannel(
      channelId: channelId,
      kind: 'one_to_one',
      ownerUserId: localUserId,
      createdAt: now,
      name: peerName,
    );
    await _store.insertChannelMember(
      channelId: channelId,
      userId: localUserId,
      role: 'owner',
      joinedAt: now,
    );
    await _store.insertChannelMember(
      channelId: channelId,
      userId: peerUserId,
      role: 'member',
      joinedAt: now,
    );
  }

  /// Wipe every message in [channelId] without removing the channel
  /// itself. The chat stays in the chat list with an empty preview
  /// (WhatsApp's Clear chat) until the next message fills it again.
  ///
  /// Safe for both DM and group channels. Used by "Clear history" in
  /// chat info and in the chat-list selection bar.
  Future<void> clearMessages(String channelId) =>
      _store.clearChannelMessages(channelId);

  /// Leave a group (decision 9/80): `DELETE /v3.0/channels/{id}/members/
  /// {selfUserId}`, for owners too — the server promotes the
  /// longest-standing admin (else the longest-standing member) and
  /// re-announces them as owner. Locally we stop being a member at once
  /// and the chat says "You left"; the chat and its history stay, read
  /// only (WhatsApp), until the user deletes it. A terminal reject puts
  /// us back, like any [removeMember].
  ///
  /// The server's `ChannelMemberRemoved` fanout reaches the remaining
  /// members; it skips the device that left.
  Future<void> leaveGroup(
    String channelId, {
    required String selfUserId,
  }) =>
      _channelMembershipOp(
        channelId: channelId,
        caller: 'leaveGroup',
        kind: OpKind.removeMember,
        method: 'DELETE',
        path: '/v3.0/channels/$channelId/members/$selfUserId',
        payload: const [],
        applyLocal: (opId) async {
          await _store.removeChannelMember(
            channelId: channelId,
            userId: selfUserId,
            removedAtMs: _clock.nowMs(),
          );
          await _ownGroupEvent(channelId, opId,
              GroupEvent(GroupEventKind.left, users: [selfUserId]));
        },
      );

  /// Delete a group for everyone (decision 9, owner only):
  /// `DELETE /v3.0/channels/{id}`. The server hard-deletes and fans
  /// `ChannelDeleted`; locally the channel is tombstoned now, the same
  /// write that fanout makes on every other member.
  Future<void> deleteGroup(String channelId) => _channelMembershipOp(
        channelId: channelId,
        caller: 'deleteGroup',
        kind: OpKind.deleteChannel,
        method: 'DELETE',
        path: '/v3.0/channels/$channelId',
        payload: const [],
        applyLocal: (_) => _store.deleteGroupLocal(channelId),
      );

  /// Promote or demote a member (decision 80):
  /// `PATCH /v3.0/channels/{id}/members/{user_id}` with
  /// `{role: "admin"|"member"}`. Owner and admins only — the server
  /// answers 403 otherwise, and a terminal reject puts the local row
  /// back (`ChatStore._rollbackMemberRole`).
  Future<void> setMemberRole({
    required String channelId,
    required String userId,
    required String role,
  }) =>
      _channelMembershipOp(
        channelId: channelId,
        caller: 'setMemberRole',
        kind: OpKind.setMemberRole,
        method: 'PATCH',
        path: '/v3.0/channels/$channelId/members/$userId',
        payload: utf8.encode(jsonEncode({'role': role})),
        applyLocal: (_) => _store.setMemberRoleLocal(
          channelId: channelId,
          userId: userId,
          role: role,
        ),
      );

  /// Add people to a group (owner and admins, decision 81):
  /// `POST /v3.0/channels/{id}/members`. Decision 221: they are invited
  /// and show as "Invited" until they accept; a terminal reject takes
  /// the invites back.
  Future<void> addMembers(String channelId, List<String> userIds) =>
      _channelMembershipOp(
        channelId: channelId,
        caller: 'addMembers',
        kind: OpKind.addMembers,
        method: 'POST',
        path: '/v3.0/channels/$channelId/members',
        payload: utf8.encode(jsonEncode({'members': userIds})),
        applyLocal: (opId) async {
          for (final userId in userIds) {
            await _store.putInvite(InviteRow(
              channelId: channelId,
              toUser: userId,
              fromUser: _authClient.currentUserId ?? '',
              createdAt: _clock.nowMs(),
            ));
          }
          await _ownGroupEvent(channelId, opId,
              GroupEvent(GroupEventKind.invited, users: userIds));
        },
      );

  /// Remove someone else from a group (owner and admins):
  /// `DELETE /v3.0/channels/{id}/members/{user_id}`. Leaving is
  /// [leaveGroup].
  Future<void> removeMember(String channelId, String userId) =>
      _channelMembershipOp(
        channelId: channelId,
        caller: 'removeMember',
        kind: OpKind.removeMember,
        method: 'DELETE',
        path: '/v3.0/channels/$channelId/members/$userId',
        payload: const [],
        applyLocal: (opId) async {
          await _store.removeChannelMember(
            channelId: channelId,
            userId: userId,
            removedAtMs: _clock.nowMs(),
          );
          await _ownGroupEvent(channelId, opId,
              GroupEvent(GroupEventKind.removed, users: [userId]));
        },
      );

  /// Rename a group (owner and admins): `PATCH /v3.0/channels/{id}`.
  Future<void> renameGroup(String channelId, String name) =>
      _channelMembershipOp(
        channelId: channelId,
        caller: 'renameGroup',
        kind: OpKind.editChannel,
        method: 'PATCH',
        path: '/v3.0/channels/$channelId',
        payload: utf8.encode(jsonEncode({'name': name})),
        applyLocal: (opId) async {
          await _store.applyChannelEdit(
            channelId: channelId,
            name: (value: name),
            editedAtMs: _clock.nowMs(),
          );
          await _ownGroupEvent(channelId, opId,
              GroupEvent(GroupEventKind.renamed, text: name));
        },
      );

  /// The shape all three group-membership writes share: refuse to touch
  /// a DM, enqueue the REST op, apply the local projection, kick the
  /// scheduler. Resolving the channel kind up front keeps the outbound
  /// queue clean even though the store methods re-validate.
  Future<void> _channelMembershipOp({
    required String channelId,
    required String caller,
    required String kind,
    required String method,
    required String path,
    required List<int> payload,
    required Future<void> Function(String opId) applyLocal,
  }) async {
    final rows = await _store.db.query(
      'channels',
      columns: const ['kind'],
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    if (rows.isEmpty) {
      // Channel already gone locally — nothing to do, no op to enqueue.
      return;
    }
    final channelKind = rows.single['kind'] as String;
    if (channelKind != 'group') {
      throw StateError(
        '$caller called on non-group channel ($channelKind). '
        'DM channels must not be deleted — clear messages instead.',
      );
    }

    final now = _clock.nowMs();
    final op = OutboundOpRow(
      opId: _uuidGen.next(nowMs: now),
      transport: OpTransport.rest,
      kind: kind,
      restMethod: method,
      restPath: path,
      resourceId: channelId,
      // RestTransport tolerates an empty payload — it sends just the
      // standard op_id / client_timestamp_ms envelope fields with no
      // endpoint-specific body.
      payload: payload,
      status: OpStatus.pending,
      attempts: 0,
      nextRetryAt: now,
      dispatchedAt: null,
      lastError: null,
      acknowledgedAt: null,
      createdAt: now,
      targetMessageId: null,
      targetChannelId: channelId,
    );

    await _store.enqueueOutboundOp(op);
    await applyLocal(op.opId);
    _scheduler.tickSoon();
  }

  /// The actor's own [GroupEvent] line: the server's fanout skips the
  /// device that acted, so nothing else will write it here. Keyed on
  /// the op, so a terminal reject can take it back out.
  Future<void> _ownGroupEvent(
    String channelId,
    String opId,
    GroupEvent event,
  ) =>
      _store.insertGroupEvent(
        channelId: channelId,
        messageId: 'ge-$opId',
        actorUserId: _authClient.currentUserId ?? '',
        event: event,
        atMs: _clock.nowMs(),
      );

  // --- connecting: invites, blocks, reports (decisions 219-221) ---------

  /// Set by `main.dart`: materialize a group just joined through the
  /// inbound receiver, which also fetches its members' profiles.
  Future<void> Function(String channelId, Map<String, dynamic> group)?
      adoptGroup;

  /// Mirror the server's connections, blocks and pending invites
  /// (SYNC_PROTOCOL §23) into the store. At every foreground login.
  Future<void> refreshConnections() async {
    final json = await _authClient.getConnections();
    final invites = [
      for (final i in (json['invites'] as List).cast<Map<String, dynamic>>())
        InviteRow(
          channelId: i['channel_id'] as String,
          toUser: i['to'] as String,
          fromUser: i['from'] as String,
          name: i['name'] as String?,
          createdAt: (i['created_at'] as num).toInt(),
        ),
    ];
    await _store.replaceConnections(
      connected: (json['connections'] as List).cast<String>(),
      blocked: (json['blocked'] as List).cast<String>(),
      invites: invites,
    );
    // An invite from someone this phone has never seen needs a name.
    final known = {for (final c in await _store.fetchContacts()) c.userId};
    for (final from in {for (final i in invites) i.fromUser}) {
      if (!known.contains(from)) await _fetchContact(from);
    }
  }

  Future<void> _fetchContact(String userId) async {
    try {
      final profile = await _authClient.getUser(userId);
      await _store.upsertContact(
        userId: userId,
        username: profile['username'] as String?,
        displayName: profile['displayName'] as String?,
        avatarUrl: profile['avatarUrl'] as String?,
        statusText: profile['statusText'] as String?,
        nowMs: _clock.nowMs(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('ChatService: profile of $userId failed: $e');
    }
  }

  /// Every pending invite this phone can see, oldest first.
  Stream<List<InviteRow>> watchInvites() =>
      _store.watchTables(const {'invites'}, _store.fetchInvites);

  /// Where we stand with [peerUserId]: connected, blocked, an invite
  /// either way.
  Stream<PeerLink> watchPeerLink(String peerUserId) => _store.watchTables(
      const {'invites', 'connections'},
      () => _store.peerLink(_authClient.currentUserId ?? '', peerUserId));

  /// Who we blocked (Settings › Privacy › Blocked).
  Stream<Set<String>> watchBlocked() =>
      _store.watchTables(const {'connections'}, _store.blockedUsers);

  /// Who we may invite to a group: our connections (decision 221).
  Future<Set<String>?> connectedUsers() => _store.connectedUsers();

  /// Invite [peerUserId] to chat (decision 219). Their chat with us shows
  /// "You invited …" and, until they answer, "Invite sent". Throws
  /// [AuthClientException]: 429 `invite_limit` past the cap.
  Future<void> sendInvite(String peerUserId) async {
    final self = _authClient.currentUserId!;
    final state = await _authClient.sendInvite(peerUserId);
    final channelId = dmChannelId(self, peerUserId);
    final now = _clock.nowMs();
    if (state == 'connected') {
      // they had invited us: inviting back accepted theirs
      await _store.removeInvites(channelId);
      await _store.setConnection(peerUserId, connected: true);
      await _dmLine(
          channelId, self, const GroupEvent(GroupEventKind.accepted));
      return;
    }
    await _store.putInvite(InviteRow(
      channelId: channelId,
      toUser: peerUserId,
      fromUser: self,
      createdAt: now,
    ));
    await _dmLine(channelId, self,
        GroupEvent(GroupEventKind.invited, users: [peerUserId]));
  }

  /// A line in a 1:1 chat this phone already has; once per kind.
  Future<void> _dmLine(
      String channelId, String actor, GroupEvent event) async {
    if (!await _store.channelExists(channelId)) return;
    final now = _clock.nowMs();
    await _store.insertGroupEvent(
      channelId: channelId,
      messageId: 'ge-${event.kind.name}-$channelId-$now',
      actorUserId: actor,
      event: event,
      atMs: now,
    );
  }

  /// Accept [invite]; returns the chat to open. A 1:1 one connects us; a
  /// group's makes us a member. Throws [AuthClientException]; a 404 means
  /// the invite is gone (taken back), and it goes from here too.
  Future<String> acceptInvite(InviteRow invite) async {
    final self = _authClient.currentUserId!;
    final Map<String, dynamic> json;
    try {
      json = await _authClient.acceptInvite(invite.channelId);
    } on AuthClientException catch (e) {
      if (e.statusCode == 404) {
        await _store.removeInvites(invite.channelId, toUser: self);
      }
      rethrow;
    }
    await _store.removeInvites(invite.channelId, toUser: self);
    if (invite.isGroup) {
      await adoptGroup?.call(invite.channelId, json);
      await _dmLine(invite.channelId, self,
          GroupEvent(GroupEventKind.added, users: [self]));
      return invite.channelId;
    }
    await _store.setConnection(invite.fromUser, connected: true);
    final peer = (await _store.fetchContacts())
        .where((c) => c.userId == invite.fromUser)
        .firstOrNull;
    final channelId = await startDirectMessage(
      localUserId: self,
      peerUserId: invite.fromUser,
      peerName: peer?.displayLabel ?? '',
    );
    await _dmLine(channelId, self, const GroupEvent(GroupEventKind.accepted));
    return channelId;
  }

  /// Decline [invite]; [block] also blocks whoever sent it.
  Future<void> declineInvite(InviteRow invite, {bool block = false}) async {
    await _authClient.declineInvite(invite.channelId, block: block);
    await _store.removeInvites(invite.channelId, toUser: invite.toUser);
    if (block) await _store.setConnection(invite.fromUser, blocked: true);
  }

  /// Take back our invite of [userId] into [channelId] (a group's, or the
  /// pair's DM id).
  Future<void> cancelInvite(String channelId, String userId) async {
    await _authClient.cancelInvite(channelId, userId);
    await _store.removeInvites(channelId, toUser: userId);
  }

  /// Block or unblock [userId]: the server drops their 1:1 messages and
  /// invites to us. Groups are not affected.
  Future<void> setBlocked(String userId, bool blocked) async {
    await _authClient.setBlocked(userId, blocked);
    await _store.setConnection(userId, blocked: blocked);
  }

  /// Report [userId] (WhatsApp's Report). With [channelId], the chat's
  /// last 5 messages go along, as this phone shows them: the server
  /// cannot read the chat. [block]: Report and block.
  Future<void> report(
    String userId, {
    String? channelId,
    bool block = false,
  }) async {
    final messages = channelId == null
        ? const <MessageRow>[]
        : (await _store.fetchChannelMessages(channelId, limit: 50))
            .where((m) => m.contentType != kGroupEventType && !m.tombstoned)
            .take(5)
            .toList();
    // "Report and block" blocks even when the report cannot go (a 429
    // past the daily limit, no network): the block is what protects.
    try {
      await _authClient.report(userId, [
        for (final m in messages.reversed)
          {
            'author': m.authorUserId,
            'body': (m.body ?? '').length > 4096
                ? m.body!.substring(0, 4096)
                : m.body ?? '',
            if (m.contentType != null) 'content_type': m.contentType,
            'sent_at': m.displayTimestampMs,
          },
      ]);
    } finally {
      if (block) await setBlocked(userId, true);
    }
  }

  /// Active members of [channelId], joined with the local contact row
  /// where one exists. Powers the chat-info member list.
  Future<List<ChannelMemberRow>> fetchChannelMembers(String channelId) =>
      _store.fetchChannelMembers(channelId);

  /// One-shot read of the channels [userId] is a member of, optionally
  /// filtered by [kind]. The reactive variant is [watchMemberChannels].
  Future<List<ChannelListEntry>> fetchMemberChannels({
    required String userId,
    String? kind,
  }) =>
      _store.fetchMemberChannels(userId: userId, kind: kind);

  /// Substring search restricted to [channelId]. Powers the chat
  /// screen's inline search.
  Future<List<MessageRow>> searchInChannel({
    required String channelId,
    required String query,
    int limit = 200,
  }) =>
      _store.searchChannelMessages(
        channelId: channelId,
        query: query,
        limit: limit,
      );

  /// Substring search over every chat. Powers the home screen's search.
  Future<List<MessageRow>> searchMessages(String query) =>
      _store.searchMessages(query: query);

  /// Channels the current user is an active member of, filtered by
  /// `kind`. Powers the Groups tab in the new-chat picker.
  Stream<List<ChannelListEntry>> watchMemberChannels({
    required String userId,
    String? kind,
  }) =>
      _store.watchMemberChannels(userId: userId, kind: kind);

  /// Reactive failure surface — SPIKE_B_SYNC.md §10. The UI can bind a
  /// toast or inline retry affordance to this.
  Stream<List<OutboundOpRow>> watchFailures() => failureStream(_store);

  // --- Message actions — V3_RELEASE_PLAN §4.3 / §4.4 --------------------

  /// One outbound WS op carrying a ChatPayload. [kind] is local-only
  /// bookkeeping (see [OpKind.messageEdit]); the wire shape is the same
  /// for every type.
  /// [madeAtMs]: when the user acted, if earlier than [nowMs]; the op id
  /// carries it (a delete is judged by it, decision 222).
  OutboundOpRow _chatOp({
    required String kind,
    required String channelId,
    required String messageId,
    required Uint8List payload,
    required int nowMs,
    int? madeAtMs,
  }) =>
      OutboundOpRow(
        opId: _uuidGen.next(nowMs: madeAtMs ?? nowMs),
        transport: OpTransport.ws,
        kind: kind,
        restMethod: null,
        restPath: null,
        resourceId: channelId,
        payload: payload,
        status: OpStatus.pending,
        attempts: 0,
        nextRetryAt: nowMs,
        dispatchedAt: null,
        lastError: null,
        acknowledgedAt: null,
        createdAt: nowMs,
        targetMessageId: messageId,
        targetChannelId: channelId,
      );

  /// Toggle [emoji] from [userId] on [messageId] — REACTION_ADD when
  /// [add], REACTION_REMOVE otherwise. Local row first, op second, one
  /// transaction. Non-destructive, so no undo window (decision 11).
  Future<void> reactToMessage({
    required String channelId,
    required String messageId,
    required String userId,
    required String emoji,
    required bool add,
  }) async {
    final now = _clock.nowMs();
    await _store.enqueueReaction(
      messageId: messageId,
      userId: userId,
      emoji: emoji,
      add: add,
      nowMs: now,
      op: _chatOp(
        kind: OpKind.messageReaction,
        channelId: channelId,
        messageId: messageId,
        payload: _encodeChatOp(
          type: add
              ? pb.ChatPayloadType.TYPE_REACTION_ADD
              : pb.ChatPayloadType.TYPE_REACTION_REMOVE,
          messageId: messageId,
          emoji: emoji,
        ),
        nowMs: now,
      ),
    );
    _scheduler.tickSoon();
  }

  /// Replace the body of one of the local user's own messages —
  /// MESSAGE_UPDATE. Recipients drop it unless we are the author
  /// (SYNC_PROTOCOL §6a.3), so the caller must gate the UI on
  /// authorship too; this is the second line of defence, not the first.
  ///
  /// An UPDATE replaces body, content type *and* attachments
  /// (v3-chat-payload.proto), so a caption edit re-sends the
  /// attachments it keeps. Until our CREATE is ACKed those still point
  /// at a local file, so an attachment message is not editable yet.
  Future<void> editMessage({
    required String channelId,
    required String messageId,
    required String newBody,
  }) async {
    final row = await _store.fetchMessage(messageId);
    final attachments = row?.attachments == null
        ? const <pb.Attachment>[]
        : pb.ChatPayload.fromBuffer(row!.attachments!).attachments;
    if (attachments.isNotEmpty && row!.serverTimestampMs == null) {
      throw ArgumentError('Wait for the upload to finish before editing.');
    }
    final now = _clock.nowMs();
    await _store.enqueueMessageEdit(
      messageId: messageId,
      newBody: newBody,
      nowMs: now,
      op: _chatOp(
        kind: OpKind.messageEdit,
        channelId: channelId,
        messageId: messageId,
        payload: _encodeChatOp(
          type: pb.ChatPayloadType.TYPE_MESSAGE_UPDATE,
          messageId: messageId,
          body: newBody,
          contentType: attachments.isEmpty ? null : row!.contentType,
          attachments: attachments,
        ),
        nowMs: now,
      ),
    );
    _scheduler.tickSoon();
  }

  /// Decision 222: "Delete for everyone" fits [m] — the user's own, not
  /// deleted, and not yet sent or sent less than
  /// [kDeleteForEveryoneWindow] ago by this phone's clock. Receivers judge
  /// the delete by the same two times (SYNC_PROTOCOL §20.1).
  bool canDeleteForEveryone(MessageRow m, String? selfUserId) {
    if (m.authorUserId != selfUserId || m.tombstoned) return false;
    final sent = m.serverTimestampMs;
    return sent == null ||
        _clock.nowMs() - sent < kDeleteForEveryoneWindow.inMilliseconds;
  }

  /// "Delete for me" (decision 222): any message, gone from this phone
  /// only. Nothing is sent and there is nothing to undo.
  Future<void> deleteForMe(List<String> messageIds) =>
      _store.deleteMessagesLocal(messageIds);

  StreamSubscription<Set<String>>? _expirySub;
  Timer? _expiryTimer;
  Timer? _rearm;

  /// Decision 222: timed messages leave this phone when their time is up.
  /// Deletes what is due now, then keeps one timer armed for the next,
  /// re-armed a second after messages change (once per burst: a pull
  /// writes hundreds). Started per account by `main.dart`; [stopExpiry]
  /// before the store closes.
  void startExpiry() {
    _expirySub ??= _store.tableChanges
        .where((t) => t.contains('messages'))
        .listen((_) => _rearm ??= Timer(const Duration(seconds: 1), () {
              _rearm = null;
              _armExpiry();
            }));
    unawaited(_sweepExpired());
  }

  /// Whether the timed-message sweeper is running ([startExpiry]).
  @visibleForTesting
  bool get expiryRunning => _expirySub != null;

  Future<void> stopExpiry() async {
    await _expirySub?.cancel();
    _expirySub = null;
    _rearm?.cancel();
    _rearm = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  Future<void> _sweepExpired() async {
    final self = _authClient.currentUserId;
    if (self == null || _expirySub == null) return;
    try {
      await _store.deleteExpiredMessages(
          nowMs: _clock.nowMs(), localUserId: self);
    } catch (e) {
      // Not re-armed: the next change to messages tries again.
      // ignore: avoid_print
      print('ChatService: timed message sweep failed: $e');
      return;
    }
    await _armExpiry();
  }

  Future<void> _armExpiry() async {
    if (_expirySub == null) return;
    final int? next;
    try {
      next = await _store.nextExpiryMs();
    } catch (_) {
      return; // the store closed under us
    }
    _expiryTimer?.cancel();
    if (next == null || _expirySub == null) return;
    _expiryTimer = Timer(
        Duration(milliseconds: max(0, next - _clock.nowMs())), _sweepExpired);
  }

  /// Decision 222: [messageId]'s versions, newest (current) first.
  Future<List<MessageVersion>> messageVersions(String messageId) =>
      _store.fetchMessageVersions(messageId);

  /// Decision 11 — delete for everyone, with a [undoWindow] during
  /// which nothing has been sent. The caller is responsible for calling
  /// [commitDelete] when the window elapses (or [undoDelete] before
  /// that); [sweepExpiredDeletes] is the backstop for a caller that
  /// never got the chance.
  Future<void> deleteMessage({
    required String messageId,
    Duration undoWindow = const Duration(seconds: 5),
  }) async {
    final now = _clock.nowMs();
    await _store.beginTombstone(
      messageId: messageId,
      pendingUntilMs: now + undoWindow.inMilliseconds,
      nowMs: now,
    );
  }

  /// Undo inside the window. Enqueues nothing, and cancels the delete
  /// that [commitDelete] would otherwise have sent.
  Future<void> undoDelete(String messageId) =>
      _store.undoTombstone(messageId: messageId, nowMs: _clock.nowMs());

  /// The window elapsed — enqueue MESSAGE_DELETE. No-op if an Undo got
  /// there first. Returns true iff an op was enqueued.
  Future<bool> commitDelete({
    required String channelId,
    required String messageId,
  }) async {
    final now = _clock.nowMs();
    // Receivers judge a delete by its op id's time (decision 222): one
    // committed late (the app was killed in the window) still carries
    // the window's end, not the commit's.
    final until = (await _store.fetchMessage(messageId))?.tombstonePendingUntil;
    final committed = await _store.commitTombstone(
      messageId: messageId,
      op: _chatOp(
        kind: OpKind.messageDelete,
        channelId: channelId,
        messageId: messageId,
        payload: _encodeChatOp(
          type: pb.ChatPayloadType.TYPE_MESSAGE_DELETE,
          messageId: messageId,
        ),
        nowMs: now,
        madeAtMs: until == null ? null : min(now, until),
      ),
    );
    if (committed) _scheduler.tickSoon();
    return committed;
  }

  /// Commit every delete in [channelId] whose window elapsed while
  /// nobody was watching (screen closed, app killed). Called on chat
  /// open so a tombstone can never strand un-enqueued.
  Future<void> sweepExpiredDeletes(String channelId) async {
    for (final messageId in await _store.expiredTombstones(
      channelId: channelId,
      nowMs: _clock.nowMs(),
    )) {
      await commitDelete(channelId: channelId, messageId: messageId);
    }
  }

  /// SPIKE_B_SYNC.md §10 — user tapped Retry on a failed op. Clones it
  /// into a fresh pending op (new op_id, so the server treats it as a
  /// new intent) and dismisses the failed row.
  Future<void> retryFailedOp(String opId) async {
    final now = _clock.nowMs();
    await _store.manualRetry(
      failedOpId: opId,
      newOpId: _uuidGen.next(nowMs: now),
      nowMs: now,
    );
    _scheduler.tickSoon();
  }

  /// User saw the failure (toast shown) — stop re-reporting it.
  Future<void> dismissFailure(String opId) =>
      _store.acknowledgeFailure(opId: opId, nowMs: _clock.nowMs());

  // --- local-only chat settings ------------------------------------------
  //
  // Pin, mute and delete-chat are device-local metadata
  // (V3_ARCHITECTURE decision 3 offline matrix). None of them enqueues
  // an outbound op, so none of them can fail or need a connection —
  // which is why they have no error path and no "needs a connection"
  // affordance in the UI.

  /// Pin [channelId] to the top of the chat list, or unpin it.
  Future<void> setPinned(String channelId, bool pinned) =>
      _store.setChannelPinned(channelId, pinned);

  /// Mute [channelId] until [untilMs] (epoch ms). `null` unmutes;
  /// [kMuteAlways] is the sheet's "Always" option.
  ///
  /// The wake stays content-free and ungated; the phone skips muted
  /// chats when it builds notifications from the store
  /// (`MessageNotifications`). Also drives the outline unread badge and
  /// the group-info mute bar.
  Future<void> setMuted(String channelId, int? untilMs) =>
      _store.setChannelMuted(channelId, untilMs);

  /// "Delete chat" — local-only, and not "leave group". Erases history
  /// and drops the row from Chats; membership is untouched, the group
  /// keeps showing under Groups, and the next message brings the chat
  /// back. See [leaveGroup] for the server-op counterpart.
  Future<void> deleteChat(String channelId) =>
      _store.deleteChatLocal(channelId);

  /// One channel plus its local settings — powers the group-info
  /// header. Null when the channel is not in the local store.
  Future<ChannelListEntry?> fetchChannel(String channelId) =>
      _store.fetchChannel(channelId);

  /// Photos and videos in [channelId], newest first — the "Media" tab
  /// of "Media, links and docs".
  Future<List<MessageRow>> fetchMedia(String channelId) =>
      _store.fetchChannelMedia(channelId);

  /// Documents in [channelId] (no media, no voice notes), newest first
  /// — the "Docs" tab.
  Future<List<MessageRow>> fetchFiles(String channelId) =>
      _store.fetchChannelFiles(channelId);

  /// Messages and captions in [channelId] carrying an http(s) URL,
  /// newest first — the "Links" tab.
  Future<List<MessageRow>> fetchLinks(String channelId) =>
      _store.fetchChannelLinks(channelId);

  /// Secure messages in [channelId], newest first — the "Secure" tab.
  Future<List<MessageRow>> fetchSecure(String channelId) =>
      _store.fetchChannelSecure(channelId);

  /// Star or unstar messages — local-only, like pin and mute.
  Future<void> setStarred(List<String> messageIds, bool starred) =>
      _store.setStarred(messageIds, starred, _clock.nowMs());

  /// Starred messages in every chat, newest star first.
  Stream<List<StarredMessage>> watchStarredMessages() =>
      _store.watchStarredMessages();

  // --- attachments and photos — V3_RELEASE_PLAN §4.2 ---------------------
  //
  // Everything here is local-first in the same sense as [sendMessage]:
  // the row (or the avatar) points at the picked file on disk the
  // instant the user picks it, and an `asset_upload` op swaps in the
  // media-ms fileId once the bytes are up. The upload is a real op, so
  // it retries, backs off, and dead-letters like anything else.

  /// Wire the asset client, cache, and upload adapter together. Called
  /// from the constructor because `main.dart` has already built (and
  /// started) the scheduler by then — see [SyncScheduler.assetTransport].
  void _installAssetPipeline() {
    final client = AssetClient(
      baseUrl: _authClient.baseUrl,
      auth: _authClient,
      httpClient: _authClient.httpClient,
    );
    assets = AssetCache(client: client);
    AssetCache.instance = assets;
    _scheduler.assetTransport = AssetUploadTransport(
      client: client,
      network: _wsTransport,
      onUploaded: _onAssetUploaded,
      onProgress: assets.reportUpload,
      // Off the UI isolate: about 40 ms a MB in pure Dart.
      seal: (plain) => Isolate.run(() {
        final (:key, :sealed) = sealAttachment(plain);
        return (
          key: key,
          sealed: sealed,
          md5: Uint8List.fromList(md5.convert(sealed).bytes),
        );
      }),
    );
  }

  /// `messages.attachments` for one file: a `ChatPayload` carrying only
  /// the repeated field, the same shape InboundReceiver writes.
  static Uint8List _encodeAttachments(Map<String, dynamic> spec, String url) =>
      pb.ChatPayload(
        attachments: [
          pb.Attachment(
            url: url,
            mimeType: spec['mime'] as String,
            sizeBytes: fixnum.Int64(spec['size'] as int),
            filename: spec['name'] as String? ?? '',
            width: spec['width'] as int? ?? 0,
            height: spec['height'] as int? ?? 0,
            durationMs: spec['durationMs'] as int? ?? 0,
            thumbnail: spec['thumb'] == null
                ? null
                : base64Decode(spec['thumb'] as String),
          ),
        ],
      ).writeToBuffer();

  /// The message's `content_type`: the file's type, or [kVoiceNoteType]
  /// for a recording. Ops queued before the key existed have only `mime`.
  static String _messageType(Map<String, dynamic> spec) =>
      spec['contentType'] as String? ?? spec['mime'] as String;

  /// MESSAGE_CREATE carrying an attachment. Separate from
  /// [_encodeChatPayload] only because `content_type` is the file's
  /// type here, not `text/plain`.
  static Uint8List _encodeAttachmentCreate({
    required String messageId,
    required Map<String, dynamic> spec,
    required String url,
  }) =>
      pb.ChatPayload(
        version: 1,
        type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
        messageId: uuidBytes(messageId),
        body: spec['body'] as String? ?? '',
        contentType: _messageType(spec),
        attachments: pb.ChatPayload.fromBuffer(_encodeAttachments(spec, url))
            .attachments,
        replyToMessageId: spec['replyTo'] == null
            ? null
            : uuidBytes(spec['replyTo'] as String),
      ).writeToBuffer();

  OutboundOpRow _uploadOp({
    required Map<String, dynamic> spec,
    required String resourceId,
    required String? messageId,
    required String? channelId,
    required int nowMs,
  }) =>
      OutboundOpRow(
        opId: _uuidGen.next(nowMs: nowMs),
        transport: OpTransport.asset,
        kind: OpKind.assetUpload,
        restMethod: null,
        restPath: null,
        // Deliberately NOT the channel: the scheduler runs one op per
        // resource at a time, and a long upload must not hold up the
        // channel's other messages behind it.
        resourceId: resourceId,
        payload: utf8.encode(jsonEncode(spec)),
        status: OpStatus.pending,
        attempts: 0,
        nextRetryAt: nowMs,
        dispatchedAt: null,
        lastError: null,
        acknowledgedAt: null,
        createdAt: nowMs,
        targetMessageId: messageId,
        targetChannelId: channelId,
      );

  /// Send [path] as an attachment. The file must already live somewhere
  /// durable — use [AssetCache.importPicked] on whatever the picker
  /// returns, because the picker's temp copy can be swept before the
  /// upload runs. [voiceNote] marks a recording made in the app
  /// ([kVoiceNoteType]); any other audio goes as an audio file.
  /// [thumbnail]: a video's first frame, a small JPEG (SYNC_PROTOCOL §25.4).
  ///
  /// Returns the new message_id.
  Future<String> sendAttachment({
    required String channelId,
    required String authorUserId,
    required String path,
    String? caption,
    String? replyToMessageId,
    int width = 0,
    int height = 0,
    int durationMs = 0,
    bool voiceNote = false,
    Uint8List? thumbnail,
  }) async {
    final now = _clock.nowMs();
    final messageId = _uuidGen.next(nowMs: now);
    final file = File(path);
    final size = await file.length();
    if (size + sealedAttachmentOverhead > AssetClient.maxUploadBytes) {
      throw ArgumentError(
        'Attachment is ${size ~/ (1024 * 1024)} MB; the limit is '
        '${AssetClient.maxUploadBytes ~/ (1024 * 1024)} MB.',
      );
    }
    final spec = <String, dynamic>{
      'then': 'message',
      'path': path,
      'ext': extForPath(path),
      'mime': mimeForPath(path),
      if (voiceNote) 'contentType': kVoiceNoteType,
      'size': size,
      'name': path.split('/').last,
      'category': 'message',
      'width': width,
      'height': height,
      'durationMs': durationMs,
      if (thumbnail != null) 'thumb': base64Encode(thumbnail),
      'body': caption ?? '',
      if (replyToMessageId != null) 'replyTo': replyToMessageId,
      // Decisions 188 and 190: sealed with a key derived from the file at
      // upload; it travels in the url fragment inside the encrypted
      // message, never to the server.
      'seal': true,
    };

    // The bubble points at the local file until the upload lands, so a
    // photo is visible in the thread the moment it is picked.
    final message = MessageRow(
      messageId: messageId,
      channelId: channelId,
      authorUserId: authorUserId,
      body: caption,
      contentType: _messageType(spec),
      replyToMessageId: replyToMessageId,
      clientTimestampMs: now,
      serverTimestampMs: null,
      state: MessageState.pending,
      stateUpdatedAt: now,
      isEdited: false,
      lastEditMs: null,
      tombstoned: false,
      tombstonePendingUntil: null,
      attachments: _encodeAttachments(spec, path),
    );

    await _store.enqueueLocalMessage(
      message: message,
      op: _uploadOp(
        spec: spec,
        resourceId: 'asset:$messageId',
        messageId: messageId,
        channelId: channelId,
        nowMs: now,
      ),
      nowMs: now,
    );
    _scheduler.tickSoon();
    return messageId;
  }

  /// Set the signed-in user's photo. Shows immediately (local path),
  /// then becomes the fileId and a `PATCH /v3.0/users/me` once uploaded
  /// — whose `ProfileEdited` fanout tells everyone we share a channel
  /// with (AUTH_CONTRACT §4.5, SYNC_PROTOCOL §10.2).
  Future<void> setOwnAvatar(String path) =>
      _enqueueAvatarUpload(path: path, then: 'profile', channelId: null);

  /// Same for a group photo — `PATCH /v3.0/channels/{id}`, fanned out
  /// as `ChannelEdited`.
  Future<void> setChannelAvatar({
    required String channelId,
    required String path,
    bool announce = true,
  }) async {
    await _store.setChannelAvatar(channelId, path);
    if (announce) {
      final now = _clock.nowMs();
      await _store.insertGroupEvent(
        channelId: channelId,
        messageId: 'ge-${_uuidGen.next(nowMs: now)}',
        actorUserId: _authClient.currentUserId ?? '',
        event: const GroupEvent(GroupEventKind.photo, text: 'set'),
        atMs: now,
      );
    }
    await _enqueueAvatarUpload(
      path: path,
      then: 'channel',
      channelId: channelId,
    );
  }

  Future<void> _enqueueAvatarUpload({
    required String path,
    required String then,
    required String? channelId,
  }) async {
    final now = _clock.nowMs();
    final size = await File(path).length();
    if (then == 'profile') await _writeOwnAvatar(path);
    await _store.enqueueOutboundOp(_uploadOp(
      spec: {
        'then': then,
        'path': path,
        'ext': extForPath(path),
        'mime': mimeForPath(path),
        'size': size,
        'name': path.split('/').last,
        'category': 'profile',
      },
      resourceId: 'asset:$path',
      messageId: null,
      channelId: channelId,
      nowMs: now,
    ));
    _scheduler.tickSoon();
  }

  /// The upload finished: [fileId] is now a real media-ms object, so
  /// whatever was waiting on it can go out. Runs before the upload op's
  /// own ACK is processed, so the follow-up op is durable by the time
  /// the upload op is retired.
  Future<void> _onAssetUploaded(
      String opId, String fileId, Uint8List? key) async {
    final op = await _store.fetchOutboundOp(opId);
    if (op == null) return;
    final spec = jsonDecode(utf8.decode(op.payload)) as Map<String, dynamic>;
    final url = key == null ? fileId : attachmentUrl(fileId, key);
    // The bytes are already in memory under the local path — keep them
    // so the bubble doesn't re-download what it just uploaded.
    assets.rekey(spec['path'] as String, url);
    assets.reportUpload(spec['path'] as String, null);
    final now = _clock.nowMs();

    switch (spec['then'] as String?) {
      case 'message':
        final messageId = op.targetMessageId!;
        final channelId = op.targetChannelId!;
        await _store.setMessageAttachments(
          messageId: messageId,
          attachments: _encodeAttachments(spec, url),
        );
        await _store.enqueueOutboundOp(OutboundOpRow(
          opId: _uuidGen.next(nowMs: now),
          transport: OpTransport.ws,
          kind: OpKind.chatPayload,
          restMethod: null,
          restPath: null,
          resourceId: channelId,
          payload: _encodeAttachmentCreate(
            messageId: messageId,
            spec: spec,
            url: url,
          ),
          status: OpStatus.pending,
          attempts: 0,
          nextRetryAt: now,
          dispatchedAt: null,
          lastError: null,
          acknowledgedAt: null,
          createdAt: now,
          targetMessageId: messageId,
          targetChannelId: channelId,
        ));
      case 'profile':
        await _writeOwnAvatar(fileId);
        await _store.enqueueOutboundOp(_restOp(
          kind: OpKind.editProfile,
          method: 'PATCH',
          path: '/v3.0/users/me',
          resourceId: 'me',
          channelId: null,
          body: {'avatarUrl': fileId},
          nowMs: now,
        ));
      case 'channel':
        final channelId = op.targetChannelId!;
        await _store.setChannelAvatar(channelId, fileId);
        await _store.enqueueOutboundOp(_restOp(
          kind: OpKind.editChannel,
          method: 'PATCH',
          path: '/v3.0/channels/$channelId',
          resourceId: channelId,
          channelId: channelId,
          // §11.3 spells it snake_case; `avatarUrl` is a 400 there.
          body: {'avatar_url': fileId},
          nowMs: now,
        ));
    }
    _scheduler.tickSoon();
  }

  OutboundOpRow _restOp({
    required String kind,
    required String method,
    required String path,
    required String resourceId,
    required String? channelId,
    required Map<String, dynamic> body,
    required int nowMs,
  }) =>
      OutboundOpRow(
        opId: _uuidGen.next(nowMs: nowMs),
        transport: OpTransport.rest,
        kind: kind,
        restMethod: method,
        restPath: path,
        resourceId: resourceId,
        payload: utf8.encode(jsonEncode(body)),
        status: OpStatus.pending,
        attempts: 0,
        nextRetryAt: nowMs,
        dispatchedAt: null,
        lastError: null,
        acknowledgedAt: null,
        createdAt: nowMs,
        targetMessageId: null,
        targetChannelId: channelId,
      );

  /// Own avatar, local copy. Not in `contacts` — that table is other
  /// people, and a self row would show up in the new-chat picker.
  ///
  /// ponytail: `shared_preferences`, because the one place that owns
  /// own-profile persistence (`AuthService`) writes secure storage and
  /// an avatar pointer is not a secret. Move it there if own-profile
  /// fields ever need to be read atomically together.
  ///
  /// Per account, as the database is (AUTH_CONTRACT §8.4): the next
  /// account signing in on this phone must not wear this one's photo.
  String get _ownAvatarKey => 'v3.avatarUrl.${_authClient.currentUserId}';

  /// Before per-account databases there was one key; it was whoever
  /// was signed in, which is who still is on the first read after the
  /// upgrade.
  static const String _legacyOwnAvatarKey = 'v3.avatarUrl';

  Future<void> _writeOwnAvatar(String value) async {
    try {
      (await SharedPreferences.getInstance())
          .setString(_ownAvatarKey, value);
    } catch (_) {
      // No platform channel (widget tests) — the avatar just isn't
      // remembered across restarts there.
    }
  }

  /// The signed-in user's photo: a local path until the upload lands,
  /// then the media-ms fileId. Null when they have never set one.
  Future<String?> ownAvatarUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_legacyOwnAvatarKey);
      if (legacy != null) {
        await prefs.setString(_ownAvatarKey, legacy);
        await prefs.remove(_legacyOwnAvatarKey);
      }
      return prefs.getString(_ownAvatarKey);
    } catch (_) {
      return null;
    }
  }
}

/// "Always" in the mute sheet — a `muted_until_ms` far enough out that
/// it never elapses, so the same `until > now` comparison covers every
/// mute option and no "muted forever" special case is needed.
const int kMuteAlways = 253402300800000; // 9999-01-01T00:00:00Z

/// Top-level helper so UI code doesn't need to import
/// `package:vartalap_sync` directly for the failure stream.
Stream<List<OutboundOpRow>> failureStream(ChatStore store) =>
    watchFailures(store);
