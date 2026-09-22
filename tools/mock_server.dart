/// Vartalap v3 mock server for golden-path testing.
///
/// Serves REST (auth, channels) and WebSocket (chat ops) on a single
/// port. State is held in memory but persisted to a JSON file across
/// restarts so a server bounce does not log the user out. OTP auto-
/// accepts any 6-digit code.
///
/// Usage:
///   dart run tools/mock_server.dart [--port 9777] [--seed-peer] \
///                                   [--state-file PATH]
///
/// Default state file: tools/.mock_state.json (next to this script).
/// Use --state-file=- to disable persistence (back to pure in-memory).
///
/// Then run the app:
///   flutter run --dart-define=API_URL=http://10.0.2.2:9777 \
///               --dart-define=WS_URL=ws://10.0.2.2:9777/wss
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:vartalap_proto/vartalap_proto.dart' as pb;

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

class UserRecord {
  final String userId;
  final String phone;
  String? username;

  /// AUTH_CONTRACT §4.5 optional 4-digit discovery key. Stored in the
  /// clear — this is a mock; the real server stores a hash (§4.5).
  /// Never echoed by any response.
  String? usernameKey;
  String? displayName;
  String? avatarUrl;
  String? statusText;
  final int createdAt;

  UserRecord({
    required this.userId,
    required this.phone,
    required this.createdAt,
  });

  Map<String, dynamic> toProfileJson() => {
        'user_id': userId,
        'username': username,
        'phone': phone,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'statusText': statusText,
        'createdAt': createdAt,
      };

  Map<String, dynamic> toPublicJson() => {
        'user_id': userId,
        'username': username,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'statusText': statusText,
      };

  Map<String, dynamic> toPersistJson() => {
        'userId': userId,
        'phone': phone,
        'username': username,
        'usernameKey': usernameKey,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'statusText': statusText,
        'createdAt': createdAt,
      };

  static UserRecord fromPersistJson(Map<String, dynamic> j) => UserRecord(
        userId: j['userId'] as String,
        phone: j['phone'] as String,
        createdAt: j['createdAt'] as int,
      )
        ..username = j['username'] as String?
        ..usernameKey = j['usernameKey'] as String?
        ..displayName = j['displayName'] as String?
        ..avatarUrl = j['avatarUrl'] as String?
        ..statusText = j['statusText'] as String?;
}

class SessionRecord {
  final String accesskey;
  final String refreshToken;
  final String userId;
  final String deviceId;
  final int accesskeyExpiresAt;
  final int refreshTokenExpiresAt;

  const SessionRecord({
    required this.accesskey,
    required this.refreshToken,
    required this.userId,
    required this.deviceId,
    required this.accesskeyExpiresAt,
    required this.refreshTokenExpiresAt,
  });

  Map<String, dynamic> toPersistJson() => {
        'accesskey': accesskey,
        'refreshToken': refreshToken,
        'userId': userId,
        'deviceId': deviceId,
        'accesskeyExpiresAt': accesskeyExpiresAt,
        'refreshTokenExpiresAt': refreshTokenExpiresAt,
      };

  static SessionRecord fromPersistJson(Map<String, dynamic> j) =>
      SessionRecord(
        accesskey: j['accesskey'] as String,
        refreshToken: j['refreshToken'] as String,
        userId: j['userId'] as String,
        deviceId: j['deviceId'] as String,
        accesskeyExpiresAt: j['accesskeyExpiresAt'] as int,
        refreshTokenExpiresAt: j['refreshTokenExpiresAt'] as int,
      );
}

class OtpSession {
  final String sessionId;
  final String phone;
  final String deviceId;
  final int createdAt;

  /// AUTH_CONTRACT §3.2: verify is one-shot. Re-verifying a consumed
  /// session is `410 SESSION_CONSUMED`, not a fresh login.
  bool consumed = false;

  OtpSession({
    required this.sessionId,
    required this.phone,
    required this.deviceId,
    required this.createdAt,
  });
}

class ChannelRecord {
  final String channelId;
  final String kind;
  // Mutable: PATCH /v3.0/channels/{id} edits both (SYNC_PROTOCOL §10.2
  // ChannelEdited).
  String? name;
  String? avatarUrl;

  // Decisions 9/80: exactly one owner, any number of admins, everyone
  // else a member. Both move — owner on succession, admins on PATCH
  // members/{user_id}.
  String ownerUserId;
  final Set<String> admins;

  /// Insertion-ordered (Dart's default `Set` is a LinkedHashSet), which
  /// is what makes "longest-standing" a `.first` — see [roleOf] and the
  /// succession rule in [leaveChannel].
  final Set<String> members;
  final int createdAt;

  ChannelRecord({
    required this.channelId,
    required this.kind,
    this.name,
    this.avatarUrl,
    required this.ownerUserId,
    Set<String>? admins,
    required this.members,
    required this.createdAt,
  }) : admins = admins ?? <String>{};

  String roleOf(String userId) => userId == ownerUserId
      ? 'owner'
      : (admins.contains(userId) ? 'admin' : 'member');

  Map<String, dynamic> toPersistJson() => {
        'channelId': channelId,
        'kind': kind,
        'name': name,
        'avatarUrl': avatarUrl,
        'ownerUserId': ownerUserId,
        'admins': admins.toList(),
        'members': members.toList(),
        'createdAt': createdAt,
      };

  static ChannelRecord fromPersistJson(Map<String, dynamic> j) => ChannelRecord(
        channelId: j['channelId'] as String,
        kind: j['kind'] as String,
        name: j['name'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        ownerUserId: j['ownerUserId'] as String,
        admins:
            (j['admins'] as List<dynamic>? ?? []).cast<String>().toSet(),
        members: (j['members'] as List<dynamic>).cast<String>().toSet(),
        createdAt: j['createdAt'] as int,
      );
}

// ---------------------------------------------------------------------------
// In-memory state
// ---------------------------------------------------------------------------

class MockState {
  final Map<String, UserRecord> usersByPhone = {};
  final Map<String, UserRecord> usersById = {};
  final Map<String, SessionRecord> sessions = {}; // accesskey -> session
  final Map<String, SessionRecord> sessionsByRefresh = {}; // refreshToken -> session
  final Map<String, OtpSession> otpSessions = {};
  final Map<String, ChannelRecord> channels = {};
  final Map<String, int> channelDeliverySeq = {};
  // §7.1 dedup window: '<user_id>:<op_id>' -> the outcome we already
  // returned for it. ponytail: unbounded and in-memory only (the spec
  // wants 10k/user, 7 days) — a mock never runs long enough to care.
  final Map<String, StoredOutcome> outcomes = {};
  // §6 sequencing: '<user_id>:<resource_id>' -> max accepted seq.
  final Map<String, int> resourceSeq = {};
  final Map<String, List<WebSocket>> wsConnections = {};
  // Per-user undelivered queue (SYNC_PROTOCOL.md §11). Holds raw
  // serialized WS_PUSH WsEnvelope frames. Drained on WS connect.
  final Map<String, List<Uint8List>> undelivered = {};

  final Random _rng = Random.secure();

  // ---- Persistence -----------------------------------------------------

  /// Path to the JSON state file, or null if persistence is disabled.
  String? persistencePath;
  Timer? _saveTimer;

  /// Schedule a debounced save. Every mutation site calls this; the
  /// 200ms window coalesces bursts (an OTP-verify touches users +
  /// sessions + channel + undelivered in quick succession — one write
  /// covers them all).
  void markDirty() {
    final path = persistencePath;
    if (path == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      _saveTimer = null;
      _saveSync(path);
    });
  }

  void _saveSync(String path) {
    try {
      final tmp = File('$path.tmp');
      tmp.writeAsStringSync(jsonEncode(toPersistJson()));
      tmp.renameSync(path);
    } catch (e) {
      _log('Persistence save failed: $e');
    }
  }

  Map<String, dynamic> toPersistJson() => {
        'version': 1,
        'users': usersById.values.map((u) => u.toPersistJson()).toList(),
        'sessions': sessions.values.map((s) => s.toPersistJson()).toList(),
        'channels':
            channels.values.map((c) => c.toPersistJson()).toList(),
        'channelDeliverySeq': channelDeliverySeq,
        'resourceSeq': resourceSeq,
        'undelivered': undelivered.map(
          (k, v) => MapEntry(k, v.map(base64Encode).toList()),
        ),
      };

  /// Load state from [path] if it exists. Silently no-ops on missing /
  /// malformed file so a fresh dev box just starts empty.
  void loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      final raw = file.readAsStringSync();
      if (raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in (j['users'] as List? ?? [])) {
        final u = UserRecord.fromPersistJson(entry as Map<String, dynamic>);
        usersByPhone[u.phone] = u;
        usersById[u.userId] = u;
      }
      for (final entry in (j['sessions'] as List? ?? [])) {
        final s = SessionRecord.fromPersistJson(entry as Map<String, dynamic>);
        sessions[s.accesskey] = s;
        sessionsByRefresh[s.refreshToken] = s;
      }
      for (final entry in (j['channels'] as List? ?? [])) {
        final c = ChannelRecord.fromPersistJson(entry as Map<String, dynamic>);
        channels[c.channelId] = c;
      }
      final seqs = j['channelDeliverySeq'] as Map<String, dynamic>? ?? {};
      seqs.forEach((k, v) => channelDeliverySeq[k] = v as int);
      final seqs2 = j['resourceSeq'] as Map<String, dynamic>? ?? {};
      seqs2.forEach((k, v) => resourceSeq[k] = v as int);
      final queues = j['undelivered'] as Map<String, dynamic>? ?? {};
      queues.forEach((k, v) => undelivered[k] = (v as List<dynamic>)
          .map((e) => base64Decode(e as String))
          .toList());
    } catch (e) {
      _log('Persistence load failed (starting fresh): $e');
    }
  }

  String generateUserId(String phone) {
    // Deterministic: SHA-256 of phone, take last 9 hex chars.
    final bytes = utf8.encode(phone);
    var hash = 0x811c9dc5; // FNV-1a 32-bit (good enough for a mock)
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    // Use two rounds to get 9 hex chars (36 bits).
    final hash2 = (hash * 0x01000193 + phone.length) & 0xFFFFFFFF;
    final combined = ((hash & 0x1F) << 32) | hash2;
    return combined.toRadixString(16).padLeft(9, '0').substring(0, 9);
  }

  String generateUuid() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  UserRecord getOrCreateUser(String phone) {
    var user = usersByPhone[phone];
    if (user == null) {
      user = UserRecord(
        userId: generateUserId(phone),
        phone: phone,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      usersByPhone[phone] = user;
      usersById[user.userId] = user;
      markDirty();
    }
    return user;
  }

  SessionRecord createSession(String userId, String deviceId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = SessionRecord(
      accesskey: generateUuid(),
      refreshToken: 'rt_${generateUuid()}',
      userId: userId,
      deviceId: deviceId,
      accesskeyExpiresAt: now + 30 * 24 * 3600 * 1000, // 30 days
      refreshTokenExpiresAt: now + 90 * 24 * 3600 * 1000, // 90 days
    );
    sessions[session.accesskey] = session;
    sessionsByRefresh[session.refreshToken] = session;
    markDirty();
    return session;
  }

  SessionRecord? lookupByAccesskey(String accesskey) => sessions[accesskey];

  void revokeSession(SessionRecord session) {
    sessions.remove(session.accesskey);
    sessionsByRefresh.remove(session.refreshToken);
    markDirty();
  }

  int nextDeliverySeq(String channelId) {
    final seq = (channelDeliverySeq[channelId] ?? 0) + 1;
    channelDeliverySeq[channelId] = seq;
    markDirty();
    return seq;
  }

  /// §7.1 — the outcome already returned for [opId], if any.
  StoredOutcome? storedOutcome(String userId, String opId) =>
      outcomes['$userId:$opId'];

  void recordOutcome(String userId, String opId, StoredOutcome outcome) {
    outcomes['$userId:$opId'] = outcome;
  }

  /// §6 — accept [seq] iff it is exactly `max_seen + 1` (first op on a
  /// resource must be 1). Returns false on a skip / replay of a lower
  /// seq, which the caller turns into `out_of_order`.
  bool acceptSeq(String userId, String resourceId, int seq) {
    final key = '$userId:$resourceId';
    final prev = resourceSeq[key] ?? 0;
    if (seq != prev + 1) return false;
    resourceSeq[key] = seq;
    markDirty();
    return true;
  }

  void addWsConnection(String userId, WebSocket ws) {
    wsConnections.putIfAbsent(userId, () => []).add(ws);
  }

  void removeWsConnection(String userId, WebSocket ws) {
    wsConnections[userId]?.remove(ws);
  }

  void enqueueUndelivered(String userId, Uint8List frame) {
    undelivered.putIfAbsent(userId, () => []).add(frame);
    markDirty();
  }

  List<Uint8List> drainUndelivered(String userId) {
    final queued = undelivered.remove(userId);
    if (queued != null && queued.isNotEmpty) markDirty();
    return queued ?? const [];
  }

  /// Create the seed peer user with a well-known userId.
  UserRecord createSeedPeer() {
    const phone = '+10000000000';
    final user = UserRecord(
      userId: '000000001',
      phone: phone,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    user.displayName = 'Seed Peer';
    user.username = 'seed_peer';
    usersByPhone[phone] = user;
    usersById[user.userId] = user;
    // A second well-known peer whose handle is gated by a username key
    // (AUTH_CONTRACT §4.5/§7.6) so tests can exercise both branches of
    // the by-username lookup.
    final keyed = UserRecord(
      userId: keyedPeerUserId,
      phone: keyedPeerPhone,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    keyed.displayName = 'Keyed Peer';
    keyed.username = keyedPeerUsername;
    keyed.usernameKey = keyedPeerKey;
    usersByPhone[keyedPeerPhone] = keyed;
    usersById[keyed.userId] = keyed;
    markDirty();
    return user;
  }
}

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

const String seedPeerUserId = '000000001';

/// A second seeded peer, discoverable only via
/// `GET /v3.0/users/by-username/{username}?key=` (AUTH_CONTRACT §7.6).
const String keyedPeerUserId = '000000002';
const String keyedPeerPhone = '+10000000002';
const String keyedPeerUsername = 'keyed_peer';
const String keyedPeerKey = '4821';

/// The dev OTP code. The mock accepts any 6-digit code; tests use this.
const String devOtpCode = '000000';

/// CLI wrapper. Preserves the historical flags and the on-disk state
/// file; in-process callers use [MockServer.start] instead (which
/// defaults to in-memory state).
void main(List<String> args) async {
  final port = int.parse(_parseArg(args, '--port', '9777'));
  final seedPeer = args.contains('--seed-peer');
  // Default state file lives next to the script. `--state-file=-`
  // disables persistence (back to pure in-memory).
  final scriptDir = File.fromUri(Platform.script).parent.path;
  final stateArg =
      _parseArg(args, '--state-file', '$scriptDir/.mock_state.json');
  final statePath = stateArg == '-' ? null : stateArg;
  final strict = !args.contains('--lax');

  final server = await MockServer.start(
    port: port,
    strict: strict,
    seedPeer: seedPeer,
    demoMode: seedPeer,
    statePath: statePath,
    log: true,
  );

  if (statePath != null) {
    _log('Persistence: $statePath '
        '(${server.state.usersById.length} user(s), '
        '${server.state.sessions.length} session(s), '
        '${server.state.channels.length} channel(s))');
  } else {
    _log('Persistence: disabled (--state-file=-)');
  }
  if (seedPeer) _log('Seed peer: userId=$seedPeerUserId');
  // Flush IO on Ctrl-C so the in-flight debounce timer doesn't drop
  // the last mutation.
  ProcessSignal.sigint.watch().listen((_) {
    if (statePath != null) server.state._saveSync(statePath);
    exit(0);
  });

  _log('Mock server listening on http://localhost:${server.port}');
  _log('  WS endpoint: ws://localhost:${server.port}/wss');
  _log('  Emulator:    http://10.0.2.2:${server.port}');
  _log('  Strict:      $strict');
  _log('---');
}

String _parseArg(List<String> args, String flag, String defaultValue) {
  final idx = args.indexOf(flag);
  if (idx >= 0 && idx + 1 < args.length) return args[idx + 1];
  return defaultValue;
}

bool _logEnabled = true;

void _log(String msg) {
  if (!_logEnabled) return;
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  print('[$ts] $msg');
}

/// One REST request the server handled. Tests assert on these instead
/// of scraping logs.
class RecordedRequest {
  final String method;
  final String path;
  final Map<String, dynamic> body;
  final int status;
  RecordedRequest(this.method, this.path, this.body, this.status);

  @override
  String toString() => '$method $path -> $status ${jsonEncode(body)}';
}

/// One inbound WS envelope the server accepted or rejected, with the
/// ACK reason it produced (null == ACK_SUCCESS).
class RecordedEnvelope {
  final String opId;
  final String channelId;
  final int resourceSeq;
  final Uint8List payload;
  final String? rejectReason;
  RecordedEnvelope({
    required this.opId,
    required this.channelId,
    required this.resourceSeq,
    required this.payload,
    required this.rejectReason,
  });
}

/// Stored per-op outcome for the §7.1 dedup window. WS ops keep an ACK
/// outcome; REST ops keep the literal response they got.
class StoredOutcome {
  final bool success;
  final String? reason; // WS permanent-reject reason
  final int? status; // REST status
  final Map<String, dynamic>? body; // REST body
  const StoredOutcome({
    required this.success,
    this.reason,
    this.status,
    this.body,
  });
}

/// The v3 mock chat-server, startable in-process.
///
/// `strict: true` (the default) turns it into a contract enforcer:
/// per-resource sequencing, op_id prefix binding, WS batch cap,
/// ChatPayload-or-0x53 payload shape, channel `kind`, op dedup and
/// one-shot OTP verify are all enforced per docs/SYNC_PROTOCOL.md and
/// docs/AUTH_CONTRACT.md. `strict: false` restores the permissive
/// behaviour the CLI demo relied on.
class MockServer {
  final HttpServer _http;
  final MockState state;

  /// The seed peer user exists and is discoverable via contacts.
  final bool seedPeerEnabled;

  /// CLI demo behaviours: auto-create a DM with the seed peer on OTP
  /// verify, auto-add the seed peer to every created channel, and
  /// auto-echo replies / typing. Off for in-process tests (they drive
  /// the peer explicitly via [injectPeerMessage]).
  final bool demoMode;

  /// Contract enforcement (SYNC_PROTOCOL §6, §6a.3, §7, §11.3).
  final bool strict;

  /// Every REST request handled, in order. Test hook.
  final List<RecordedRequest> requests = [];

  /// Every non-ephemeral WS envelope received, in order. Test hook.
  final List<RecordedEnvelope> envelopes = [];

  /// Every accepted `ephemeral=true` WS envelope, in order. They never
  /// reach [envelopes] (no ACK, no dedup, no sequencing). Test hook.
  final List<RecordedEnvelope> ephemeralEnvelopes = [];

  MockServer._(this._http, this.state,
      {required this.seedPeerEnabled,
      required this.demoMode,
      required this.strict});

  /// Bind and start serving. `port: 0` picks a free port.
  static Future<MockServer> start({
    int port = 0,
    bool strict = true,
    bool seedPeer = true,
    bool demoMode = false,
    String? statePath,
    bool log = false,
  }) async {
    _logEnabled = log;
    final state = MockState();
    if (statePath != null) {
      state.loadFromFile(statePath);
      state.persistencePath = statePath;
    }
    final http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    final server = MockServer._(
      http,
      state,
      seedPeerEnabled: seedPeer,
      demoMode: demoMode,
      strict: strict,
    );
    if (seedPeer && !state.usersById.containsKey(seedPeerUserId)) {
      state.createSeedPeer();
    }
    unawaited(server._serve());
    return server;
  }

  int get port => _http.port;
  Uri get apiUrl => Uri.parse('http://127.0.0.1:$port');
  Uri get wsUrl => Uri.parse('ws://127.0.0.1:$port/wss');

  Future<void> _serve() async {
    await for (final req in _http) {
      try {
        await _handleRequest(req);
      } catch (e, st) {
        _log('ERROR handling ${req.method} ${req.uri}: $e\n$st');
        try {
          _respondJson(req, 500, {
            'error': {'code': 'INTERNAL_ERROR', 'message': '$e'}
          });
        } catch (_) {}
      }
    }
  }

  /// Close every socket and stop listening.
  Future<void> stop() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    state._saveTimer?.cancel();
    for (final sockets in state.wsConnections.values) {
      for (final ws in sockets.toList()) {
        try {
          await ws.close();
        } catch (_) {}
      }
    }
    state.wsConnections.clear();
    await _http.close(force: true);
  }

  /// Demo timers, cancelled by [stop] so a test never leaks one.
  final Set<Timer> _timers = {};

  Timer _timer(Duration d, void Function() fn) {
    late Timer t;
    t = Timer(d, () {
      _timers.remove(t);
      fn();
    });
    _timers.add(t);
    return t;
  }

  // ---- Test hooks ------------------------------------------------------

  /// The OTP code that will verify the session for [phone]. The mock
  /// accepts any 6-digit code, so this is a constant; the method shape
  /// keeps tests honest if that ever changes.
  String sendOtpCodeFor(String phone) => devOtpCode;

  /// The well-known peer user every account can discover via
  /// `POST /v3.0/contacts/lookup`.
  UserRecord get seedPeer => state.usersById[seedPeerUserId]!;

  /// Inject an inbound chat message from [senderUserId] (defaults to
  /// the seed peer) into [channelId]. Fans a real `WS_PUSH` carrying a
  /// `ChatPayload{TYPE_MESSAGE_CREATE}` to every other member — live if
  /// they have a socket, otherwise onto their undelivered queue.
  ({String messageId, String opId}) injectPeerMessage({
    required String channelId,
    required String body,
    String senderUserId = seedPeerUserId,
  }) =>
      _sendPeerMessage(channelId, senderUserId, body);

  /// Inject a peer-authored edit of [messageId] (SYNC_PROTOCOL §6a:
  /// the recipient applies it only because [senderUserId] is the
  /// message's author).
  ({String messageId, String opId}) injectPeerEdit({
    required String channelId,
    required String messageId,
    required String body,
    String senderUserId = seedPeerUserId,
  }) =>
      _fanoutPeerChatPayload(
        channelId,
        senderUserId,
        pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_MESSAGE_UPDATE,
          messageId: messageId,
          body: body,
          contentType: 'text/plain',
        ),
      );

  /// Inject a peer-authored delete (tombstone) of [messageId].
  ({String messageId, String opId}) injectPeerDelete({
    required String channelId,
    required String messageId,
    String senderUserId = seedPeerUserId,
  }) =>
      _fanoutPeerChatPayload(
        channelId,
        senderUserId,
        pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_MESSAGE_DELETE,
          messageId: messageId,
        ),
      );

  /// Inject a peer reaction on [messageId] — add when [add], remove
  /// otherwise. Any member may react to anyone's message.
  ({String messageId, String opId}) injectPeerReaction({
    required String channelId,
    required String messageId,
    required String emoji,
    bool add = true,
    String senderUserId = seedPeerUserId,
  }) =>
      _fanoutPeerChatPayload(
        channelId,
        senderUserId,
        pb.ChatPayload(
          version: 1,
          type: add
              ? pb.ChatPayloadType.TYPE_REACTION_ADD
              : pb.ChatPayloadType.TYPE_REACTION_REMOVE,
          messageId: messageId,
          emoji: emoji,
        ),
      );

  /// Inject a peer-authored read receipt marking [messageId] (and
  /// everything before it) as read by [senderUserId] — decision 56's
  /// `ChatPayload{TYPE_READ_RECEIPT}`, not a server event.
  ({String messageId, String opId}) injectPeerReadReceipt({
    required String channelId,
    required String messageId,
    String senderUserId = seedPeerUserId,
  }) =>
      _fanoutPeerChatPayload(
        channelId,
        senderUserId,
        pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_READ_RECEIPT,
          messageId: messageId,
        ),
      );

  /// Inject a peer typing indicator as an `ephemeral=true` WS_PUSH —
  /// live-only, no ACK, no dedup, dropped for offline members.
  void injectPeerTyping({
    required String channelId,
    required bool isTyping,
    String senderUserId = seedPeerUserId,
  }) {
    final channel = state.channels[channelId];
    if (channel == null) throw StateError('unknown channel $channelId');
    final now = DateTime.now().millisecondsSinceEpoch;
    _fanoutEphemeral(
      pb.Envelope(
        opId: state.generateUuid(),
        channelId: channelId,
        clientTimestampMs: fixnum.Int64(now),
        payload: pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_TYPING,
          isTyping: isTyping,
        ).writeToBuffer(),
        ephemeral: true,
      ),
      senderUserId,
      channel,
      now,
    );
  }

  /// Reject the next [count] chat-content ops with ACK_PERMANENT, so a
  /// test can drive the client's dead-letter / Retry path without
  /// waiting out a retry budget. Consumed one op at a time.
  int rejectNextChatOps = 0;

  /// Park the `ChannelCreated` fanout a `POST /v3.0/channels` produces
  /// until [releaseChannelCreatedFanout], so a test can land the REST
  /// response on the caller before the other members hear anything.
  /// Default false: announce first, then answer — the order the real
  /// gateway produces.
  bool holdChannelCreatedFanout = false;
  final List<void Function()> _heldChannelCreatedFanouts = [];

  /// Deliver every fanout parked by [holdChannelCreatedFanout].
  void releaseChannelCreatedFanout() {
    final held = List.of(_heldChannelCreatedFanouts);
    _heldChannelCreatedFanouts.clear();
    for (final fanout in held) {
      fanout();
    }
  }

  /// Throw away everything queued for [userId] and report how many
  /// frames were lost. Stands in for an undelivered queue that did not
  /// survive — the one server-side failure a client cannot detect and
  /// has no way to ask about.
  int dropUndelivered(String userId) =>
      state.undelivered.remove(userId)?.length ?? 0;

  /// Materialize a server-side channel record without going through
  /// `POST /v3.0/channels`. Lets a test line the server's roster up
  /// with the client's optimistic state (or stand up a channel some
  /// other user created). With [announce] the §10.2 `ChannelCreated`
  /// event is fanned to every member except [ownerUserId].
  void ensureChannel({
    required String channelId,
    required String kind,
    required String ownerUserId,
    required List<String> members,
    String? name,
    bool announce = false,
  }) {
    final existing = state.channels[channelId];
    final createdAt = existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch;
    if (existing == null) {
      state.channels[channelId] = ChannelRecord(
        channelId: channelId,
        kind: kind,
        name: name,
        ownerUserId: ownerUserId,
        members: {...members},
        createdAt: createdAt,
      );
    } else {
      existing.members.addAll(members);
    }
    state.markDirty();
    if (!announce) return;
    for (final memberId in members) {
      if (memberId == ownerUserId) continue;
      _enqueueChannelCreated(
        recipientUserId: memberId,
        channelId: channelId,
        kind: kind,
        name: name ?? '',
        members: members,
        creatorUserId: ownerUserId,
        createdAtMs: createdAt,
      );
      // _enqueueChannelCreated only queues; flush it now if the
      // recipient is online so the test doesn't have to pull.
      final queued = state.drainUndelivered(memberId);
      for (final frame in queued) {
        _sendToUser(memberId, frame);
      }
    }
  }

  // ---- Strict validation (SYNC_PROTOCOL §6, §6a.3, §7.1, §11.3) --------

  /// §3 / §6a.3 step 2 — `op_id` bits[62..26] must equal the
  /// authenticated user_id. Layout per
  /// packages/vartalap_sync/lib/src/uuid7.dart: the 36-bit user_id
  /// spans the low 6 bits of byte 8 through the high 6 bits of byte 12.
  /// Returns null when the binding holds, else the reject reason.
  String? _checkOpIdPrefix(String userId, String opId) {
    final hex = opId.replaceAll('-', '');
    if (hex.length != 32) return 'validation_failed';
    int b(int i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    int bits;
    int expected;
    try {
      bits = ((b(8) & 0x3F) << 30) |
          (b(9) << 22) |
          (b(10) << 14) |
          (b(11) << 6) |
          (b(12) >> 2);
      expected = int.parse(userId, radix: 16);
    } on FormatException {
      return 'validation_failed';
    }
    return bits == expected ? null : 'prefix_mismatch';
  }

  /// §6a.3 step 5 — a client `Envelope.payload` is a `ChatPayload`
  /// protobuf and nothing else. A leading 0x53 (a forged server event)
  /// is rejected earlier in [_processEnvelope]; a JSON blob or byte
  /// soup is `validation_failed` here.
  bool _payloadIsWellFormed(List<int> payload) {
    if (payload.isEmpty) return false;
    try {
      final chat = pb.ChatPayload.fromBuffer(payload);
      // A real ChatPayload always sets `type`; a byte soup that happens
      // to survive the varint decoder does not.
      return chat.type != pb.ChatPayloadType.TYPE_UNSPECIFIED;
    } catch (_) {
      return false;
    }
  }

  /// Shared §11.2 preamble for REST writes: op_id prefix binding,
  /// §7.1 dedup replay, §6 sequencing. Returns a [StoredOutcome] when
  /// the request must NOT be applied (either a replay whose stored
  /// response we echo, or a rejection), else null.
  /// Pass `consumeSeq: false` when the endpoint has to run its own
  /// validation between the dedup check and the sequence check — see
  /// [_consumeSeq].
  StoredOutcome? _validateRestOp({
    required SessionRecord session,
    required Map<String, dynamic> body,
    required String resourceId,
    bool consumeSeq = true,
  }) {
    if (!strict) return null;
    final opId = body['op_id'];
    final seq = body['resource_seq'];
    if (opId is! String || opId.isEmpty || seq is! int) {
      return const StoredOutcome(
        success: false,
        status: 400,
        reason: 'validation_failed',
      );
    }
    final replay = state.storedOutcome(session.userId, opId);
    if (replay != null) return replay;

    final prefix = _checkOpIdPrefix(session.userId, opId);
    if (prefix != null) {
      return StoredOutcome(success: false, status: 400, reason: prefix);
    }
    if (consumeSeq && !state.acceptSeq(session.userId, resourceId, seq)) {
      return const StoredOutcome(
        success: false,
        status: 400,
        reason: 'out_of_order',
      );
    }
    return null;
  }

  /// §6 — the sequence half of [_validateRestOp], for an endpoint that
  /// must validate before consuming. `POST /v3.0/channels` is the one:
  /// the real gateway (`channel-ms.createChannel`) checks the roster
  /// and the `kind` BEFORE its `inOrder` call, so a create the server
  /// refuses on those grounds consumes no sequence. The mock used to
  /// consume it first and drift from the server on exactly that path.
  StoredOutcome? _consumeSeq(
    SessionRecord session,
    Map<String, dynamic> body,
    String resourceId,
  ) {
    if (!strict) return null;
    final seq = body['resource_seq'];
    if (seq is! int) {
      return const StoredOutcome(
        success: false,
        status: 400,
        reason: 'validation_failed',
      );
    }
    if (!state.acceptSeq(session.userId, resourceId, seq)) {
      return const StoredOutcome(
        success: false,
        status: 400,
        reason: 'out_of_order',
      );
    }
    return null;
  }

  /// Emit a stored/rejected REST outcome and record it.
  void _respondOutcome(
    HttpRequest req,
    Map<String, dynamic> body,
    StoredOutcome outcome,
  ) {
    final status = outcome.status ?? (outcome.success ? 200 : 400);
    final payload = outcome.body ??
        {
          'error': {
            'code': outcome.reason ?? 'validation_failed',
            'message': 'rejected: ${outcome.reason}'
          }
        };
    _record(req, body, status);
    _respondJson(req, status, payload);
  }

  void _record(HttpRequest req, Map<String, dynamic> body, int status) {
    requests.add(RecordedRequest(req.method, req.uri.path, body, status));
  }

  /// Server-side add of [userId] to [channelId], fanning the §10.2
  /// `ChannelMemberAdded` event to the existing members.
  void addChannelMember(String channelId, String userId) {
    final channel = state.channels[channelId];
    if (channel == null) throw StateError('unknown channel $channelId');
    channel.members.add(userId);
    state.markDirty();
    for (final memberId in channel.members) {
      if (memberId == userId) continue;
      _enqueueChannelMemberAdded(
        recipientUserId: memberId,
        channelId: channelId,
        newMemberUserIds: [userId],
        role: 'member',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Request router
  // ---------------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest req) async {
    // CORS for local dev
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    req.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS');
    req.response.headers.add('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    if (req.method == 'OPTIONS') {
      req.response.statusCode = 204;
      await req.response.close();
      return;
    }

    final path = req.uri.path;
    final method = req.method;

    // WebSocket upgrade
    if (WebSocketTransformer.isUpgradeRequest(req) && path == '/wss') {
      await _handleWsUpgrade(req);
      return;
    }

    // REST routes
    if (method == 'POST' && path == '/v3.0/auth/otp/send') {
      await _handleOtpSend(req);
    } else if (method == 'POST' && path == '/v3.0/auth/otp/verify') {
      await _handleOtpVerify(req);
    } else if (method == 'POST' && path == '/v3.0/auth/session/refresh') {
      await _handleSessionRefresh(req);
    } else if (method == 'POST' && path == '/v3.0/auth/session/revoke') {
      await _handleSessionRevoke(req);
    } else if (method == 'GET' && path == '/v3.0/users/me') {
      await _handleGetProfile(req);
    } else if (method == 'PATCH' && path == '/v3.0/users/me') {
      await _handlePatchProfile(req);
    } else if (method == 'POST' && path == '/v3.0/users/username/check') {
      await _handleCheckUsername(req);
    } else if (method == 'GET' &&
        path.startsWith('/v3.0/users/by-username/')) {
      await _handleGetUserByUsername(req);
    } else if (method == 'GET' && path.startsWith('/v3.0/users/')) {
      await _handleGetUser(req);
    } else if (method == 'POST' && path == '/v3.0/contacts/lookup') {
      await _handleContactLookup(req);
    } else if (method == 'POST' && path == '/v3.0/push/topic') {
      await _handlePushTopic(req);
    } else if (method == 'POST' && path == '/v3.0/channels') {
      await _handleCreateChannel(req);
    } else if (method == 'DELETE' && _memberPath(path) != null) {
      await _handleDeleteChannelMember(req, _memberPath(path)!);
    } else if (method == 'DELETE' && path.startsWith('/v3.0/channels/')) {
      await _handleDeleteChannel(req);
    } else if (method == 'GET' && path == '/v3.0/sync/pending') {
      await _handleSyncPending(req);
    } else if (method == 'POST' && path == '/v3.0/_dev/seed-users') {
      await _handleDevSeedUsers(req);
    } else if (await _tryAssetRoute(req, method, path)) {
      // media-ms presign / blob / status, and PATCH /v3.0/channels/{id}
      // — handlers at the end of this class.
    } else {
      _respondJson(req, 404, {
        'error': {'code': 'NOT_FOUND', 'message': 'Unknown route: $method $path'}
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Auth handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleOtpSend(HttpRequest req) async {
    final body = await _readJsonBody(req);
    final phone = body['phone'] as String?;
    final deviceId = body['deviceId'] as String?;
    if (phone == null || deviceId == null) {
      _respondJson(req, 400, {
        'error': {'code': 'MALFORMED_REQUEST', 'message': 'phone and deviceId required'}
      });
      return;
    }

    final sessionId = state.generateUuid();
    state.otpSessions[sessionId] = OtpSession(
      sessionId: sessionId,
      phone: phone,
      deviceId: deviceId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    final existing = state.usersByPhone.containsKey(phone);
    _log('OTP send: phone=$phone sessionId=$sessionId code=000000 existing=$existing');

    _respondJson(req, 200, {
      'sessionId': sessionId,
      'resendAfterSec': 30,
      'expiresInSec': 600,
      'isExistingAccount': existing,
    });
  }

  Future<void> _handleOtpVerify(HttpRequest req) async {
    final body = await _readJsonBody(req);
    final sessionId = body['sessionId'] as String?;
    final code = body['code'] as String?;
    final deviceId = body['deviceId'] as String?;

    if (sessionId == null || code == null || deviceId == null) {
      _respondJson(req, 400, {
        'error': {'code': 'MALFORMED_REQUEST', 'message': 'sessionId, code, deviceId required'}
      });
      return;
    }

    final otpSession = strict
        ? state.otpSessions[sessionId]
        : state.otpSessions.remove(sessionId);
    if (otpSession == null) {
      _respondJson(req, 404, {
        'error': {'code': 'SESSION_NOT_FOUND', 'message': 'Unknown sessionId'}
      });
      return;
    }
    // AUTH_CONTRACT §3.2 — verify is one-shot.
    if (otpSession.consumed) {
      _respondJson(req, 410, {
        'error': {
          'code': 'SESSION_CONSUMED',
          'message': 'OTP session already verified'
        }
      });
      return;
    }
    otpSession.consumed = true;

    // Accept any 6-digit code.
    if (code.length != 6) {
      _respondJson(req, 401, {
        'error': {'code': 'INVALID_CODE', 'message': 'Code must be 6 digits'}
      });
      return;
    }

    final isNew = !state.usersByPhone.containsKey(otpSession.phone);
    final user = state.getOrCreateUser(otpSession.phone);
    final session = state.createSession(user.userId, deviceId);

    _log('OTP verify: phone=${otpSession.phone} userId=${user.userId} isNew=$isNew');

    // If seed-peer is enabled and this user has no DM with the seed
    // peer yet, create one. We trigger off "channel missing" rather than
    // `isNew` so devs who enable --seed-peer on a previously-registered
    // account also get the channel materialized on next login.
    String? defaultChannelId;
    if (demoMode) {
      defaultChannelId = 'dm-${user.userId}-$seedPeerUserId';
      if (!state.channels.containsKey(defaultChannelId)) {
        final createdAt = DateTime.now().millisecondsSinceEpoch;
        state.channels[defaultChannelId] = ChannelRecord(
          channelId: defaultChannelId,
          kind: 'one_to_one',
          name: 'Seed Peer',
          ownerUserId: user.userId,
          members: {user.userId, seedPeerUserId},
          createdAt: createdAt,
        );
        state.markDirty();
        _log('Created seed-peer DM channel: $defaultChannelId');

        // Enqueue ChannelCreated for the new user so on WS connect the
        // client materializes the channel + member roster locally.
        _enqueueChannelCreated(
          recipientUserId: user.userId,
          channelId: defaultChannelId,
          kind: 'one_to_one',
          name: 'Seed Peer',
          members: [user.userId, seedPeerUserId],
          creatorUserId: user.userId,
          createdAtMs: createdAt,
        );
        // Followed by a welcome message so the channel actually appears
        // in the chat list — `watchChannelList` JOINs on `last_message_id`
        // so a channel with no messages stays hidden.
        _enqueueWelcomeMessage(
          recipientUserId: user.userId,
          channelId: defaultChannelId,
          senderUserId: seedPeerUserId,
          body: '👋 Welcome to Vartalap! Reply with anything and I\'ll echo it back.',
        );
      }
    }

    _respondJson(req, 200, {
      'status': true,
      'user_id': user.userId,
      'username': user.username,
      'phone': user.phone,
      'accesskey': session.accesskey,
      'refreshToken': session.refreshToken,
      'accesskeyExpiresAt': session.accesskeyExpiresAt,
      'refreshTokenExpiresAt': session.refreshTokenExpiresAt,
      'isNew': isNew,
      if (defaultChannelId != null) 'defaultChannelId': defaultChannelId,
    });
  }

  Future<void> _handleSessionRefresh(HttpRequest req) async {
    final body = await _readJsonBody(req);
    final refreshToken = body['refreshToken'] as String?;
    final deviceId = body['deviceId'] as String?;

    if (refreshToken == null || deviceId == null) {
      _respondJson(req, 400, {
        'error': {'code': 'MALFORMED_REQUEST', 'message': 'refreshToken and deviceId required'}
      });
      return;
    }

    final oldSession = state.sessionsByRefresh[refreshToken];
    if (oldSession == null || oldSession.deviceId != deviceId) {
      _respondJson(req, 401, {
        'error': {'code': 'INVALID_REFRESH_TOKEN', 'message': 'Invalid refresh token'}
      });
      return;
    }

    state.revokeSession(oldSession);
    final newSession = state.createSession(oldSession.userId, deviceId);

    _respondJson(req, 200, {
      'user_id': oldSession.userId,
      'accesskey': newSession.accesskey,
      'refreshToken': newSession.refreshToken,
      'accesskeyExpiresAt': newSession.accesskeyExpiresAt,
      'refreshTokenExpiresAt': newSession.refreshTokenExpiresAt,
    });
  }

  Future<void> _handleSessionRevoke(HttpRequest req) async {
    final session = _authenticate(req, usernameExempt: true);
    if (session == null) return;
    state.revokeSession(session);
    _log('Session revoked: userId=${session.userId}');
    _respondJson(req, 200, {'status': true});
  }

  // ---------------------------------------------------------------------------
  // Profile / contacts handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleGetProfile(HttpRequest req) async {
    final session = _authenticate(req, usernameExempt: true);
    if (session == null) return;
    final user = state.usersById[session.userId];
    if (user == null) {
      _respondJson(req, 404, {
        'error': {'code': 'USER_NOT_FOUND', 'message': 'User not found'}
      });
      return;
    }
    _respondJson(req, 200, user.toProfileJson());
  }

  Future<void> _handlePatchProfile(HttpRequest req) async {
    final session = _authenticate(req, usernameExempt: true);
    if (session == null) return;
    final user = state.usersById[session.userId];
    if (user == null) {
      _respondJson(req, 404, {
        'error': {'code': 'USER_NOT_FOUND', 'message': 'User not found'}
      });
      return;
    }
    final body = await _readJsonBody(req);
    // Track which fields actually changed so the fanout payload only
    // includes the deltas (matches proto3 `optional` semantics).
    String? newUsername;
    String? newDisplayName;
    String? newAvatarUrl;
    String? newStatusText;
    bool usernameTouched = false;
    bool profileTouched = false;
    if (body.containsKey('username')) {
      final raw = body['username'] as String?;
      if (raw != null &&
          !RegExp(r'^[a-z][a-z0-9._]{2,29}$').hasMatch(raw)) {
        _respondJson(req, 400, {
          'error': {
            'code': 'INVALID_USERNAME',
            'message': 'username must match ^[a-z][a-z0-9._]{2,29}\$'
          }
        });
        return;
      }
      final taken = raw != null &&
          state.usersById.values.any((u) =>
              u.userId != user.userId &&
              u.username != null &&
              u.username!.toLowerCase() == raw.toLowerCase());
      if (taken) {
        _respondJson(req, 409, {
          'error': {'code': 'USERNAME_TAKEN', 'message': 'username taken'}
        });
        return;
      }
      user.username = raw;
      // §4.5: clearing the handle also clears the key — a key with no
      // handle to gate is meaningless.
      if (raw == null) user.usernameKey = null;
      newUsername = user.username;
      usernameTouched = true;
    }
    if (body.containsKey('usernameKey')) {
      final raw = body['usernameKey'] as String?;
      if (raw != null &&
          (user.username == null || !RegExp(r'^\d{4}$').hasMatch(raw))) {
        _respondJson(req, 400, {
          'error': {
            'code': 'INVALID_USERNAME_KEY',
            'message': 'usernameKey must be exactly 4 digits, and only '
                'while a username is set'
          }
        });
        return;
      }
      // Stored in the clear — mock. Never echoed: toProfileJson() has
      // no usernameKey field (§4.5).
      user.usernameKey = raw;
    }
    if (body.containsKey('displayName')) {
      user.displayName = body['displayName'] as String?;
      newDisplayName = user.displayName;
      profileTouched = true;
    }
    if (body.containsKey('avatarUrl')) {
      user.avatarUrl = body['avatarUrl'] as String?;
      newAvatarUrl = user.avatarUrl;
      profileTouched = true;
    }
    if (body.containsKey('statusText')) {
      user.statusText = body['statusText'] as String?;
      newStatusText = user.statusText;
      profileTouched = true;
    }
    state.markDirty();
    _record(req, body, 200);
    _respondJson(req, 200, user.toProfileJson());

    // SYNC_PROTOCOL §10.2 fanout: every user sharing at least one
    // channel with the editor gets the corresponding ServerEventPayload.
    // We collect the recipient set first, then emit at most one push of
    // each kind to each recipient.
    final recipients = <String>{};
    for (final ch in state.channels.values) {
      if (ch.members.contains(user.userId)) {
        recipients.addAll(ch.members);
      }
    }
    recipients.remove(user.userId); // skip the editor

    _log('PATCH /v3.0/users/me: editor=${user.userId} '
        'profileTouched=$profileTouched usernameTouched=$usernameTouched '
        'recipients=${recipients.length}');

    if (profileTouched && recipients.isNotEmpty) {
      for (final recipient in recipients) {
        _enqueueProfileEdited(
          recipientUserId: recipient,
          editorUserId: user.userId,
          displayName: body.containsKey('displayName') ? newDisplayName : null,
          displayNamePresent: body.containsKey('displayName'),
          avatarUrl: body.containsKey('avatarUrl') ? newAvatarUrl : null,
          avatarUrlPresent: body.containsKey('avatarUrl'),
          statusText: body.containsKey('statusText') ? newStatusText : null,
          statusTextPresent: body.containsKey('statusText'),
        );
      }
    }
    if (usernameTouched && recipients.isNotEmpty) {
      for (final recipient in recipients) {
        _enqueueUsernameChanged(
          recipientUserId: recipient,
          editorUserId: user.userId,
          newUsername: newUsername ?? '',
        );
      }
    }
  }

  // Username availability stub. Real server (TODO) needs:
  //   - case-insensitive uniqueness over the global users table
  //   - 1-change-per-90-days rate limit per user
  //   - reserved-word list (admin, support, …)
  //   - bot/abuse heuristics
  // This stub only does (1) — the rest are documented in
  // docs/V3_TODOS.md.
  Future<void> _handleCheckUsername(HttpRequest req) async {
    final session = _authenticate(req, usernameExempt: true);
    if (session == null) return;
    final body = await _readJsonBody(req);
    final candidate = (body['username'] as String?)?.trim().toLowerCase();
    if (candidate == null || candidate.isEmpty) {
      _respondJson(req, 200, {'available': true});
      return;
    }
    final taken = state.usersById.values.any(
      (u) =>
          u.userId != session.userId &&
          u.username != null &&
          u.username!.toLowerCase() == candidate,
    );
    _respondJson(req, 200, {
      'available': !taken,
      if (taken) 'reason': 'taken',
    });
  }

  Future<void> _handleGetUser(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    final userId = req.uri.path.split('/').last;
    final user = state.usersById[userId];
    if (user == null) {
      _respondJson(req, 404, {
        'error': {'code': 'USER_NOT_FOUND', 'message': 'User not found'}
      });
      return;
    }
    _respondJson(req, 200, user.toPublicJson());
  }

  /// `GET /v3.0/users/by-username/{username}[?key=NNNN]` —
  /// AUTH_CONTRACT §7.6. Exact case-insensitive match, public profile
  /// only (no `phone`, §2.5).
  ///
  /// CONTRACT ADDITION (confirm before folding into AUTH_CONTRACT
  /// §7.6/§11.2): §7.6 makes "no such handle" and "wrong key"
  /// deliberately indistinguishable, but gives the client no way to
  /// learn that a key is needed at all — so the picker could never
  /// decide whether to show its Key field. This mock answers a
  /// *missing* key with `404 USERNAME_KEY_REQUIRED` while a *wrong*
  /// key stays a plain `404 USER_NOT_FOUND`. The key value itself
  /// leaks nothing; only "this public handle is gated" does, which the
  /// UI has to surface regardless.
  Future<void> _handleGetUserByUsername(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    final handle = Uri.decodeComponent(
            req.uri.path.substring('/v3.0/users/by-username/'.length))
        .toLowerCase();
    final key = req.uri.queryParameters['key'];
    void notFound([String code = 'USER_NOT_FOUND']) => _respondJson(req, 404, {
          'error': {'code': code, 'message': 'No such user'}
        });
    final user = state.usersById.values
        .where((u) => u.username?.toLowerCase() == handle)
        .firstOrNull;
    if (user == null) {
      notFound();
      return;
    }
    if (user.usernameKey != null) {
      if (key == null || key.isEmpty) {
        notFound('USERNAME_KEY_REQUIRED');
        return;
      }
      if (key != user.usernameKey) {
        notFound();
        return;
      }
    }
    _respondJson(req, 200, user.toPublicJson());
  }

  Future<void> _handleContactLookup(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    // Simplified: return all registered users as matches for any hash.
    // Echo the same SHA-256(phone) the client would have submitted, so
    // chat_service can map matches back to device-side contact names via
    // its `hashByName` lookup. The earlier `'hash_${u.phone}'` placeholder
    // string broke that mapping — every contact ended up with a null
    // `contact_book_name` in the local store, falling through to
    // `@username` in the UI.
    final matches = state.usersById.values
        .where((u) => u.userId != session.userId)
        .map((u) => {
              'phoneHash': sha256.convert(utf8.encode(u.phone)).toString(),
              'user_id': u.userId,
              'username': u.username,
            })
        .toList();
    _respondJson(req, 200, {'matches': matches});
  }

  // DEV-ONLY. Pre-registers N synthetic users with deterministic phones
  // and usernames so the New Chat screen can render a non-trivial contact
  // list against a single device. No auth required — the route is mock-
  // server-only and the chat-server has no equivalent. Idempotent: running
  // it twice with the same count just re-asserts the same set.
  //
  // Phones: +1900000000{N+1} (avoiding the seed peer's +10000000000 and
  // any real-looking range). Usernames: dummy_N. Display name: "Dummy N".
  Future<void> _handleDevSeedUsers(HttpRequest req) async {
    final body = await _readJsonBody(req);
    final raw = body['count'];
    final count = raw is int ? raw : int.tryParse('${raw ?? ''}') ?? 5;
    if (count < 1 || count > 50) {
      _respondJson(req, 400, {
        'error': {
          'code': 'OUT_OF_RANGE',
          'message': 'count must be 1..50 (got $count)'
        }
      });
      return;
    }
    final created = <Map<String, dynamic>>[];
    for (var i = 1; i <= count; i++) {
      final phone = '+1900000000$i';
      final user = state.getOrCreateUser(phone);
      user.username ??= 'dummy_$i';
      user.displayName ??= 'Dummy $i';
      created.add({
        'user_id': user.userId,
        'phone': phone,
        'username': user.username,
        'display_name': user.displayName,
      });
    }
    state.markDirty();
    _log('DEV: seeded ${created.length} dummy user(s)');
    _respondJson(req, 200, {'users': created, 'count': created.length});
  }

  /// AUTH_CONTRACT §5.1 — register, replace or (null/"") deregister the
  /// ntfy topic of the calling device. Validates the HTTPS scheme and a
  /// basic URL shape exactly like notification-ms; the mock has no
  /// configured `--ntfy-base-url`, so the host prefix check is the one
  /// server rule it cannot mirror.
  Future<void> _handlePushTopic(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    final body = await _readJsonBody(req);
    final topicUrl = body['topicUrl'] as String?;
    if (topicUrl == null || topicUrl.isEmpty) {
      _log('Push topic cleared for userId=${session.userId}');
      _record(req, body, 200);
      _respondJson(req, 200, {'status': true});
      return;
    }
    final parsed = Uri.tryParse(topicUrl);
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      _record(req, body, 400);
      _respondJson(req, 400, {
        'error': {
          'code': 'INVALID_TOPIC_URL',
          'message': 'topicUrl must be an https URL'
        }
      });
      return;
    }
    _log('Push topic registered for userId=${session.userId}: $topicUrl');
    _record(req, body, 200);
    _respondJson(req, 200, {'status': true});
  }

  // Client-triggered pull. Returns base64 of raw WS_PUSH WsEnvelope frames
  // queued for this user; the queue is drained in the same call.
  // Client invokes this on startup / WS connect — server never pushes
  // spontaneously and never auto-drains on connect.
  Future<void> _handleSyncPending(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    final queued = state.drainUndelivered(session.userId);
    final frames = queued.map(base64Encode).toList();
    _log('Sync pull: userId=${session.userId} delivered=${frames.length} frame(s)');
    _respondJson(req, 200, {'frames': frames});
  }

  // ---------------------------------------------------------------------------
  // Channel handler
  // ---------------------------------------------------------------------------

  Future<void> _handleCreateChannel(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    final body = await _readJsonBody(req);
    final channelId = body['channel_id'] as String? ?? state.generateUuid();
    final kind = body['kind'] as String? ?? 'one_to_one';
    final name = body['name'] as String?;
    final membersList = (body['members'] as List<dynamic>?)?.cast<String>() ?? [];

    // §11.3 — dedup + op_id binding now; the sequence is consumed only
    // once the `kind` and roster checks below have had their say, which
    // is the order channel-ms.createChannel runs them in.
    final pre = _validateRestOp(
      session: session,
      body: body,
      resourceId: channelId,
      consumeSeq: false,
    );
    if (pre != null) {
      _respondOutcome(req, body, pre);
      return;
    }
    // §11.3 — `kind` is exactly "one_to_one" or "group". No "dm".
    if (strict && kind != 'one_to_one' && kind != 'group') {
      final outcome = StoredOutcome(
        success: false,
        status: 400,
        reason: 'validation_failed',
        body: {
          'error': {
            'code': 'validation_failed',
            'message': 'kind must be one_to_one or group, got "$kind"'
          }
        },
      );
      state.recordOutcome(session.userId, body['op_id'] as String, outcome);
      _respondOutcome(req, body, outcome);
      return;
    }

    // §11.3 — the roster the server stores is the one it was sent, and
    // the creator must be in it. The real gateway answers 403
    // `forbidden` ("creator must be in members"); the mock used to add
    // the creator implicitly, which hid a client that never sent it.
    if (strict && !membersList.contains(session.userId)) {
      final outcome = StoredOutcome(
        success: false,
        status: 403,
        reason: 'forbidden',
        body: {
          'error': {
            'code': 'forbidden',
            'message': 'creator must be in members',
          }
        },
      );
      state.recordOutcome(session.userId, body['op_id'] as String, outcome);
      _respondOutcome(req, body, outcome);
      return;
    }

    final seqCheck = _consumeSeq(session, body, channelId);
    if (seqCheck != null) {
      state.recordOutcome(session.userId, body['op_id'] as String, seqCheck);
      _respondOutcome(req, body, seqCheck);
      return;
    }

    // Members the client explicitly asked for (creator + picked peers).
    final clientRequested = <String>{session.userId, ...membersList};
    // Final server-side roster — same as requested, plus the seed peer
    // in demo mode so groups demo Echo replies.
    final members = <String>{...clientRequested};
    if (demoMode) members.add(seedPeerUserId);

    final createdAt = DateTime.now().millisecondsSinceEpoch;
    state.channels[channelId] = ChannelRecord(
      channelId: channelId,
      kind: kind,
      name: name,
      ownerUserId: session.userId,
      members: members,
      createdAt: createdAt,
    );
    state.markDirty();

    _log('Channel created: $channelId kind=$kind members=$members');

    // §10.2 — announce the new channel to the other members, the way
    // channel-ms.createChannel fans CHANNEL_CREATED. The mock never
    // did, so a peer only learned a channel existed when a message
    // landed on it, and no test could see the ordering between the
    // REST answer and the announcement.
    //
    // ponytail: the creator is skipped. The real gateway includes it
    // in the recipient list, but the creator already holds the row and
    // its InboundReceiver makes the echo a no-op — the same reasoning
    // [ensureChannel]'s announce already uses. Add it if a test ever
    // needs to assert on the echo itself.
    void announce() {
      for (final memberId in members) {
        if (memberId == session.userId) continue;
        _enqueueChannelCreated(
          recipientUserId: memberId,
          channelId: channelId,
          kind: kind,
          name: name ?? '',
          members: members.toList(),
          creatorUserId: session.userId,
          createdAtMs: createdAt,
        );
        // _enqueueChannelCreated only queues; flush it now if the
        // recipient is connected, so a live peer sees it without
        // having to pull.
        for (final frame in state.drainUndelivered(memberId)) {
          _sendToUser(memberId, frame);
        }
      }
    }

    if (holdChannelCreatedFanout) {
      _heldChannelCreatedFanouts.add(announce);
    } else {
      announce();
    }

    // If the server added members the client doesn't know about
    // (currently just the seed peer when --seed-peer is on), emit a
    // ChannelMemberAdded WS_PUSH so the client materializes the missing
    // membership rows. Without this, group bubbles authored by the seed
    // peer render with "Unknown" because the local `channel_members`
    // join misses them.
    final injected = members.difference(clientRequested);
    if (injected.isNotEmpty) {
      _enqueueChannelMemberAdded(
        recipientUserId: session.userId,
        channelId: channelId,
        newMemberUserIds: injected.toList(),
      );
    }

    final created = {
      'channel_id': channelId,
      'kind': kind,
      'name': name,
      'members': members.toList(),
      'created_at': createdAt,
    };
    final opId = body['op_id'];
    if (opId is String) {
      state.recordOutcome(session.userId, opId,
          StoredOutcome(success: true, status: 201, body: created));
    }
    _record(req, body, 201);
    _respondJson(req, 201, created);
  }

  /// `(channelId, userId)` of `/v3.0/channels/{id}/members/{user_id}`,
  /// or null when [path] is not that shape.
  static ({String channelId, String userId})? _memberPath(String path) {
    const prefix = '/v3.0/channels/';
    if (!path.startsWith(prefix)) return null;
    final parts = path.substring(prefix.length).split('/');
    if (parts.length != 3 || parts[1] != 'members') return null;
    if (parts[0].isEmpty || parts[2].isEmpty) return null;
    return (channelId: parts[0], userId: parts[2]);
  }

  // DELETE /v3.0/channels/{id} — decision 9 hard delete, owner only.
  // The channel record goes; every other member is told with a §10.2
  // ChannelDeleted so their local row is tombstoned. Plain members and
  // admins get 403 — leaving is DELETE …/members/{self}.
  Future<void> _handleDeleteChannel(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;

    // /v3.0/channels/{id}
    final path = req.uri.path;
    final channelId = path.substring('/v3.0/channels/'.length);
    if (channelId.isEmpty || channelId.contains('/')) {
      _respondJson(req, 400, {
        'error': {'code': 'MALFORMED_REQUEST', 'message': 'channel_id required'}
      });
      return;
    }

    // §11.2 — the body carries op_id / resource_seq / client_timestamp_ms.
    final body = await _readJsonBody(req);
    final pre = _validateRestOp(
      session: session,
      body: body,
      resourceId: channelId,
    );
    if (pre != null) {
      _respondOutcome(req, body, pre);
      return;
    }

    final channel = state.channels[channelId];
    if (channel == null) {
      _record(req, body, 404);
      _respondJson(req, 404, {
        'error': {'code': 'NOT_FOUND', 'message': 'Unknown channel: $channelId'}
      });
      return;
    }
    if (!channel.members.contains(session.userId)) {
      _record(req, body, 403);
      _respondJson(req, 403, {
        'error': {'code': 'FORBIDDEN', 'message': 'Not a member of channel'}
      });
      return;
    }
    if (channel.ownerUserId != session.userId) {
      _record(req, body, 403);
      _respondJson(req, 403, {
        'error': {
          'code': 'FORBIDDEN',
          'message': 'Only the owner can delete a group'
        }
      });
      return;
    }

    final recipients = channel.members.where((m) => m != session.userId).toList();
    state.channels.remove(channelId);
    state.markDirty();
    _log('Channel deleted: $channelId by=${session.userId}');

    final opId = body['op_id'];
    if (opId is String) {
      state.recordOutcome(session.userId, opId,
          const StoredOutcome(success: true, status: 200, body: {}));
    }
    _record(req, body, 200);
    _respondJson(req, 200, <String, dynamic>{});

    for (final memberId in recipients) {
      _enqueueChannelDeleted(
        recipientUserId: memberId,
        channelId: channelId,
      );
    }
  }

  // DELETE /v3.0/channels/{id}/members/{user_id} — decision 80. Target
  // == self is "leave" and is open to every member, the owner included
  // (succession happens in [leaveChannel]). Target != self is "remove
  // from group": owner and admins only, and never the owner.
  Future<void> _handleDeleteChannelMember(
    HttpRequest req,
    ({String channelId, String userId}) target,
  ) async {
    final session = _authenticate(req);
    if (session == null) return;

    final body = await _readJsonBody(req);
    final pre = _validateRestOp(
      session: session,
      body: body,
      resourceId: target.channelId,
    );
    if (pre != null) {
      _respondOutcome(req, body, pre);
      return;
    }

    final channel = state.channels[target.channelId];
    if (channel == null) {
      _record(req, body, 404);
      _respondJson(req, 404, {
        'error': {
          'code': 'NOT_FOUND',
          'message': 'Unknown channel: ${target.channelId}'
        }
      });
      return;
    }
    if (!channel.members.contains(session.userId)) {
      _record(req, body, 403);
      _respondJson(req, 403, {
        'error': {'code': 'FORBIDDEN', 'message': 'Not a member of channel'}
      });
      return;
    }
    if (!channel.members.contains(target.userId)) {
      _record(req, body, 404);
      _respondJson(req, 404, {
        'error': {
          'code': 'NOT_FOUND',
          'message': 'Not a member: ${target.userId}'
        }
      });
      return;
    }
    if (target.userId != session.userId) {
      final actorRole = channel.roleOf(session.userId);
      if (actorRole == 'member') {
        _record(req, body, 403);
        _respondJson(req, 403, {
          'error': {
            'code': 'FORBIDDEN',
            'message': 'Only the owner or an admin can remove a member'
          }
        });
        return;
      }
      if (target.userId == channel.ownerUserId) {
        _record(req, body, 403);
        _respondJson(req, 403, {
          'error': {
            'code': 'FORBIDDEN',
            'message': 'The owner cannot be removed'
          }
        });
        return;
      }
    }

    leaveChannel(target.channelId, target.userId);

    final opId = body['op_id'];
    if (opId is String) {
      state.recordOutcome(session.userId, opId,
          const StoredOutcome(success: true, status: 200, body: {}));
    }
    _record(req, body, 200);
    _respondJson(req, 200, <String, dynamic>{});
  }

  /// Server-side membership removal with decision 9 succession, shared
  /// by the REST route and tests that need another user to walk out.
  ///
  /// The leaver always gets a `ChannelMemberRemoved` (so a kicked
  /// client tombstones), as does everyone left. If the leaver was the
  /// owner, the longest-standing admin — else the longest-standing
  /// remaining member — is re-announced as
  /// `ChannelMemberAdded{role:"owner"}`. The last member out takes the
  /// channel with them and gets a `ChannelDeleted`.
  void leaveChannel(String channelId, String userId) {
    final channel = state.channels[channelId];
    if (channel == null || !channel.members.contains(userId)) return;
    channel.members.remove(userId);
    channel.admins.remove(userId);
    final removedAtMs = DateTime.now().millisecondsSinceEpoch;

    if (channel.members.isEmpty) {
      state.channels.remove(channelId);
      state.markDirty();
      _log('Channel emptied by last member: $channelId user=$userId');
      _enqueueChannelDeleted(
        recipientUserId: userId,
        channelId: channelId,
      );
      return;
    }

    String? successor;
    if (channel.ownerUserId == userId) {
      // Insertion order on both sets is join order — `.first` is the
      // longest-standing.
      successor = channel.admins.isNotEmpty
          ? channel.admins.first
          : channel.members.first;
      channel.ownerUserId = successor;
      channel.admins.remove(successor);
      _log('Ownership of $channelId passed to $successor');
    }
    state.markDirty();
    _log('Channel leave: $channelId user=$userId '
        'remaining=${channel.members}');

    for (final memberId in {userId, ...channel.members}) {
      _enqueueChannelMemberRemoved(
        recipientUserId: memberId,
        channelId: channelId,
        memberUserId: userId,
        removedAtMs: removedAtMs,
      );
    }
    if (successor == null) return;
    for (final memberId in channel.members) {
      _enqueueChannelMemberAdded(
        recipientUserId: memberId,
        channelId: channelId,
        newMemberUserIds: [successor],
        role: 'owner',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // WebSocket handler
  // ---------------------------------------------------------------------------

  Future<void> _handleWsUpgrade(HttpRequest req) async {
    // Extract accesskey from Sec-WebSocket-Protocol: accesskey.<token>
    final subprotocol = req.headers.value('sec-websocket-protocol');
    if (subprotocol == null || !subprotocol.startsWith('accesskey.')) {
      req.response.statusCode = 401;
      req.response.write(jsonEncode({
        'error': {'code': 'MISSING_ACCESSKEY', 'message': 'WebSocket subprotocol must carry accesskey'}
      }));
      await req.response.close();
      return;
    }

    final token = subprotocol.substring('accesskey.'.length);
    final session = state.lookupByAccesskey(token);
    if (session == null) {
      req.response.statusCode = 401;
      req.response.write(jsonEncode({
        'error': {'code': 'INVALID_ACCESSKEY', 'message': 'accesskey is not valid'}
      }));
      await req.response.close();
      return;
    }

    final userId = session.userId;
    final ws = await WebSocketTransformer.upgrade(
      req,
      protocolSelector: (protocols) => protocols.isNotEmpty ? protocols.first : '',
    );

    state.addWsConnection(userId, ws);
    _log('WS connected: userId=$userId (${state.wsConnections[userId]?.length ?? 0} sockets)');

    ws.listen(
      (dynamic data) {
        if (data is! List<int>) return;
        _handleWsFrame(userId, Uint8List.fromList(data));
      },
      onError: (e) {
        _log('WS error for userId=$userId: $e');
        state.removeWsConnection(userId, ws);
      },
      onDone: () {
        state.removeWsConnection(userId, ws);
        _log('WS disconnected: userId=$userId');
      },
    );
  }

  void _handleWsFrame(String senderUserId, Uint8List bytes) {
    pb.WsEnvelope wsEnv;
    try {
      wsEnv = pb.WsEnvelope.fromBuffer(bytes);
    } catch (e) {
      _log('WS malformed frame from $senderUserId: $e');
      return;
    }

    if (wsEnv.type != pb.WsType.WS_OP) {
      _log('WS unexpected type=${wsEnv.type} from $senderUserId');
      return;
    }

    // SYNC_PROTOCOL §5.2 — max 20 envelopes per WS_OP frame. Over the
    // cap the whole frame is rejected: `validation_failed` for every
    // envelope in it.
    if (strict && wsEnv.ops.envelopes.length > 20) {
      _log('WS batch too large (${wsEnv.ops.envelopes.length}) '
          'from $senderUserId');
      final rejects = [
        for (final env in wsEnv.ops.envelopes)
          pb.Ack(
            opId: env.opId,
            outcome: pb.AckOutcome.ACK_PERMANENT,
            reason: 'validation_failed',
          )
      ];
      _sendToUser(
        senderUserId,
        pb.WsEnvelope(type: pb.WsType.WS_ACK, acks: pb.AckBatch(acks: rejects))
            .writeToBuffer(),
      );
      return;
    }

    final acks = <pb.Ack>[];
    for (final env in wsEnv.ops.envelopes) {
      final ack = _processEnvelope(senderUserId, env);
      if (ack != null) acks.add(ack);
    }

    if (acks.isEmpty) return; // ephemeral-only batch — no ACK frame.

    // Send all ACKs back to sender.
    final ackFrame = pb.WsEnvelope(
      type: pb.WsType.WS_ACK,
      acks: pb.AckBatch(acks: acks),
    );
    _sendToUser(senderUserId, ackFrame.writeToBuffer());
  }

  pb.Ack? _processEnvelope(String senderUserId, pb.Envelope env) {
    final channelId = env.channelId;
    final opId = env.opId;
    final now = DateTime.now().millisecondsSinceEpoch;

    pb.Ack reject(String reason) {
      _log('WS reject: opId=$opId reason=$reason from $senderUserId');
      state.recordOutcome(
          senderUserId, opId, StoredOutcome(success: false, reason: reason));
      envelopes.add(RecordedEnvelope(
        opId: opId,
        channelId: channelId,
        resourceSeq: env.resourceSeq.toInt(),
        payload: Uint8List.fromList(env.payload),
        rejectReason: reason,
      ));
      return pb.Ack(
        opId: opId,
        outcome: pb.AckOutcome.ACK_PERMANENT,
        reason: reason,
      );
    }

    // §7.1 dedup — a replayed op_id returns the stored outcome and is
    // never re-applied.
    if (!env.ephemeral) {
      final stored = state.storedOutcome(senderUserId, opId);
      if (stored != null) {
        _log('WS dedup: opId=$opId from $senderUserId '
            'success=${stored.success}');
        return stored.success
            ? pb.Ack(
                opId: opId,
                outcome: pb.AckOutcome.ACK_SUCCESS,
                serverTimestampMs: fixnum.Int64(now),
              )
            : pb.Ack(
                opId: opId,
                outcome: pb.AckOutcome.ACK_PERMANENT,
                reason: stored.reason,
              );
      }
    }

    // §6a.3 step 2 — op_id user_id bits must match the session.
    if (strict) {
      final prefix = _checkOpIdPrefix(senderUserId, opId);
      if (prefix != null) return reject(prefix);
    }

    // Channel membership check
    final channel = state.channels[channelId];
    if (channel == null || !channel.members.contains(senderUserId)) {
      return reject('forbidden');
    }

    // §10.2 / decision 56 — server events are server-authored. A client
    // that prepends the 0x53 distinguisher is forging one; the real
    // gateway answers `validation_failed` and so do we. Checked ahead of
    // the ephemeral split so a forged typing frame is rejected too.
    if (strict && env.payload.isNotEmpty && env.payload[0] == 0x53) {
      return reject('validation_failed');
    }

    // Ephemeral envelopes bypass dedup, deliverySeq, undelivered queue,
    // ACK emission, and any of the post-fanout receipts. Fan to currently-
    // connected members live and drop the rest. See v3-envelope.proto.
    if (env.ephemeral) {
      ephemeralEnvelopes.add(RecordedEnvelope(
        opId: opId,
        channelId: channelId,
        resourceSeq: env.resourceSeq.toInt(),
        payload: Uint8List.fromList(env.payload),
        rejectReason: null,
      ));
      _fanoutEphemeral(env, senderUserId, channel, now);
      if (demoMode &&
          senderUserId != seedPeerUserId &&
          channel.members.contains(seedPeerUserId)) {
        _scheduleSeedPeerTypingEcho(channelId, env.payload);
      }
      // Return null-ish via a no-outcome Ack — the client ignores ACKs
      // with op_ids it doesn't track. (Safer than skipping the return:
      // the calling site builds an AckBatch from a List<Ack>.)
      return null;
    }

    // §6a.3 step 4 — resource_seq must be exactly max_seen + 1 for
    // this (user_id, channel_id); the first op on a resource is 1.
    if (strict &&
        !state.acceptSeq(senderUserId, channelId, env.resourceSeq.toInt())) {
      return reject('out_of_order');
    }

    // §6a.3 step 5 — a client payload is a ChatPayload proto. Nothing
    // else is on the wire (§10.2 server events are server-authored).
    if (strict && !_payloadIsWellFormed(env.payload)) {
      return reject('validation_failed');
    }

    // Test hook. Placed after the sequence check on purpose: the seq
    // has been consumed server-side either way, so the client's next
    // op (or its manual retry) still lines up at max_seen + 1. A read
    // receipt is not chat content and never consumes the budget.
    if (rejectNextChatOps > 0 && !_isReadReceipt(env.payload)) {
      rejectNextChatOps--;
      return reject('forced_reject');
    }

    // Accept the op
    state.recordOutcome(
        senderUserId, opId, const StoredOutcome(success: true));
    envelopes.add(RecordedEnvelope(
      opId: opId,
      channelId: channelId,
      resourceSeq: env.resourceSeq.toInt(),
      payload: Uint8List.fromList(env.payload),
      rejectReason: null,
    ));
    final deliverySeq = state.nextDeliverySeq(channelId);

    _log('WS op: opId=$opId channel=$channelId sender=$senderUserId seq=$deliverySeq');

    // Fanout WS_PUSH to other channel members
    final pushEnv = pb.Envelope(
      opId: opId,
      channelId: channelId,
      resourceSeq: env.resourceSeq,
      clientTimestampMs: env.clientTimestampMs,
      payload: env.payload,
      senderUserId: senderUserId,
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(deliverySeq),
    );

    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    final pushBytes = pushFrame.writeToBuffer();

    for (final memberId in channel.members) {
      if (memberId == senderUserId) continue;
      _sendToUser(memberId, pushBytes);
    }

    // Send a MessageStateChanged{DELIVERED} back to the author so the
    // local row flips from single tick to double. Only if there was at
    // least one other channel member (otherwise nothing was delivered).
    // `_isMessageCreate` is what keeps receipts/edits/reactions out:
    // re-announcing their lifecycle would loop a receipt back at the
    // reader and produce an "Echo: <binary>" garbage reply.
    if (channel.members.length > 1 &&
        _isMessageCreate(env.payload)) {
      final messageId = _extractMessageId(env.payload);
      if (messageId != null) {
        _enqueueMessageStateChanged(
          recipientUserId: senderUserId,
          channelId: channelId,
          messageId: messageId,
          newState: pb.MessageStateValue.MESSAGE_STATE_DELIVERED,
        );
      } else {
        _log('Skipping delivered receipt: no message_id extractable from '
            'payload (opId=$opId, ${env.payload.length} bytes)');
      }
    }

    // Seed peer auto-reply (and auto-mark-read so the author's tick
    // goes blue without needing a second human device).
    if (_isMessageCreate(env.payload) &&
        demoMode &&
        senderUserId != seedPeerUserId &&
        channel.members.contains(seedPeerUserId)) {
      _scheduleSeedPeerReply(channelId, senderUserId, env.payload);
      final readId = _extractMessageId(env.payload);
      if (readId != null) {
        _timer(const Duration(milliseconds: 1500), () {
          _enqueueMessageStateChanged(
            recipientUserId: senderUserId,
            channelId: channelId,
            messageId: readId,
            newState: pb.MessageStateValue.MESSAGE_STATE_READ,
          );
        });
      }
    }

    return pb.Ack(
      opId: opId,
      outcome: pb.AckOutcome.ACK_SUCCESS,
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(deliverySeq),
    );
  }

  // Live-fanout to a user. If the user has no open WS, the frame is
  // enqueued in the per-user undelivered queue; the client picks it up
  // on its next call to GET /v3.0/sync/pending.
  void _sendToUser(String userId, Uint8List bytes) {
    final sockets = state.wsConnections[userId];
    if (sockets == null || sockets.isEmpty) {
      state.enqueueUndelivered(userId, bytes);
      return;
    }
    for (final ws in sockets) {
      try {
        ws.add(bytes);
      } catch (e) {
        _log('WS send error to $userId: $e');
      }
    }
  }

  // Build a WS_PUSH WsEnvelope carrying a ChannelCreated ServerEventPayload
  // for [recipientUserId] and enqueue it in the user's undelivered queue.
  // Wire format: payload bytes are the serialized ServerEventPayload
  // PREPENDED with 0x53 per SYNC_PROTOCOL.md §10.2.
  void _enqueueChannelCreated({
    required String recipientUserId,
    required String channelId,
    required String kind,
    required String name,
    required List<String> members,
    required String creatorUserId,
    required int createdAtMs,
  }) {
    final sep = pb.ServerEventPayload(
      version: 1,
      type: pb.ServerEventType.CHANNEL_CREATED,
      channelCreated: pb.ChannelCreated(
        channelId: channelId,
        kind: kind,
        name: name,
        members: members,
        creator: creatorUserId,
        createdAtMs: fixnum.Int64(createdAtMs),
      ),
    );
    final payload = Uint8List.fromList([0x53, ...sep.writeToBuffer()]);

    final now = DateTime.now().millisecondsSinceEpoch;
    final pushEnv = pb.Envelope(
      opId: state.generateUuid(),
      channelId: channelId,
      resourceSeq: fixnum.Int64(0),
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: creatorUserId,
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(state.nextDeliverySeq(channelId)),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    state.enqueueUndelivered(recipientUserId, pushFrame.writeToBuffer());
    _log('Enqueued ChannelCreated for $recipientUserId channel=$channelId');
  }

  // Build a WS_PUSH WsEnvelope carrying a ChannelMemberAdded
  // ServerEventPayload and enqueue it for [recipientUserId]. Used when
  // the server adds members the client didn't request (e.g. the seed
  // peer auto-injection in --seed-peer mode) so the local membership
  // table catches up. Without this, group bubbles authored by the
  // auto-added member render with "Unknown" because the local
  // channel_members join misses them.
  //
  // Decision 80 re-uses it as the role-change / succession fanout:
  // [role] re-announces an EXISTING member so recipients upsert the new
  // role. Left empty on a plain add (recipients default to "member").
  void _enqueueChannelMemberAdded({
    required String recipientUserId,
    required String channelId,
    required List<String> newMemberUserIds,
    String role = '',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sep = pb.ServerEventPayload(
      version: 1,
      type: pb.ServerEventType.CHANNEL_MEMBER_ADDED,
      memberAdded: pb.ChannelMemberAdded(
        channelId: channelId,
        members: newMemberUserIds,
        addedAtMs: fixnum.Int64(now),
        role: role,
      ),
    );
    final payload = Uint8List.fromList([0x53, ...sep.writeToBuffer()]);
    final pushEnv = pb.Envelope(
      opId: state.generateUuid(),
      channelId: channelId,
      resourceSeq: fixnum.Int64(0),
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: '', // server-authored
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(state.nextDeliverySeq(channelId)),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    // Live-fan if the recipient's WS is open; otherwise enqueue.
    _sendToUser(recipientUserId, pushFrame.writeToBuffer());
    _log('Sent ChannelMemberAdded to $recipientUserId '
        'channel=$channelId added=$newMemberUserIds');
  }

  // Build a WS_PUSH WsEnvelope carrying a ChannelMemberRemoved
  // ServerEventPayload and enqueue / live-fan it for [recipientUserId].
  // Used when a member leaves a group via DELETE /v3.0/channels/{id} so
  // the remaining members' local channel_members tables drop the row.
  void _enqueueChannelMemberRemoved({
    required String recipientUserId,
    required String channelId,
    required String memberUserId,
    required int removedAtMs,
  }) {
    final sep = pb.ServerEventPayload(
      version: 1,
      type: pb.ServerEventType.CHANNEL_MEMBER_REMOVED,
      memberRemoved: pb.ChannelMemberRemoved(
        channelId: channelId,
        member: memberUserId,
        removedAtMs: fixnum.Int64(removedAtMs),
      ),
    );
    final payload = Uint8List.fromList([0x53, ...sep.writeToBuffer()]);
    final pushEnv = pb.Envelope(
      opId: state.generateUuid(),
      channelId: channelId,
      resourceSeq: fixnum.Int64(0),
      clientTimestampMs: fixnum.Int64(removedAtMs),
      payload: payload,
      senderUserId: '', // server-authored
      serverTimestampMs: fixnum.Int64(removedAtMs),
      deliverySequence: fixnum.Int64(state.nextDeliverySeq(channelId)),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    // Live-fan if the recipient's WS is open; otherwise enqueue.
    _sendToUser(recipientUserId, pushFrame.writeToBuffer());
    _log('Sent ChannelMemberRemoved to $recipientUserId '
        'channel=$channelId member=$memberUserId');
  }

  // SYNC_PROTOCOL §10.2 ProfileEdited fanout. Each *Present flag carries
  // proto3-`optional` semantics: when true, the field is populated on
  // the wire (empty string == "user cleared this"); when false the
  // field is absent and recipients leave their cached value alone.
  //
  // Channel id on the envelope is intentionally a synthetic per-recipient
  // "profile" channel — recipients route on `payload[0]==0x53` and the
  // inner `ServerEventPayload.user_id`, not on Envelope.channel_id.
  // We use the channel that this fanout would be most relevant to
  // (any shared channel works); for simplicity we pick the first one.
  void _enqueueProfileEdited({
    required String recipientUserId,
    required String editorUserId,
    required bool displayNamePresent,
    String? displayName,
    required bool avatarUrlPresent,
    String? avatarUrl,
    required bool statusTextPresent,
    String? statusText,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final body = pb.ProfileEdited(
      userId: editorUserId,
      editedAtMs: fixnum.Int64(now),
    );
    if (displayNamePresent) body.displayName = displayName ?? '';
    if (avatarUrlPresent) body.avatarUrl = avatarUrl ?? '';
    if (statusTextPresent) body.statusText = statusText ?? '';
    final sep = pb.ServerEventPayload(
      version: 1,
      type: pb.ServerEventType.PROFILE_EDITED,
      profileEdited: body,
    );
    final payload = Uint8List.fromList([0x53, ...sep.writeToBuffer()]);

    final channelId = state.channels.values
        .firstWhere(
          (ch) =>
              ch.members.contains(editorUserId) &&
              ch.members.contains(recipientUserId),
          orElse: () => state.channels.values.first,
        )
        .channelId;

    final pushEnv = pb.Envelope(
      opId: state.generateUuid(),
      channelId: channelId,
      resourceSeq: fixnum.Int64(0),
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: '', // server-authored
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(state.nextDeliverySeq(channelId)),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    _sendToUser(recipientUserId, pushFrame.writeToBuffer());
    _log('Sent ProfileEdited to=$recipientUserId editor=$editorUserId');
  }

  // SYNC_PROTOCOL §10.2 UsernameChanged fanout. Empty `newUsername`
  // signals "user cleared their handle".
  void _enqueueUsernameChanged({
    required String recipientUserId,
    required String editorUserId,
    required String newUsername,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sep = pb.ServerEventPayload(
      version: 1,
      type: pb.ServerEventType.USERNAME_CHANGED,
      usernameChanged: pb.UsernameChanged(
        userId: editorUserId,
        newUsername: newUsername,
        changedAtMs: fixnum.Int64(now),
      ),
    );
    final payload = Uint8List.fromList([0x53, ...sep.writeToBuffer()]);

    final channelId = state.channels.values
        .firstWhere(
          (ch) =>
              ch.members.contains(editorUserId) &&
              ch.members.contains(recipientUserId),
          orElse: () => state.channels.values.first,
        )
        .channelId;

    final pushEnv = pb.Envelope(
      opId: state.generateUuid(),
      channelId: channelId,
      resourceSeq: fixnum.Int64(0),
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: '',
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(state.nextDeliverySeq(channelId)),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    _sendToUser(recipientUserId, pushFrame.writeToBuffer());
    _log('Sent UsernameChanged to=$recipientUserId editor=$editorUserId '
        'new=$newUsername');
  }

  // SYNC_PROTOCOL §10.2 ChannelEdited fanout. *Present flags carry
  // proto3-`optional` semantics: when true, the field is populated on
  // the wire (empty string == "user cleared this"); when false the
  // field is absent and recipients leave their cached value alone.
  // Wired to PATCH /v3.0/channels/{id} (_handlePatchChannel).
  void _enqueueChannelEdited({
    required String recipientUserId,
    required String channelId,
    required bool namePresent,
    String? name,
    required bool avatarUrlPresent,
    String? avatarUrl,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final body = pb.ChannelEdited(
      channelId: channelId,
      editedAtMs: fixnum.Int64(now),
    );
    if (namePresent) body.name = name ?? '';
    if (avatarUrlPresent) body.avatarUrl = avatarUrl ?? '';
    final sep = pb.ServerEventPayload(
      version: 1,
      type: pb.ServerEventType.CHANNEL_EDITED,
      channelEdited: body,
    );
    final payload = Uint8List.fromList([0x53, ...sep.writeToBuffer()]);
    final pushEnv = pb.Envelope(
      opId: state.generateUuid(),
      channelId: channelId,
      resourceSeq: fixnum.Int64(0),
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: '', // server-authored
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(state.nextDeliverySeq(channelId)),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    _sendToUser(recipientUserId, pushFrame.writeToBuffer());
    _log('Sent ChannelEdited to=$recipientUserId channel=$channelId');
  }

  // SYNC_PROTOCOL §10.2 ChannelDeleted fanout. Recipients tombstone the
  // channel locally. Not wired to a REST route yet — call site for
  // future DELETE /v3.0/channels/{id} or manual testing.
  void _enqueueChannelDeleted({
    required String recipientUserId,
    required String channelId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sep = pb.ServerEventPayload(
      version: 1,
      type: pb.ServerEventType.CHANNEL_DELETED,
      channelDeleted: pb.ChannelDeleted(
        channelId: channelId,
        deletedAtMs: fixnum.Int64(now),
      ),
    );
    final payload = Uint8List.fromList([0x53, ...sep.writeToBuffer()]);
    final pushEnv = pb.Envelope(
      opId: state.generateUuid(),
      channelId: channelId,
      resourceSeq: fixnum.Int64(0),
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: '', // server-authored
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(state.nextDeliverySeq(channelId)),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    _sendToUser(recipientUserId, pushFrame.writeToBuffer());
    _log('Sent ChannelDeleted to=$recipientUserId channel=$channelId');
  }

  // Build a WS_PUSH WsEnvelope carrying a ChatPayload TYPE_MESSAGE_CREATE
  // from [senderUserId] in [channelId] and enqueue it for [recipientUserId].
  // Used to seed an opening message into the seed-peer DM so the channel
  // shows up in the chat list (which JOINs on `last_message_id`, hiding
  // channels with no messages).
  void _enqueueWelcomeMessage({
    required String recipientUserId,
    required String channelId,
    required String senderUserId,
    required String body,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final messageId = state.generateUuid();
    final chatPayload = pb.ChatPayload(
      version: 1,
      type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
      messageId: messageId,
      body: body,
      contentType: 'text/plain',
    );
    final pushEnv = pb.Envelope(
      opId: state.generateUuid(),
      channelId: channelId,
      resourceSeq: fixnum.Int64(1),
      clientTimestampMs: fixnum.Int64(now),
      payload: chatPayload.writeToBuffer(),
      senderUserId: senderUserId,
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(state.nextDeliverySeq(channelId)),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    state.enqueueUndelivered(recipientUserId, pushFrame.writeToBuffer());
    _log('Enqueued welcome message for $recipientUserId channel=$channelId '
        'body="$body"');
  }

  // Build a WS_PUSH WsEnvelope carrying a MessageStateChanged
  // ServerEventPayload and either send it live (if the recipient — i.e.
  // the original message author — has an open WS) or enqueue it. Used to
  // flip the author's tick from sent → delivered (and later read).
  void _enqueueMessageStateChanged({
    required String recipientUserId,
    required String channelId,
    required String messageId,
    required pb.MessageStateValue newState,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sep = pb.ServerEventPayload(
      version: 1,
      type: pb.ServerEventType.MESSAGE_STATE_CHANGED,
      messageStateChanged: pb.MessageStateChanged(
        channelId: channelId,
        messageId: messageId,
        newState: newState,
        changedAtMs: fixnum.Int64(now),
      ),
    );
    final payload = Uint8List.fromList([0x53, ...sep.writeToBuffer()]);
    final pushEnv = pb.Envelope(
      opId: state.generateUuid(),
      channelId: channelId,
      resourceSeq: fixnum.Int64(0),
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: '', // server-authored
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(state.nextDeliverySeq(channelId)),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    // _sendToUser falls back to undelivered queue when offline.
    _sendToUser(recipientUserId, pushFrame.writeToBuffer());
    _log('Sent MessageStateChanged{${newState.name}} '
        'to=$recipientUserId channel=$channelId message=$messageId');
  }

  // Fan an `ephemeral=true` envelope to currently-connected channel
  // members. Skips the undelivered queue, never produces an ACK, never
  // records op_id_seen — pure best-effort signal.
  void _fanoutEphemeral(
    pb.Envelope env,
    String senderUserId,
    ChannelRecord channel,
    int now,
  ) {
    final pushEnv = pb.Envelope(
      opId: env.opId,
      channelId: env.channelId,
      resourceSeq: env.resourceSeq,
      clientTimestampMs: env.clientTimestampMs,
      payload: env.payload,
      ephemeral: true,
      senderUserId: senderUserId,
      serverTimestampMs: fixnum.Int64(now),
      // No delivery_sequence — ephemeral envelopes don't participate in
      // recipient-side ordering. Field defaults to 0 on the wire.
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    final pushBytes = pushFrame.writeToBuffer();
    for (final memberId in channel.members) {
      if (memberId == senderUserId) continue;
      final sockets = state.wsConnections[memberId];
      if (sockets == null || sockets.isEmpty) continue; // drop if offline
      for (final ws in sockets) {
        try {
          ws.add(pushBytes);
        } catch (e) {
          _log('Ephemeral fanout error to $memberId: $e');
        }
      }
    }
  }

  // Demo helper: when the human user types in a seed-peer DM, echo back
  // a typing indicator from the seed peer so the AppBar subtitle becomes
  // visible without a second device. Fires `is_typing=true`, then `false`
  // after 2.5s (well before the 6s recipient TTL on the human side).
  void _scheduleSeedPeerTypingEcho(String channelId, List<int> payload) {
    // Only respond to typing-true events; ignore the user's own typing-false.
    if (payload.isEmpty) return;
    pb.ChatPayload chat;
    try {
      chat = pb.ChatPayload.fromBuffer(payload);
    } catch (_) {
      return;
    }
    if (chat.type != pb.ChatPayloadType.TYPE_TYPING) return;
    if (!chat.isTyping) return;

    void send(bool isTyping) {
      // The seed peer is a client, so it echoes a ChatPayload, not a
      // server event (decision 56).
      final replyBytes = pb.ChatPayload(
        version: 1,
        type: pb.ChatPayloadType.TYPE_TYPING,
        isTyping: isTyping,
      ).writeToBuffer();
      final now = DateTime.now().millisecondsSinceEpoch;
      final pushEnv = pb.Envelope(
        opId: state.generateUuid(),
        channelId: channelId,
        resourceSeq: fixnum.Int64(0),
        clientTimestampMs: fixnum.Int64(now),
        payload: replyBytes,
        ephemeral: true,
        senderUserId: seedPeerUserId,
        serverTimestampMs: fixnum.Int64(now),
      );
      final frame = pb.WsEnvelope(type: pb.WsType.WS_PUSH, push: pushEnv);
      final bytes = frame.writeToBuffer();
      final channel = state.channels[channelId];
      if (channel == null) return;
      for (final memberId in channel.members) {
        if (memberId == seedPeerUserId) continue;
        final sockets = state.wsConnections[memberId];
        if (sockets == null || sockets.isEmpty) continue;
        for (final ws in sockets) {
          try {
            ws.add(bytes);
          } catch (_) {}
        }
      }
    }

    // Heartbeat the seed-peer typing for ~6s so a realistic typing burst
    // exercises the receiver-side TTL refresh path. Cadence matches the
    // human client's 3s heartbeat in chat.dart.
    send(true);
    _timer(const Duration(milliseconds: 3000), () => send(true));
    _timer(const Duration(milliseconds: 6000), () => send(false));
  }

  // Pull `message_id` out of an inbound ChatPayload. The wire carries
  // `v3-chat-payload.proto` and nothing else (§6a.1) — a JSON body is
  // rejected as `validation_failed` long before this, so there is no
  // fallback here. A leading 0x53 means server event, not chat content.
  /// True only for the two ChatPayload types that introduce a new
  /// message. An edit / delete / reaction targets a message that was
  /// already delivered, so receipting them would re-announce a
  /// lifecycle transition that already happened.
  /// The `ChatPayload.type` of a client payload, or null when the bytes
  /// aren't one (a server event, or soup).
  pb.ChatPayloadType? _chatTypeOf(List<int> payload) {
    if (payload.isEmpty || payload[0] == 0x53) return null;
    try {
      return pb.ChatPayload.fromBuffer(payload).type;
    } catch (_) {
      return null;
    }
  }

  bool _isReadReceipt(List<int> payload) =>
      _chatTypeOf(payload) == pb.ChatPayloadType.TYPE_READ_RECEIPT;

  bool _isMessageCreate(List<int> payload) {
    final type = _chatTypeOf(payload);
    return type == pb.ChatPayloadType.TYPE_MESSAGE_CREATE ||
        type == pb.ChatPayloadType.TYPE_MESSAGE_FORWARD;
  }

  String? _extractMessageId(List<int> payload) {
    if (payload.isEmpty) return null;
    if (payload[0] == 0x53) return null;
    try {
      final chat = pb.ChatPayload.fromBuffer(payload);
      if (chat.messageId.isNotEmpty) return chat.messageId;
    } catch (_) {
      // Not a ChatPayload — nothing to receipt.
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Seed peer auto-reply
  // ---------------------------------------------------------------------------

  void _scheduleSeedPeerReply(
      String channelId, String realUserId, List<int> incomingPayload) {
    // The wire is protobuf-only (§6a.1) — an undecodable payload never
    // reaches here in strict mode, and in lax mode we fall back to a
    // canned greeting rather than guessing at the encoding.
    var replyBody = 'Hello from Seed Peer!';
    try {
      final incoming = pb.ChatPayload.fromBuffer(incomingPayload);
      if (incoming.body.isNotEmpty) replyBody = 'Echo: ${incoming.body}';
    } catch (_) {
      // Leave the canned greeting.
    }
    _timer(const Duration(seconds: 1), () {
      if (state.channels.containsKey(channelId)) {
        _sendPeerMessage(channelId, seedPeerUserId, replyBody);
      }
    });
  }

  /// Fan a `ChatPayload{TYPE_MESSAGE_CREATE}` from [senderUserId] to
  /// every other member of [channelId].
  ({String messageId, String opId}) _sendPeerMessage(
          String channelId, String senderUserId, String body) =>
      _fanoutPeerChatPayload(
        channelId,
        senderUserId,
        pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
          messageId: state.generateUuid(),
          body: body,
          contentType: 'text/plain',
        ),
      );

  /// Fan an arbitrary peer-authored [payload] to every other member of
  /// [channelId] as a WS_PUSH — the same path a relayed client op takes,
  /// which is what makes edits / deletes / reactions injectable at all:
  /// the server never parses any of them (V3_ARCHITECTURE decision 12).
  ({String messageId, String opId}) _fanoutPeerChatPayload(
      String channelId, String senderUserId, pb.ChatPayload payload) {
    final channel = state.channels[channelId];
    if (channel == null) throw StateError('unknown channel $channelId');
    final now = DateTime.now().millisecondsSinceEpoch;
    final deliverySeq = state.nextDeliverySeq(channelId);
    final messageId = payload.messageId;

    final opId = state.generateUuid();
    final pushEnv = pb.Envelope(
      opId: opId,
      channelId: channelId,
      resourceSeq: fixnum.Int64(1),
      clientTimestampMs: fixnum.Int64(now),
      payload: payload.writeToBuffer(),
      senderUserId: senderUserId,
      serverTimestampMs: fixnum.Int64(now),
      deliverySequence: fixnum.Int64(deliverySeq),
    );
    final pushBytes =
        pb.WsEnvelope(type: pb.WsType.WS_PUSH, push: pushEnv).writeToBuffer();

    for (final memberId in channel.members) {
      if (memberId == senderUserId) continue;
      _sendToUser(memberId, pushBytes);
    }
    _log('Peer ${payload.type.name}: channel=$channelId '
        'from=$senderUserId deliverySeq=$deliverySeq message=$messageId');
    return (messageId: messageId, opId: opId);
  }

  // ---------------------------------------------------------------------------
  // HTTP helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest req) async {
    final raw = await utf8.decodeStream(req);
    if (raw.isEmpty) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  void _respondJson(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    req.response.close();
  }

  /// Returns the session if Authorization header is valid, else responds 401
  /// and returns null.
  /// AUTH_CONTRACT §2.4: authenticate, then enforce the
  /// `403 USERNAME_REQUIRED` gate. Pass [usernameExempt] for the short
  /// exempt list — `GET`/`PATCH /v3.0/users/me`,
  /// `POST /v3.0/users/username/check`, `POST /v3.0/auth/session/*`,
  /// `POST /v3.0/auth/phone/rebind/*`.
  ///
  /// ponytail: the WS upgrade (§6) is deliberately NOT gated — a client
  /// that has not picked a handle yet has nothing to send and the
  /// reconnect dance buys nothing. Gate it in `_handleWsUpgrade` if a
  /// server-side test ever needs it.
  SessionRecord? _authenticate(HttpRequest req, {bool usernameExempt = false}) {
    final authHeader = req.headers.value('authorization');
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      _respondJson(req, 401, {
        'error': {'code': 'MISSING_ACCESSKEY', 'message': 'Authorization header required'}
      });
      return null;
    }
    final token = authHeader.substring('Bearer '.length);
    final session = state.lookupByAccesskey(token);
    if (session == null) {
      _respondJson(req, 401, {
        'error': {'code': 'INVALID_ACCESSKEY', 'message': 'accesskey is not valid'}
      });
      return null;
    }
    if (!usernameExempt && state.usersById[session.userId]?.username == null) {
      _respondJson(req, 403, {
        'error': {
          'code': 'USERNAME_REQUIRED',
          'message': 'Set a username via PATCH /v3.0/users/me first'
        }
      });
      return null;
    }
    return session;
  }

  // ---------------------------------------------------------------------------
  // media-ms assets — V3_RELEASE_PLAN §4.2, decisions 8 / 22 / 36
  //
  // Same four-step shape as the real service: presign an upload, PUT the
  // bytes at the signed url, mark the record complete, presign a
  // download. The "object store" is a map in this process and the signed
  // urls point back at this server — good enough to drive the client's
  // whole upload path in a test, and the only part that differs from
  // production is where the bytes land.
  // ---------------------------------------------------------------------------

  static const int _maxUploadBytes = 25 * 1024 * 1024;
  final Map<String, _AssetRecord> assets = {};

  Future<bool> _tryAssetRoute(
    HttpRequest req,
    String method,
    String path,
  ) async {
    if (method == 'GET' && path == '/v3.0/assets/upload/presigned_url') {
      await _handlePresignUpload(req);
      return true;
    }
    if (method == 'GET' &&
        path.startsWith('/v3.0/assets/download/') &&
        path.endsWith('/presigned_url')) {
      await _handlePresignDownload(req, path);
      return true;
    }
    if (method == 'PUT' &&
        path.startsWith('/v3.0/assets/') &&
        path.endsWith('/status')) {
      await _handleAssetStatus(req, path);
      return true;
    }
    if (path.startsWith('/v3.0/_blob/') && (method == 'PUT' || method == 'GET')) {
      await _handleBlob(req, method, path);
      return true;
    }
    if (method == 'PATCH' && _memberPath(path) != null) {
      await _handlePatchChannelMember(req, _memberPath(path)!);
      return true;
    }
    if (method == 'PATCH' && path.startsWith('/v3.0/channels/')) {
      await _handlePatchChannel(req, path);
      return true;
    }
    return false;
  }

  /// `GET /v3.0/assets/upload/presigned_url?ext&category&size`. The
  /// content type is derived from `ext` and signed, so the PUT must
  /// send the same one.
  Future<void> _handlePresignUpload(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    final q = req.uri.queryParameters;
    final ext = q['ext'];
    final category = q['category'];
    final size = int.tryParse(q['size'] ?? '');
    if (ext == null || ext.isEmpty || category == null || size == null) {
      _respondJson(req, 400, {
        'error': {
          'code': 'validation_failed',
          'message': 'ext, category and size are required'
        }
      });
      return;
    }
    if (size < 1 || size > _maxUploadBytes) {
      _respondJson(req, 400, {
        'error': {
          'code': 'validation_failed',
          'message': 'size must be between 1 and $_maxUploadBytes bytes'
        }
      });
      return;
    }
    final fileId = state.generateUuid();
    assets[fileId] = _AssetRecord(
      owner: session.userId,
      category: category,
      contentType: _contentTypeForExt(ext),
      declaredSize: size,
    );
    _record(req, const {}, 200);
    _respondJson(req, 200, {
      'url': '${apiUrl.toString()}/v3.0/_blob/$fileId',
      'fileId': fileId,
    });
    _log('Presigned upload $fileId owner=${session.userId} size=$size');
  }

  /// The "object store". Unauthenticated on purpose — holding the
  /// (unguessable) fileId is the capability, exactly as in the real
  /// presigned-url model.
  Future<void> _handleBlob(
    HttpRequest req,
    String method,
    String path,
  ) async {
    final fileId = path.substring('/v3.0/_blob/'.length);
    final record = assets[fileId];
    if (record == null) {
      _respondJson(req, 404, {
        'error': {'code': 'NOT_FOUND', 'message': 'Unknown fileId: $fileId'}
      });
      return;
    }
    if (method == 'PUT') {
      final builder = BytesBuilder();
      await for (final chunk in req) {
        builder.add(chunk);
      }
      record.bytes = builder.takeBytes();
      _record(req, {'fileId': fileId, 'bytes': record.bytes!.length}, 200);
      _respondJson(req, 200, {'fileId': fileId});
      _log('Blob stored $fileId (${record.bytes!.length} bytes)');
      return;
    }
    final bytes = record.bytes;
    if (bytes == null) {
      _respondJson(req, 404, {
        'error': {'code': 'NOT_FOUND', 'message': 'Nothing uploaded yet'}
      });
      return;
    }
    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType.parse(record.contentType);
    req.response.add(bytes);
    await req.response.close();
  }

  /// `PUT /v3.0/assets/{fileId}/status` — owner scoped, once.
  Future<void> _handleAssetStatus(HttpRequest req, String path) async {
    final session = _authenticate(req);
    if (session == null) return;
    final fileId = path.substring(
      '/v3.0/assets/'.length,
      path.length - '/status'.length,
    );
    final body = await _readJsonBody(req);
    final record = assets[fileId];
    if (record == null || record.owner != session.userId) {
      _record(req, body, 404);
      _respondJson(req, 404, {
        'error': {'code': 'NOT_FOUND', 'message': 'file not found'}
      });
      return;
    }
    if (record.complete) {
      _record(req, body, 400);
      _respondJson(req, 400, {
        'error': {
          'code': 'ALREADY_MARKED',
          'message': 'file status is already set'
        }
      });
      return;
    }
    record.complete = body['status'] == true;
    _record(req, body, 200);
    _respondJson(req, 200, <String, dynamic>{});
  }

  /// `GET /v3.0/assets/download/{fileId}/presigned_url` — any
  /// authenticated user may resolve a fileId they were given.
  Future<void> _handlePresignDownload(HttpRequest req, String path) async {
    final session = _authenticate(req);
    if (session == null) return;
    final fileId = path.substring(
      '/v3.0/assets/download/'.length,
      path.length - '/presigned_url'.length,
    );
    final record = assets[fileId];
    if (record == null) {
      _record(req, const {}, 404);
      _respondJson(req, 404, {
        'error': {'code': 'NOT_FOUND', 'message': 'file not found'}
      });
      return;
    }
    _record(req, const {}, 200);
    _respondJson(req, 200, {
      'fileId': fileId,
      'contentType': record.contentType,
      'url': '${apiUrl.toString()}/v3.0/_blob/$fileId',
    });
  }

  /// `PATCH /v3.0/channels/{id}/members/{user_id}` — decision 80's role
  /// change. Owner and admins only; never on yourself and never on the
  /// owner. Fanned out to every member (the actor included) as a
  /// `ChannelMemberAdded{members:[target], role}` re-announce, which is
  /// what makes the projection an upsert rather than an insert.
  Future<void> _handlePatchChannelMember(
    HttpRequest req,
    ({String channelId, String userId}) target,
  ) async {
    final session = _authenticate(req);
    if (session == null) return;

    final body = await _readJsonBody(req);
    final pre = _validateRestOp(
      session: session,
      body: body,
      resourceId: target.channelId,
    );
    if (pre != null) {
      _respondOutcome(req, body, pre);
      return;
    }

    final role = body['role'];
    if (role != 'admin' && role != 'member') {
      _record(req, body, 400);
      _respondJson(req, 400, {
        'error': {
          'code': 'validation_failed',
          'message': 'role must be "admin" or "member"'
        }
      });
      return;
    }

    final channel = state.channels[target.channelId];
    if (channel == null) {
      _record(req, body, 404);
      _respondJson(req, 404, {
        'error': {
          'code': 'NOT_FOUND',
          'message': 'Unknown channel: ${target.channelId}'
        }
      });
      return;
    }
    if (!channel.members.contains(session.userId) ||
        channel.roleOf(session.userId) == 'member' ||
        target.userId == session.userId ||
        target.userId == channel.ownerUserId) {
      _record(req, body, 403);
      _respondJson(req, 403, {
        'error': {
          'code': 'FORBIDDEN',
          'message': 'Only the owner or an admin can change another '
              "member's role"
        }
      });
      return;
    }
    if (!channel.members.contains(target.userId)) {
      _record(req, body, 404);
      _respondJson(req, 404, {
        'error': {
          'code': 'NOT_FOUND',
          'message': 'Not a member: ${target.userId}'
        }
      });
      return;
    }

    if (role == 'admin') {
      channel.admins.add(target.userId);
    } else {
      channel.admins.remove(target.userId);
    }
    state.markDirty();
    _log('Role change: ${target.channelId} ${target.userId} -> $role '
        'by=${session.userId}');

    final result = {
      'channel_id': target.channelId,
      'user_id': target.userId,
      'role': role,
    };
    final opId = body['op_id'];
    if (opId is String) {
      state.recordOutcome(session.userId, opId,
          StoredOutcome(success: true, status: 200, body: result));
    }
    _record(req, body, 200);
    _respondJson(req, 200, result);

    for (final memberId in channel.members) {
      _enqueueChannelMemberAdded(
        recipientUserId: memberId,
        channelId: target.channelId,
        newMemberUserIds: [target.userId],
        role: role as String,
      );
    }
  }

  /// `PATCH /v3.0/channels/{id}` — name / avatarUrl, fanned out as
  /// `ChannelEdited` (SYNC_PROTOCOL §10.2) to every other member.
  Future<void> _handlePatchChannel(HttpRequest req, String path) async {
    final session = _authenticate(req);
    if (session == null) return;
    final channelId = path.substring('/v3.0/channels/'.length);
    final body = await _readJsonBody(req);
    if (channelId.isEmpty || channelId.contains('/')) {
      _respondJson(req, 400, {
        'error': {'code': 'MALFORMED_REQUEST', 'message': 'channel_id required'}
      });
      return;
    }
    final pre = _validateRestOp(
      session: session,
      body: body,
      resourceId: channelId,
    );
    if (pre != null) {
      _respondOutcome(req, body, pre);
      return;
    }
    final channel = state.channels[channelId];
    if (channel == null) {
      _record(req, body, 404);
      _respondJson(req, 404, {
        'error': {'code': 'NOT_FOUND', 'message': 'Unknown channel: $channelId'}
      });
      return;
    }
    if (!channel.members.contains(session.userId)) {
      _record(req, body, 403);
      _respondJson(req, 403, {
        'error': {'code': 'FORBIDDEN', 'message': 'Not a member of channel'}
      });
      return;
    }

    final namePresent = body.containsKey('name');
    final avatarPresent = body.containsKey('avatarUrl');
    if (namePresent) channel.name = body['name'] as String?;
    if (avatarPresent) channel.avatarUrl = body['avatarUrl'] as String?;
    state.markDirty();

    final result = {
      'channel_id': channelId,
      'name': channel.name,
      'avatarUrl': channel.avatarUrl,
    };
    final opId = body['op_id'];
    if (opId is String) {
      state.recordOutcome(session.userId, opId,
          StoredOutcome(success: true, status: 200, body: result));
    }
    _record(req, body, 200);
    _respondJson(req, 200, result);

    for (final memberId in channel.members) {
      if (memberId == session.userId) continue;
      _enqueueChannelEdited(
        recipientUserId: memberId,
        channelId: channelId,
        namePresent: namePresent,
        name: channel.name,
        avatarUrlPresent: avatarPresent,
        avatarUrl: channel.avatarUrl,
      );
    }
  }

  /// Same extension → type mapping media-ms does via
  /// `libs/content-type-utils`.
  static String _contentTypeForExt(String ext) => switch (ext.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        'txt' => 'text/plain',
        'mp4' => 'video/mp4',
        'mp3' => 'audio/mpeg',
        _ => 'application/octet-stream',
      };
}

/// One media-ms record plus its bytes, which the real service keeps in
/// an object store.
class _AssetRecord {
  final String owner;
  final String category;
  final String contentType;
  final int declaredSize;
  Uint8List? bytes;
  bool complete = false;

  _AssetRecord({
    required this.owner,
    required this.category,
    required this.contentType,
    required this.declaredSize,
  });
}
