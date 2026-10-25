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
import 'package:vartalap_crypto/vartalap_crypto.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;

import 'mock_peers.dart';

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

  /// `<user_id>/<device_id>`: which device a socket or a fanout belongs
  /// to (SYNC_PROTOCOL §10.3 item 5 — the sending device is skipped).
  String get deviceKey => '$userId/$deviceId';

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

/// §19 decision 1 — the longest a stored envelope is kept, and how long
/// when its sender set no `ttl_sec`.
const int kMaxTtlSec = 30 * 24 * 60 * 60;

/// One fanout, stored once (SYNC_PROTOCOL §10.6): the WS_PUSH frame,
/// the users it went to, and the device that sent it, whose own pull
/// leaves it out. Each user's pull is built from these at read time.
class FanoutRecord {
  final String opId;
  final int serverTimestampMs;
  final Uint8List frame;
  final Set<String> recipients;

  /// The sender's `ttl_sec` from the stamp, capped at [kMaxTtlSec]; 0
  /// (unset) means [kMaxTtlSec]. Past it, no pull returns the frame.
  final int expiresAtMs;

  /// [SessionRecord.deviceKey] of the socket the op came in on; null
  /// for a fanout no socket sent (a REST side effect, a test peer).
  final String? senderDevice;

  FanoutRecord({
    required this.opId,
    required this.serverTimestampMs,
    required this.frame,
    required this.recipients,
    required this.expiresAtMs,
    this.senderDevice,
  });

  Map<String, dynamic> toPersistJson() => {
        'opId': opId,
        'serverTimestampMs': serverTimestampMs,
        'expiresAtMs': expiresAtMs,
        'frame': base64Encode(frame),
        'recipients': recipients.toList(),
        'senderDevice': senderDevice,
      };

  static FanoutRecord fromPersistJson(Map<String, dynamic> j) => FanoutRecord(
        opId: j['opId'] as String,
        serverTimestampMs: j['serverTimestampMs'] as int,
        expiresAtMs: j['expiresAtMs'] as int? ??
            (j['serverTimestampMs'] as int) + kMaxTtlSec * 1000,
        frame: base64Decode(j['frame'] as String),
        recipients: (j['recipients'] as List<dynamic>).cast<String>().toSet(),
        senderDevice: j['senderDevice'] as String?,
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
  // §7.1 dedup window: '<user_id>:<op_id>' -> the outcome we already
  // returned for it. ponytail: unbounded and in-memory only (the spec
  // wants 10k/user, 7 days) — a mock never runs long enough to care.
  final Map<String, StoredOutcome> outcomes = {};
  final Map<String, List<WebSocket>> wsConnections = {};
  /// The [SessionRecord.deviceKey] of every open socket.
  final Map<WebSocket, String> socketDevice = {};
  // Every fanout (SYNC_PROTOCOL.md §10.6), stored once, by op_id in
  // write order, pushed live or not. A pull reads it; nothing is ever
  // removed. ponytail: no 30-day retention; a mock never lives that
  // long.
  final Map<String, FanoutRecord> fanouts = {};
  /// Demo mode (`--seed-peer`): users who have already been sent the
  /// seed peer's welcome message. Trim 4 left no DM channel row to
  /// check for, and the welcome is what introduces the derived
  /// channel, so "have we said hello yet" is its own fact.
  final Set<String> welcomedUsers = {};
  /// AUTH_CONTRACT §17, see [KeyDirectory].
  /// ponytail: in memory only, not persisted; a restarted mock makes
  /// every phone publish again on its next open.
  final KeyDirectory deviceKeys = {};

  final Random _rng = Random.secure();

  // ---- Persistence -----------------------------------------------------

  /// Path to the JSON state file, or null if persistence is disabled.
  String? persistencePath;
  Timer? _saveTimer;

  /// Schedule a debounced save. Every mutation site calls this; the
  /// 200ms window coalesces bursts (an OTP-verify touches users +
  /// sessions + channel + fanouts in quick succession — one write
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
        'fanouts': fanouts.values.map((r) => r.toPersistJson()).toList(),
        'welcomedUsers': welcomedUsers.toList(),
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
      for (final entry in (j['fanouts'] as List? ?? [])) {
        final r = FanoutRecord.fromPersistJson(entry as Map<String, dynamic>);
        fanouts[r.opId] = r;
      }
      welcomedUsers.addAll(
          (j['welcomedUsers'] as List? ?? []).cast<String>());
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

  /// §7.1 — the outcome already returned for [opId], if any.
  StoredOutcome? storedOutcome(String userId, String opId) =>
      outcomes['$userId:$opId'];

  void recordOutcome(String userId, String opId, StoredOutcome outcome) {
    outcomes['$userId:$opId'] = outcome;
  }

  void addWsConnection(SessionRecord session, WebSocket ws) {
    wsConnections.putIfAbsent(session.userId, () => []).add(ws);
    socketDevice[ws] = session.deviceKey;
  }

  void removeWsConnection(String userId, WebSocket ws) {
    wsConnections[userId]?.remove(ws);
    socketDevice.remove(ws);
  }

  /// Store the WS_PUSH [frame] for [userId]: once per op_id, a
  /// fanout's later recipients joining its record.
  void recordFanout(String userId, Uint8List frame, {String? senderDevice}) {
    final push = pb.WsEnvelope.fromBuffer(frame).push;
    fanouts
        .putIfAbsent(
          push.opId,
          () => FanoutRecord(
            opId: push.opId,
            serverTimestampMs: push.serverTimestampMs.toInt(),
            expiresAtMs: push.serverTimestampMs.toInt() +
                min(push.ttlSec == 0 ? kMaxTtlSec : push.ttlSec, kMaxTtlSec) *
                    1000,
            frame: frame,
            recipients: {},
            senderDevice: senderDevice,
          ),
        )
        .recipients
        .add(userId);
    markDirty();
  }

  /// §10.6 — what [session]'s pull sees: every unexpired fanout naming
  /// its user, stamped at or after [since], but the ones its own device
  /// sent; ordered by (server_timestamp_ms, op_id).
  List<FanoutRecord> timeline(SessionRecord session, int since) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return fanouts.values
        .where((r) =>
            r.recipients.contains(session.userId) &&
            r.senderDevice != session.deviceKey &&
            r.serverTimestampMs >= since &&
            r.expiresAtMs > now)
        .toList()
    ..sort((a, b) {
      final byStamp = a.serverTimestampMs.compareTo(b.serverTimestampMs);
      return byStamp != 0 ? byStamp : a.opId.compareTo(b.opId);
    });
  }

  final Map<String, int> _readUpTo = {};

  /// Test hook: the frames fanned to [userId] since the last call, in
  /// write order. For a user with no client (the seed peer): "what
  /// arrived since I last looked". Removes nothing.
  List<Uint8List> newFramesFor(String userId) {
    final records = fanouts.values.toList();
    final from = _readUpTo[userId] ?? 0;
    _readUpTo[userId] = records.length;
    return [
      for (final r in records.skip(from))
        if (r.recipients.contains(userId)) r.frame,
    ];
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

/// Trim 4 (`design/protocol/TRIM_4_12_CONTRACT.md` §1) — the derived
/// DM channel id.
///
/// Deliberately a second implementation rather than a call into
/// `package:vartalap_sync`: the mock stands in for chat-server, and a
/// mock that shares the client's arithmetic could never disagree with
/// it. If the two ever drift, the client sees `forbidden` here, which
/// is exactly what the real server would answer.
String mockDmChannelId(String a, String b) {
  final low = a.compareTo(b) <= 0 ? a : b;
  final high = a.compareTo(b) <= 0 ? b : a;
  final hex = sha256.convert(utf8.encode('$low\u0000$high')).toString();
  return 'd${hex.substring(0, 31)}';
}

/// A derived DM id is `d` plus 31 lowercase hex chars, no dashes.
///
/// The test is the full shape, not the prefix: a group id is a dashed
/// UUID, so the dash at index 8 keeps the two id spaces provably
/// disjoint even for the ~1/16 of UUIDs that happen to start with `d`.
final RegExp _dmChannelIdShape = RegExp(r'^d[0-9a-f]{31}$');
bool isMockDmChannelId(String channelId) =>
    _dmChannelIdShape.hasMatch(channelId);

/// AUTH_CONTRACT §2: a `user_id` is 9 lowercase hex chars. A `peer`
/// that is not one cannot be part of any derivation, so it is a
/// malformed field rather than a wrong one.
bool _isWellFormedUserId(String id) =>
    RegExp(r'^[0-9a-f]{9}$').hasMatch(id);

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

/// The mock's VAPID public key (AUTH_CONTRACT §5.0): the shape of an
/// uncompressed P-256 point, base64url without padding, 87 chars.
const String kMockVapidPublicKey =
    'BMockVapidKey0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-0123456789';

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
  final Uint8List payload;
  final String? rejectReason;
  RecordedEnvelope({
    required this.opId,
    required this.channelId,
    required this.payload,
    required this.rejectReason,
  });
}

/// Stored per-op outcome for the §7.1 dedup window. WS ops keep an ACK
/// outcome; REST ops keep the literal response they got.
class StoredOutcome {
  final bool success;
  final String? reason; // WS permanent-reject reason
  final int? serverTimestampMs; // WS success: replayed on a retry
  final int? status; // REST status
  final Map<String, dynamic>? body; // REST body
  const StoredOutcome({
    required this.success,
    this.reason,
    this.serverTimestampMs,
    this.status,
    this.body,
  });
}

/// The v3 mock chat-server, startable in-process.
///
/// `strict: true` (the default) turns it into a contract enforcer:
/// op_id prefix binding, WS batch cap,
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

  /// Contract enforcement (SYNC_PROTOCOL §6a.3, §7, §11.3).
  final bool strict;

  /// Every REST request handled, in order. Test hook.
  final List<RecordedRequest> requests = [];

  /// Every non-ephemeral WS envelope received, in order. Test hook.
  final List<RecordedEnvelope> envelopes = [];

  /// Every accepted `ephemeral=true` WS envelope, in order. They never
  /// reach [envelopes] (no ACK, no dedup). Test hook.
  final List<RecordedEnvelope> ephemeralEnvelopes = [];

  /// The simulated users' crypto (decision 188): the seed peer and anyone
  /// looked up who never signed in.
  late final MockPeers peers = MockPeers(state.deviceKeys, state.generateUuid);

  /// What the simulated users received, opened as their phone would, in
  /// arrival order: a test's view of "did the other side get it". Test hook.
  final List<({String userId, pb.Envelope env, Uint8List payload})>
      peerOpened = [];

  /// Re-send requests the simulated users received. Test hook.
  final List<({String userId, pb.Envelope env})> peerResendRequests = [];

  /// While set, simulated users hold their answers to re-send requests
  /// until [releaseResends], so a test can see the placeholder first.
  bool holdResends = false;
  final _heldResends = <(String, E2eeCrypto, pb.Envelope)>[];

  Future<void> releaseResends() async {
    holdResends = false;
    final held = [..._heldResends];
    _heldResends.clear();
    for (final (userId, crypto, env) in held) {
      await _answerResend(userId, crypto, env);
    }
    await settled();
  }

  Future<void> _peerSends = Future.value();
  Future<void> _peerReceives = Future.value();

  /// Every simulated-user send and receive so far is done: sealed and
  /// fanned out, or opened into [peerOpened].
  Future<void> settled() async {
    await _peerSends;
    await _peerReceives;
  }

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
    if (seedPeer) await server.peers.forUser(seedPeerUserId);
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
    state.socketDevice.clear();
    await _http.close(force: true);
  }

  /// Demo timers, cancelled by [stop] so a test never leaks one.
  final Set<Timer> _timers = {};

  /// The server clock for every stored fanout. Never backwards: a pull
  /// asks for what is stamped at or after the client's pointer
  /// (§10.6), so a later write stamped earlier would never be pulled.
  /// ponytail: strictly increasing so tests never tie two ops on one
  /// millisecond and lean on the id tie-break by accident; the real
  /// server makes no such promise. Tests that want a tie pass
  /// `serverTimestampMs`.
  int _lastStamp = 0;
  int _stamp() => _lastStamp =
      max(DateTime.now().millisecondsSinceEpoch, _lastStamp + 1);

  /// message_id → server timestamp of every create / forward the mock
  /// has fanned out: what a peer's client would put in a receipt's
  /// `marker_server_timestamp_ms` (it saw the same stamp on fanout).
  final Map<String, int> messageStamps = {};

  void _recordStamp(List<int> payload, int stamp) {
    if (!_isMessageCreate(payload)) return;
    final id = _extractMessageId(payload);
    if (id != null) messageStamps[id] = stamp;
  }

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

  /// Resolves with [value] once the simulated user's send is out.
  Future<T> _settle<T>(T value) async {
    await _peerSends;
    return value;
  }

  /// Inject an inbound chat message from [senderUserId] (defaults to
  /// the seed peer) into [channelId]. Fans a real `WS_PUSH` carrying a
  /// `ChatPayload{TYPE_MESSAGE_CREATE}` to every other member — stored
  /// for their pulls, and live to the ones with a socket.
  ///
  /// [messageId] and [serverTimestampMs] let a test deliver the create
  /// AFTER ops that target it (SYNC_PROTOCOL §6b: the client copes).
  /// [ttlSec] is the sender's `ttl_sec` (0: the 30-day maximum).
  /// [corrupt]: a byte of the ciphertext flips in transit, so the
  /// recipient cannot decrypt it and asks for a re-send (decision 188).
  Future<({String messageId, String opId})> injectPeerMessage({
    required String channelId,
    required String body,
    String senderUserId = seedPeerUserId,
    String? messageId,
    int? serverTimestampMs,
    int ttlSec = 0,
    bool corrupt = false,
  }) =>
      _settle(_sendPeerMessage(channelId, senderUserId, body,
          messageId: messageId,
          serverTimestampMs: serverTimestampMs,
          ttlSec: ttlSec,
          corrupt: corrupt));

  /// Inject a peer-authored edit of [messageId] (SYNC_PROTOCOL §6a:
  /// the recipient applies it only because [senderUserId] is the
  /// message's author).
  Future<({String messageId, String opId})> injectPeerEdit({
    required String channelId,
    required String messageId,
    required String body,
    String senderUserId = seedPeerUserId,
    int? serverTimestampMs,
  }) =>
      _settle(_fanoutPeerChatPayload(
        channelId,
        senderUserId,
        pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_MESSAGE_UPDATE,
          messageId: messageId,
          body: body,
          contentType: 'text/plain',
        ),
        serverTimestampMs: serverTimestampMs,
      ));

  /// Inject a peer-authored delete (tombstone) of [messageId].
  Future<({String messageId, String opId})> injectPeerDelete({
    required String channelId,
    required String messageId,
    String senderUserId = seedPeerUserId,
    int? serverTimestampMs,
  }) =>
      _settle(_fanoutPeerChatPayload(
        channelId,
        senderUserId,
        pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_MESSAGE_DELETE,
          messageId: messageId,
        ),
        serverTimestampMs: serverTimestampMs,
      ));

  /// Inject a peer reaction on [messageId] — add when [add], remove
  /// otherwise. Any member may react to anyone's message.
  Future<({String messageId, String opId})> injectPeerReaction({
    required String channelId,
    required String messageId,
    required String emoji,
    bool add = true,
    String senderUserId = seedPeerUserId,
    int? serverTimestampMs,
  }) =>
      _settle(_fanoutPeerChatPayload(
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
        serverTimestampMs: serverTimestampMs,
      ));

  /// Inject a peer-authored read receipt marking [messageId] (and
  /// everything before it) as read by [senderUserId] — decision 56's
  /// `ChatPayload{TYPE_READ_RECEIPT}`, not a server event. The marker
  /// timestamp defaults to the stamp the mock gave [messageId]; pass
  /// [markerServerTimestampMs] for a message the mock never saw.
  Future<({String messageId, String opId})> injectPeerReadReceipt({
    required String channelId,
    required String messageId,
    String senderUserId = seedPeerUserId,
    int? markerServerTimestampMs,
  }) async {
    // The default marker is the stamp the peer's phone recorded on opening
    // the message (decision 188): let what is in flight land first.
    await settled();
    return _settle(_injectReceipt(pb.ChatPayloadType.TYPE_READ_RECEIPT, channelId,
        messageId, senderUserId, markerServerTimestampMs));
  }

  /// Inject a peer-authored delivery receipt: [senderUserId]'s device
  /// has stored [messageId] and everything before it (grey ✓✓). Marker
  /// as in [injectPeerReadReceipt].
  Future<({String messageId, String opId})> injectPeerDeliveryReceipt({
    required String channelId,
    required String messageId,
    String senderUserId = seedPeerUserId,
    int? markerServerTimestampMs,
  }) async {
    // The default marker is the stamp the peer's phone recorded on opening
    // the message (decision 188): let what is in flight land first.
    await settled();
    return _settle(_injectReceipt(pb.ChatPayloadType.TYPE_DELIVERY_RECEIPT, channelId,
        messageId, senderUserId, markerServerTimestampMs));
  }

  ({String messageId, String opId}) _injectReceipt(
    pb.ChatPayloadType type,
    String channelId,
    String messageId,
    String senderUserId,
    int? markerServerTimestampMs,
  ) {
    final marker = markerServerTimestampMs ?? messageStamps[messageId];
    if (marker == null) {
      throw StateError('no server timestamp known for $messageId; '
          'pass markerServerTimestampMs');
    }
    return _fanoutPeerChatPayload(
      channelId,
      senderUserId,
      pb.ChatPayload(
        version: 1,
        type: type,
        messageId: messageId,
        markerServerTimestampMs: fixnum.Int64(marker),
      ),
    );
  }

  /// Inject a peer typing indicator as an `ephemeral=true` WS_PUSH —
  /// live-only, no ACK, no dedup, dropped for offline members.
  Future<void> injectPeerTyping({
    required String channelId,
    required bool isTyping,
    String senderUserId = seedPeerUserId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final opId = state.generateUuid();
    final recipients = _recipientsFor(channelId, senderUserId);
    final plain = pb.ChatPayload(
      version: 1,
      type: pb.ChatPayloadType.TYPE_TYPING,
      isTyping: isTyping,
    ).writeToBuffer();
    _peerSends = _peerSends.then((_) async {
      final peer = isMockDmChannelId(channelId) ? recipients.single : null;
      final bytes = peer == null
          ? await _sealGroupFromPeer(
              senderUserId, opId, channelId, recipients, plain,
              ephemeral: true)
          : await _sealFromPeer(senderUserId, opId, channelId, peer, plain,
              ephemeral: true);
      if (bytes == null) return;
      _fanoutEphemeral(
        pb.Envelope(
          opId: opId,
          channelId: channelId,
          clientTimestampMs: fixnum.Int64(now),
          payload: bytes,
          ephemeral: true,
          peer: peer,
        ),
        senderUserId,
        recipients,
        now,
        senderDeviceId: MockPeers.deviceId,
      );
    }).catchError((Object e) => _log('Peer typing failed: $e'));
    return _peerSends;
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

  /// Throw away everything stored for [userId] and report how many
  /// frames were lost. Stands in for a fanout store that did not
  /// survive — the one server-side failure a client cannot detect and
  /// has no way to ask about.
  int dropUndelivered(String userId) {
    var dropped = 0;
    for (final r in state.fanouts.values) {
      if (r.recipients.remove(userId)) dropped++;
    }
    return dropped;
  }

  /// The op_ids of every stored fanout naming [userId] (§10.6), in
  /// write order. Read only.
  List<String> storedOpIds(String userId) => [
        for (final r in state.fanouts.values)
          if (r.recipients.contains(userId)) r.opId,
      ];

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
    // Decision 188: end-to-end encrypted, opaque like on the real server.
    if (payload.length > 3 && payload[0] == kSealedMarker && payload[1] == 1) {
      return true;
    }
    try {
      final chat = pb.ChatPayload.fromBuffer(payload);
      // A real ChatPayload always sets `type`; a byte soup that happens
      // to survive the varint decoder does not.
      return chat.type != pb.ChatPayloadType.TYPE_UNSPECIFIED;
    } catch (_) {
      return false;
    }
  }

  /// Shared §11.2 preamble for REST writes: op_id prefix binding and
  /// §7.1 dedup replay. Returns a [StoredOutcome] when the request must
  /// NOT be applied (either a replay whose stored response we echo, or a
  /// rejection), else null. No ordering check: the server keeps no
  /// ordering state (SYNC_PROTOCOL §6).
  StoredOutcome? _validateRestOp({
    required SessionRecord session,
    required Map<String, dynamic> body,
  }) {
    if (!strict) return null;
    final opId = body['op_id'];
    if (opId is! String || opId.isEmpty) {
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
  /// `ChannelMemberAdded` to everyone in it afterwards — the new member
  /// included, who may have no `ChannelCreated` to go on — except the
  /// [actorUserId]'s device, exactly as on the real server. No actor:
  /// server-authored, everyone hears it.
  void addChannelMember(String channelId, String userId, {String? actorUserId}) {
    final channel = state.channels[channelId];
    if (channel == null) throw StateError('unknown channel $channelId');
    channel.members.add(userId);
    state.markDirty();
    final actor = actorUserId ?? '';
    for (final memberId in channel.members) {
      if (memberId == actor) continue;
      _enqueueChannelMemberAdded(
        recipientUserId: memberId,
        channelId: channelId,
        newMemberUserIds: [userId],
        role: 'member',
        actorUserId: actor,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Request router
  // ---------------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest req) async {
    // Like any origin server with a clock (RFC 9110 §6.6.1); a fresh
    // account's pull pointer starts from the otp/verify one.
    req.response.headers.date = DateTime.now();
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
    } else if (method == 'POST' && path == '/v3.0/auth/otp/resend') {
      await _handleOtpResend(req);
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
    } else if (method == 'PUT' && path == '/v3.0/keys/me') {
      await _handlePutKeys(req);
    } else if (method == 'GET' && path.startsWith('/v3.0/keys/')) {
      await _handleGetKeys(req, path.split('/')[3]);
    } else if (method == 'POST' &&
        path.startsWith('/v3.0/keys/') &&
        path.endsWith('/claim')) {
      await _handleClaimKeys(req, path.split('/')[3]);
    } else if (method == 'POST' && path == '/v3.0/contacts/lookup') {
      await _handleContactLookup(req);
    } else if (method == 'GET' && path == '/v3.0/push/vapid') {
      _handlePushVapid(req);
    } else if (method == 'POST' && path == '/v3.0/push/topic') {
      await _handlePushTopic(req);
    } else if (method == 'POST' && path == '/v3.0/channels') {
      await _handleCreateChannel(req);
    } else if (method == 'GET' &&
        (path == '/v3.0/channels' ||
            (path.startsWith('/v3.0/channels/') &&
                !path.substring('/v3.0/channels/'.length).contains('/')))) {
      await _handleGetChannels(req, path);
    } else if (method == 'POST' &&
        path.startsWith('/v3.0/channels/') &&
        path.endsWith('/members') &&
        path.split('/').length == 5) {
      await _handleAddChannelMembers(req, path.split('/')[3]);
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

  /// §3.3: the same session again; the code stays 000000.
  Future<void> _handleOtpResend(HttpRequest req) async {
    final body = await _readJsonBody(req);
    final session = state.otpSessions[body['sessionId']];
    if (session == null) {
      _respondJson(req, 404, {
        'error': {'code': 'SESSION_NOT_FOUND', 'message': 'Unknown session'}
      });
      return;
    }
    _respondJson(req, 200, {
      'sessionId': session.sessionId,
      'resendAfterSec': 30,
      'expiresInSec': 600,
      'isExistingAccount': state.usersByPhone.containsKey(session.phone),
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

    // Trim 4 — the seed-peer DM is not created, because a DM never is:
    // its id is derived from the pair. The welcome message is the whole
    // introduction; the client materializes the channel from the first
    // frame that lands on a derived id. Sent once, on the first login
    // that finds no delivered welcome.
    String? defaultChannelId;
    if (demoMode) {
      defaultChannelId = mockDmChannelId(user.userId, seedPeerUserId);
      if (state.welcomedUsers.add(user.userId)) {
        state.markDirty();
        _enqueueWelcomeMessage(
          recipientUserId: user.userId,
          channelId: defaultChannelId,
          senderUserId: seedPeerUserId,
          body: '👋 Welcome to Vartalap! Reply with anything and I\'ll echo it back.',
        );
        _log('Seed-peer DM welcome queued on derived channel '
            '$defaultChannelId');
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

  // ---------------------------------------------------------------------------
  // E2EE key directory — AUTH_CONTRACT §17, the server's semantics in
  // short: a same-identity upload keeps its generation and adds only
  // prekey ids above the greatest seen; a new identity starts over.
  // ---------------------------------------------------------------------------

  Future<void> _handlePutKeys(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    final body = await _readJsonBody(req);
    _respondJson(
        req,
        200,
        publishKeys(state.deviceKeys, session.userId, session.deviceId, body,
            state.generateUuid));
  }

  /// A user who never signed in is one of the mock's simulated users:
  /// enrolled the first time someone looks them up.
  Future<void> _enrollIfSimulated(String userId) async {
    if (state.deviceKeys[userId]?.isNotEmpty ?? false) return;
    if (!state.usersById.containsKey(userId)) return;
    if (state.sessions.values.any((s) => s.userId == userId)) return;
    await peers.forUser(userId);
  }

  Future<void> _handleGetKeys(HttpRequest req, String userId) async {
    if (_authenticate(req) == null) return;
    if (!state.usersById.containsKey(userId)) {
      _respondJson(req, 404, {
        'error': {'code': 'KEYS_NOT_FOUND', 'message': 'The account is unavailable'}
      });
      return;
    }
    await _enrollIfSimulated(userId);
    _respondJson(req, 200, {
      'devices': [
        for (final MapEntry(:key, :value)
            in (state.deviceKeys[userId] ?? {}).entries)
          publicBundle(key, value)
      ]
    });
  }

  Future<void> _handleClaimKeys(HttpRequest req, String userId) async {
    if (_authenticate(req) == null) return;
    final body = await _readJsonBody(req);
    final claimed = claimKeys(state.deviceKeys, userId,
        body['deviceId'] as String, body['generation'] as String);
    if (claimed == null) {
      _respondJson(req, 404, {
        'error': {
          'code': 'KEYS_NOT_FOUND',
          'message': 'This device key generation is unavailable'
        }
      });
      return;
    }
    _respondJson(req, 200, claimed);
  }

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

  /// AUTH_CONTRACT §5.0 — same gating as §5.1.
  void _handlePushVapid(HttpRequest req) {
    final session = _authenticate(req);
    if (session == null) return;
    _record(req, const {}, 200);
    _respondJson(req, 200, {'vapidPublicKey': kMockVapidPublicKey});
  }

  /// AUTH_CONTRACT §5.1 — register, replace or (null/"") deregister the
  /// Web Push endpoint of the calling device. Validates the endpoint
  /// shape and the key sizes like notification-ms; the one rule it
  /// cannot mirror is "the host resolves only to public addresses",
  /// since the mock does no DNS.
  Future<void> _handlePushTopic(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    final body = await _readJsonBody(req);
    final endpoint = body['endpoint'] as String?;
    if (endpoint == null || endpoint.isEmpty) {
      _log('Push endpoint cleared for userId=${session.userId}');
      _record(req, body, 200);
      _respondJson(req, 200, {'status': true});
      return;
    }
    final parsed = Uri.tryParse(endpoint);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        endpoint.length > 2048) {
      _record(req, body, 400);
      _respondJson(req, 400, {
        'error': {
          'code': 'INVALID_PUSH_ENDPOINT',
          'message': 'endpoint must be an https URL without userinfo'
        }
      });
      return;
    }
    if (_base64UrlLength(body['p256dh']) != 65 ||
        _base64UrlLength(body['auth']) != 16) {
      _record(req, body, 400);
      _respondJson(req, 400, {
        'error': {
          'code': 'INVALID_PUSH_KEYS',
          'message': 'p256dh must be 65 bytes and auth 16 bytes, base64url'
        }
      });
      return;
    }
    _log('Push endpoint registered for userId=${session.userId}: $endpoint');
    _record(req, body, 200);
    _respondJson(req, 200, {'status': true});
  }

  /// Decoded length of a base64url (padded or not) string, or -1.
  static int _base64UrlLength(Object? value) {
    if (value is! String) return -1;
    try {
      return base64Url.decode(base64Url.normalize(value)).length;
    } on FormatException {
      return -1;
    }
  }

  // §10.6 client-triggered pull. Returns base64 of the raw WS_PUSH
  // WsEnvelope frames for this user stamped at or after `since`
  // (inclusive — several can share a millisecond; omitted = 0), but the
  // ones this device sent, ordered by (server_timestamp_ms, op_id), at
  // most 500, and `more` when there are frames past them. Read only;
  // the client keeps its own pointer. Client invokes this on startup /
  // WS connect / wake — server never pushes stored frames.
  Future<void> _handleSyncPending(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    final sinceArg = req.uri.queryParameters['since'];
    final since = sinceArg == null ? 0 : int.tryParse(sinceArg);
    if (since == null || since < 0) {
      _respondJson(req, 400, {
        'error': {
          'code': 'VALIDATION_FAILED',
          'message': 'since must be a non-negative integer'
        }
      });
      return;
    }
    final records = state.timeline(session, since);
    final frames = records.take(500).map((r) => base64Encode(r.frame)).toList();
    _log('Sync pull: device=${session.deviceKey} since=$since '
        'returned=${frames.length} of ${records.length} frame(s)');
    _respondJson(req, 200, {'frames': frames, 'more': records.length > 500});
  }

  // ---------------------------------------------------------------------------
  // Channel handler
  // ---------------------------------------------------------------------------

  Future<void> _handleCreateChannel(HttpRequest req) async {
    final session = _authenticate(req);
    if (session == null) return;
    final body = await _readJsonBody(req);
    final channelId = body['channel_id'] as String? ?? state.generateUuid();
    final kind = body['kind'] as String? ?? 'group';
    final name = body['name'] as String?;
    final membersList = (body['members'] as List<dynamic>?)?.cast<String>() ?? [];

    final pre = _validateRestOp(session: session, body: body);
    if (pre != null) {
      _respondOutcome(req, body, pre);
      return;
    }
    // Trim 4 — `POST /v3.0/channels` takes groups and nothing else. A
    // DM id is derived from the pair and has no server-side row, so
    // there is no `one_to_one` to create: a client that asks for one
    // is speaking the pre-trim protocol.
    if (strict && kind != 'group') {
      final outcome = StoredOutcome(
        success: false,
        status: 400,
        reason: 'validation_failed',
        body: {
          'error': {
            'code': 'validation_failed',
            'message': 'kind must be group, got "$kind"'
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

    // §11.2 — the body carries op_id / client_timestamp_ms.
    final body = await _readJsonBody(req);
    final pre = _validateRestOp(session: session, body: body);
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
    final pre = _validateRestOp(session: session, body: body);
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

    leaveChannel(target.channelId, target.userId, actorUserId: session.userId);

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
  void leaveChannel(String channelId, String userId, {String? actorUserId}) {
    final actor = actorUserId ?? userId;
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
        actorUserId: actor,
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

    state.addWsConnection(session, ws);
    _log('WS connected: userId=$userId (${state.wsConnections[userId]?.length ?? 0} sockets)');

    ws.listen(
      (dynamic data) {
        if (data is! List<int>) return;
        _handleWsFrame(session, Uint8List.fromList(data), ws);
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

  void _handleWsFrame(
      SessionRecord sender, Uint8List bytes, WebSocket senderSocket) {
    final senderUserId = sender.userId;
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
      _reply(
        senderSocket,
        pb.WsEnvelope(type: pb.WsType.WS_ACK, acks: pb.AckBatch(acks: rejects)),
      );
      return;
    }

    final acks = <pb.Ack>[];
    for (final env in wsEnv.ops.envelopes) {
      final ack = _processEnvelope(senderUserId, sender.deviceId, env, senderSocket);
      if (ack != null) acks.add(ack);
    }

    if (acks.isEmpty) return; // ephemeral-only batch — no ACK frame.

    // Send all ACKs back to sender.
    final ackFrame = pb.WsEnvelope(
      type: pb.WsType.WS_ACK,
      acks: pb.AckBatch(acks: acks),
    );
    _reply(senderSocket, ackFrame);
  }

  /// A reply to a frame [ws] sent (WS_ACK, WS_ERROR) goes back on that
  /// socket, like the real gateway's, and is never stored: only fanout
  /// is (§10.6).
  void _reply(WebSocket ws, pb.WsEnvelope frame) {
    try {
      ws.add(frame.writeToBuffer());
    } catch (e) {
      _log('WS reply error: $e');
    }
  }

  pb.Ack? _processEnvelope(
      String senderUserId, String senderDeviceId, pb.Envelope env, WebSocket senderSocket) {
    final channelId = env.channelId;
    final opId = env.opId;
    final now = _stamp();

    pb.Ack reject(String reason) {
      _log('WS reject: opId=$opId reason=$reason from $senderUserId');
      state.recordOutcome(
          senderUserId, opId, StoredOutcome(success: false, reason: reason));
      envelopes.add(RecordedEnvelope(
        opId: opId,
        channelId: channelId,
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
                serverTimestampMs:
                    fixnum.Int64(stored.serverTimestampMs ?? now),
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

    // Trim 4 — a `d`-prefixed channel has no row and no membership.
    // Membership IS the derivation: `peer` names the other side and the
    // server recomputes `dm_chan(sender, peer)` from the authenticated
    // session. A third party cannot produce a `peer` that derives to
    // someone else's DM id, so there is nothing to squat and nothing to
    // look up.
    //
    // Trim 12 — the recipient set is users; what is skipped is the
    // sending DEVICE, not the sending user, so a sender's own other
    // devices receive their own message. At `max_devices = 1` that is
    // unobservable; it is written this way so it stays right if the cap
    // is ever lifted.
    final Set<String> recipients;
    if (isMockDmChannelId(channelId)) {
      final peer = env.peer;
      if (peer.isEmpty || !_isWellFormedUserId(peer)) {
        return reject('validation_failed');
      }
      if (mockDmChannelId(senderUserId, peer) != channelId) {
        return reject('forbidden');
      }
      recipients = {peer, senderUserId};
    } else {
      final channel = state.channels[channelId];
      if (channel == null || !channel.members.contains(senderUserId)) {
        return reject('forbidden');
      }
      recipients = channel.members;
    }

    // §10.2 / decision 56 — server events are server-authored. A client
    // that prepends the 0x53 distinguisher is forging one; the real
    // gateway answers `validation_failed` and so do we. Checked ahead of
    // the ephemeral split so a forged typing frame is rejected too.
    if (strict && env.payload.isNotEmpty && env.payload[0] == 0x53) {
      return reject('validation_failed');
    }

    // Ephemeral envelopes bypass dedup, the fanout store, ACK
    // emission, and any of the post-fanout receipts. Fan to currently-
    // connected members live and drop the rest. See v3-envelope.proto.
    if (env.ephemeral) {
      ephemeralEnvelopes.add(RecordedEnvelope(
        opId: opId,
        channelId: channelId,
        payload: Uint8List.fromList(env.payload),
        rejectReason: null,
      ));
      _fanoutEphemeral(env, senderUserId, recipients, now,
          senderDeviceId: senderDeviceId,
          exceptSocket: senderSocket);
      for (final memberId in recipients) {
        _peerReceive(
            memberId,
            pb.Envelope(
              opId: opId,
              channelId: channelId,
              payload: env.payload,
              ephemeral: true,
              senderUserId: senderUserId,
              senderDeviceId: senderDeviceId,
              peer: env.peer,
              ttlSec: env.ttlSec,
              serverTimestampMs: fixnum.Int64(now),
            ));
      }
      if (demoMode &&
          senderUserId != seedPeerUserId &&
          recipients.contains(seedPeerUserId)) {
        _scheduleSeedPeerTypingEcho(channelId, env.payload);
      }
      // Return null-ish via a no-outcome Ack — the client ignores ACKs
      // with op_ids it doesn't track. (Safer than skipping the return:
      // the calling site builds an AckBatch from a List<Ack>.)
      return null;
    }

    // No ordering check (SYNC_PROTOCOL §6): the server keeps no
    // per-(user, channel) state, accepts ops in whatever order they
    // come, and recipients sort by (server_timestamp_ms, op_id).

    // §6a.3 step 5 — a client payload is a ChatPayload proto. Nothing
    // else is on the wire (§10.2 server events are server-authored).
    if (strict && !_payloadIsWellFormed(env.payload)) {
      return reject('validation_failed');
    }

    // Test hook. A read receipt is not chat content and never consumes
    // the budget.
    if (rejectNextChatOps > 0 && !_isReadReceipt(env.payload)) {
      rejectNextChatOps--;
      return reject('forced_reject');
    }

    // Accept the op
    state.recordOutcome(senderUserId, opId,
        StoredOutcome(success: true, serverTimestampMs: now));
    envelopes.add(RecordedEnvelope(
      opId: opId,
      channelId: channelId,
      payload: Uint8List.fromList(env.payload),
      rejectReason: null,
    ));
    _recordStamp(env.payload, now);

    _log('WS op: opId=$opId channel=$channelId sender=$senderUserId ts=$now');

    // Fanout WS_PUSH to other channel members
    final pushEnv = pb.Envelope(
      opId: opId,
      channelId: channelId,
      clientTimestampMs: env.clientTimestampMs,
      payload: env.payload,
      senderUserId: senderUserId,
      senderDeviceId: senderDeviceId,
      serverTimestampMs: fixnum.Int64(now),
      // Echoed unchanged; from the recipient's side the other
      // participant is `sender_user_id`, so nothing reads it.
      peer: env.peer.isEmpty ? null : env.peer,
      ttlSec: env.ttlSec,
    );

    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    final pushBytes = pushFrame.writeToBuffer();

    for (final memberId in recipients) {
      _sendToUser(memberId, pushBytes, exceptSocket: senderSocket);
      _peerReceive(memberId, pushEnv);
    }

    // Send a MessageStateChanged{DELIVERED} back to the author so the
    // local row flips from single tick to double. Only if there was at
    // least one other channel member (otherwise nothing was delivered).
    // `_isMessageCreate` is what keeps receipts/edits/reactions out:
    // re-announcing their lifecycle would loop a receipt back at the
    // reader and produce an "Echo: <binary>" garbage reply.
    if (recipients.difference({senderUserId}).isNotEmpty &&
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
        recipients.contains(seedPeerUserId)) {
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
    );
  }

  /// Who a frame from [senderUserId] on [channelId] goes to, sender
  /// excluded.
  ///
  /// For a group that is the stored roster. For a derived DM there is
  /// no roster to read, so the peer is recovered by testing the
  /// derivation against the users the mock holds — the same thing the
  /// draft says a real server can always do (§5.2 "the server can
  /// compute dm_chan for any pair of user_ids it holds"). The live
  /// wire path never needs this: an op carries its own `peer`.
  ///
  /// ponytail: an O(users) scan, which is nothing at mock scale.
  Set<String> _recipientsFor(String channelId, String senderUserId) {
    if (isMockDmChannelId(channelId)) {
      for (final userId in state.usersById.keys) {
        if (userId == senderUserId) continue;
        if (mockDmChannelId(senderUserId, userId) == channelId) return {userId};
      }
      throw StateError('no known peer derives $channelId with $senderUserId');
    }
    final channel = state.channels[channelId];
    if (channel == null) throw StateError('unknown channel $channelId');
    return channel.members.difference({senderUserId});
  }

  /// Deliver the WS_PUSH [bytes] to every device of [userId] except
  /// the one [exceptSocket] belongs to — trim 12's "every device of
  /// every member except the sending device".
  ///
  /// §10.6: the fanout is stored once, [userId] joining its recipients,
  /// and each pull is built from the stored records — so a push into a
  /// socket that died comes back on the next pull from the device's
  /// pointer. Then it goes live to every socket [userId] has open but
  /// the sending device's: neither its pull nor its socket hands an
  /// author its own message.
  void _sendToUser(String userId, Uint8List bytes, {WebSocket? exceptSocket}) {
    final except =
        exceptSocket == null ? null : state.socketDevice[exceptSocket];
    state.recordFanout(userId, bytes, senderDevice: except);
    for (final ws in state.wsConnections[userId] ?? const <WebSocket>[]) {
      if (except != null && state.socketDevice[ws] == except) continue;
      try {
        ws.add(bytes);
      } catch (e) {
        _log('WS send error to $userId: $e');
      }
    }
  }

  // Build a WS_PUSH WsEnvelope carrying a ChannelCreated ServerEventPayload
  // for [recipientUserId] and fan it to the user's devices.
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

    final now = _stamp();
    final pushEnv = pb.Envelope(
      opId: state.generateUuid(),
      channelId: channelId,
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: creatorUserId,
      serverTimestampMs: fixnum.Int64(now),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    _sendToUser(recipientUserId, pushFrame.writeToBuffer());
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
    String actorUserId = '',
  }) {
    final now = _stamp();
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
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: actorUserId, // the real server names the actor
      serverTimestampMs: fixnum.Int64(now),
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
    String actorUserId = '',
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
      clientTimestampMs: fixnum.Int64(removedAtMs),
      payload: payload,
      senderUserId: actorUserId, // the real server names the actor
      serverTimestampMs: fixnum.Int64(_stamp()),
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
    final now = _stamp();
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
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: '', // server-authored
      serverTimestampMs: fixnum.Int64(now),
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
    final now = _stamp();
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
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: '',
      serverTimestampMs: fixnum.Int64(now),
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
    String actorUserId = '',
  }) {
    final now = _stamp();
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
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: actorUserId, // the real server names the actor
      serverTimestampMs: fixnum.Int64(now),
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
    final now = _stamp();
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
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: '', // server-authored
      serverTimestampMs: fixnum.Int64(now),
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
    // Sealed like any peer message: it goes out once the new user's phone
    // has published its keys.
    _sendPeerMessage(channelId, senderUserId, body);
    _log('Enqueued welcome message for $recipientUserId channel=$channelId '
        'body="$body"');
  }

  // Build a WS_PUSH WsEnvelope carrying a MessageStateChanged
  // ServerEventPayload and fan it to the recipient — i.e. the original
  // message author. Used to flip the author's tick from sent →
  // delivered (and later read).
  void _enqueueMessageStateChanged({
    required String recipientUserId,
    required String channelId,
    required String messageId,
    required pb.MessageStateValue newState,
  }) {
    final now = _stamp();
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
      clientTimestampMs: fixnum.Int64(now),
      payload: payload,
      senderUserId: '', // server-authored
      serverTimestampMs: fixnum.Int64(now),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    _sendToUser(recipientUserId, pushFrame.writeToBuffer());
    _log('Sent MessageStateChanged{${newState.name}} '
        'to=$recipientUserId channel=$channelId message=$messageId');
  }

  // Fan an `ephemeral=true` envelope to currently-connected channel
  // members. Never stored, never produces an ACK, never
  // records op_id_seen — pure best-effort signal.
  void _fanoutEphemeral(
    pb.Envelope env,
    String senderUserId,
    Set<String> recipients,
    int now, {
    required String senderDeviceId,
    WebSocket? exceptSocket,
  }) {
    final pushEnv = pb.Envelope(
      opId: env.opId,
      channelId: env.channelId,
      clientTimestampMs: env.clientTimestampMs,
      payload: env.payload,
      ephemeral: true,
      senderUserId: senderUserId,
      senderDeviceId: senderDeviceId,
      peer: env.peer,
      ttlSec: env.ttlSec,
      serverTimestampMs: fixnum.Int64(now),
    );
    final pushFrame = pb.WsEnvelope(
      type: pb.WsType.WS_PUSH,
      push: pushEnv,
    );
    final pushBytes = pushFrame.writeToBuffer();
    for (final memberId in recipients) {
      final sockets = state.wsConnections[memberId]
          ?.where((ws) => !identical(ws, exceptSocket));
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
          String channelId, String senderUserId, String body,
          {String? messageId,
          int? serverTimestampMs,
          int ttlSec = 0,
          bool corrupt = false}) =>
      _fanoutPeerChatPayload(
        channelId,
        senderUserId,
        pb.ChatPayload(
          version: 1,
          type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
          messageId: messageId ?? state.generateUuid(),
          body: body,
          contentType: 'text/plain',
        ),
        serverTimestampMs: serverTimestampMs,
        ttlSec: ttlSec,
        corrupt: corrupt,
      );

  /// Fan an arbitrary peer-authored [payload] to every other member of
  /// [channelId] as a WS_PUSH — the same path a relayed client op takes,
  /// which is what makes edits / deletes / reactions injectable at all:
  /// the server never parses any of them (V3_ARCHITECTURE decision 12).
  ///
  /// [serverTimestampMs] overrides the server stamp, so a test can
  /// deliver ops in an order that disagrees with their timestamps (an
  /// edit stamped before its create, two messages on one millisecond).
  ({String messageId, String opId}) _fanoutPeerChatPayload(
      String channelId, String senderUserId, pb.ChatPayload payload,
      {int? serverTimestampMs,
      int ttlSec = 0,
      bool corrupt = false,
      String? opId,
      String retryOf = ''}) {
    final recipients = _recipientsFor(channelId, senderUserId);
    final messageId = payload.messageId;
    final plain = payload.writeToBuffer();
    opId ??= state.generateUuid();
    // Sealed like a phone's send (decision 188), in order, on a chain:
    // [settled] waits for it.
    _peerSends = _peerSends.then((_) async {
      final peer = isMockDmChannelId(channelId) ? recipients.single : null;
      final bytes = peer == null
          ? await _sealGroupFromPeer(
              senderUserId, opId!, channelId, recipients, plain,
              ttlSec: ttlSec)
          : await _sealFromPeer(senderUserId, opId!, channelId, peer, plain,
              ttlSec: ttlSec, retryOf: retryOf);
      if (bytes == null) return;
      if (corrupt) bytes.last ^= 1;
      // Stamped after any group key hand-out it needed, as a real server
      // would: a pull meets the key first.
      final now = serverTimestampMs ?? _stamp();
      _recordStamp(plain, now);
      final pushEnv = pb.Envelope(
        opId: opId,
        channelId: channelId,
        clientTimestampMs: fixnum.Int64(now),
        payload: bytes,
        senderUserId: senderUserId,
        senderDeviceId: MockPeers.deviceId,
        peer: peer,
        serverTimestampMs: fixnum.Int64(now),
        ttlSec: ttlSec == 0 ? null : ttlSec,
      );
      final pushBytes =
          pb.WsEnvelope(type: pb.WsType.WS_PUSH, push: pushEnv).writeToBuffer();
      for (final memberId in recipients) {
        _sendToUser(memberId, pushBytes);
        _peerReceive(memberId, pushEnv);
      }
    }).catchError((Object e) => _log('Peer send failed: $e'));
    _log('Peer ${payload.type.name}: channel=$channelId '
        'from=$senderUserId message=$messageId');
    return (messageId: messageId, opId: opId);
  }

  /// [sender] seals [plain] for the DM [peer]. A real client publishes its
  /// keys only once its username lands, so wait for them the way a
  /// phone's outbound queue retries; null if they never come.
  Future<Uint8List?> _sealFromPeer(String sender, String opId,
      String channelId, String peer, Uint8List plain,
      {int ttlSec = 0, bool ephemeral = false, String retryOf = ''}) async {
    final crypto = await peers.forUser(sender);
    for (var attempt = 0; attempt < 200; attempt++) {
      try {
        return await crypto.sealDm(
            opId: opId,
            channelId: channelId,
            peer: peer,
            payload: plain,
            ttlSec: ttlSec,
            ephemeral: ephemeral,
            retryOf: retryOf,
            // Logged like a phone's send, so a re-send request can be met.
            persist: ephemeral || retryOf.isNotEmpty
                ? null
                : (txn, _) => crypto.rememberSent(txn, opId,
                    {'ch': channelId, 'payload': base64.encode(plain)}));
      } on E2eeNoKeys {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    _log('Peer send dropped: $peer never published keys');
    return null;
  }

  /// A simulated user's phone meeting a re-send request, as the app does:
  /// once, from its sent log, sealed afresh under a new op id that names
  /// the one the requester could not open.
  Future<void> _answerResend(
      String userId, E2eeCrypto crypto, pb.Envelope env) async {
    final ask = jsonDecode(utf8.decode(env.payload.sublist(3))) as Map;
    final sent = await crypto.takeForResend('${ask['op']}');
    if (sent == null || sent['ch'] != ask['ch']) return;
    await crypto.resetSession(env.senderUserId, env.senderDeviceId);
    _fanoutPeerChatPayload(
      '${ask['ch']}',
      userId,
      pb.ChatPayload.fromBuffer(base64.decode(sent['payload'] as String)),
      retryOf: '${ask['op']}',
    );
  }

  /// [sender]'s Sender Key ciphertext for the group, its key handed to each
  /// member first over their 1:1 channel, as a phone does.
  Future<Uint8List?> _sealGroupFromPeer(String sender, String opId,
      String channelId, Set<String> members, Uint8List plain,
      {int ttlSec = 0, bool ephemeral = false}) async {
    for (final member in members) {
      await _enrollIfSimulated(member);
    }
    final crypto = await peers.forUser(sender);
    return crypto.sealGroup(
      opId: opId,
      channelId: channelId,
      members: members,
      payload: plain,
      ttlSec: ttlSec,
      ephemeral: ephemeral,
      dmChannel: (member) => mockDmChannelId(sender, member),
      newOpId: state.generateUuid,
      sendKey: (member, keyChannel, keyOpId, sealed) async {
        final now = _stamp();
        final env = pb.Envelope(
          opId: keyOpId,
          channelId: keyChannel,
          clientTimestampMs: fixnum.Int64(now),
          payload: sealed,
          senderUserId: sender,
          senderDeviceId: MockPeers.deviceId,
          peer: member,
          serverTimestampMs: fixnum.Int64(now),
        );
        _sendToUser(member,
            pb.WsEnvelope(type: pb.WsType.WS_PUSH, push: env).writeToBuffer());
        _peerReceive(member, env);
      },
    );
  }

  /// A simulated user's phone receiving [env]: a DM opens with its crypto,
  /// a group payload is read as it came. Lands in [peerOpened]; for a
  /// sealed message the conveniences the mock used to read off the wire
  /// (stamps, the author's double tick, the demo echo) run from here.
  void _peerReceive(String userId, pb.Envelope env) {
    if (!peers.isPeer(userId) || userId == env.senderUserId) return;
    _peerReceives = _peerReceives.then((_) async {
      final sealed = env.payload.isNotEmpty && env.payload[0] == kSealedMarker;
      final crypto = await peers.forUser(userId);
      if (sealed && env.payload.length > 3 && env.payload[2] == 5) {
        peerResendRequests.add((userId: userId, env: env));
        if (holdResends) {
          _heldResends.add((userId, crypto, env));
        } else {
          await _answerResend(userId, crypto, env);
        }
        return;
      }
      final plain = sealed
          ? (await crypto.open(env)).payload
          : Uint8List.fromList(env.payload);
      if (sealed && !env.ephemeral) await crypto.applied(env);
      if (plain.isEmpty) return; // a group key, taken
      peerOpened.add((userId: userId, env: env, payload: plain));
      if (!sealed || env.ephemeral || !_isMessageCreate(plain)) return;
      final now = env.serverTimestampMs.toInt();
      _recordStamp(plain, now);
      final messageId = _extractMessageId(plain);
      if (messageId != null && !peers.isPeer(env.senderUserId)) {
        _enqueueMessageStateChanged(
          recipientUserId: env.senderUserId,
          channelId: env.channelId,
          messageId: messageId,
          newState: pb.MessageStateValue.MESSAGE_STATE_DELIVERED,
        );
      }
      if (demoMode && userId == seedPeerUserId) {
        _scheduleSeedPeerReply(env.channelId, env.senderUserId, plain);
      }
    }).catchError((Object e) => _log('Peer $userId could not open: $e'));
  }

  // ---------------------------------------------------------------------------
  // HTTP helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest req) async {
    final raw = await utf8.decodeStream(req);
    if (raw.isEmpty) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  void _respondJson(HttpRequest req, int status, Map<String, dynamic> body) =>
      _respondJsonValue(req, status, body);

  void _respondJsonValue(HttpRequest req, int status, Object body) {
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
    // Decision 190, as media-ms: a stored copy of these exact bytes is
    // reused, with no url and no record.
    final hash = q['md5'];
    if (hash != null) {
      for (final MapEntry(:key, :value) in assets.entries) {
        if (value.md5 == hash && value.category == category && value.complete) {
          _record(req, const {}, 200);
          _respondJson(req, 200, {'fileId': key, 'existing': true});
          return;
        }
      }
    }
    final fileId = state.generateUuid();
    assets[fileId] = _AssetRecord(
      owner: session.userId,
      category: category,
      contentType: _contentTypeForExt(ext),
      declaredSize: size,
      md5: hash,
    );
    _record(req, const {}, 200);
    _respondJson(req, 200, {
      'url': '${apiUrl.toString()}/v3.0/_blob/$fileId',
      'fileId': fileId,
      'contentType': assets[fileId]!.contentType,
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
      // Like S3: the content-type is part of the signature.
      final sent = req.headers.contentType?.mimeType;
      if (sent != record.contentType) {
        _respondJson(req, 403, {
          'error': {
            'code': 'SignatureDoesNotMatch',
            'message': 'content-type $sent, signed ${record.contentType}'
          }
        });
        return;
      }
      final builder = BytesBuilder();
      await for (final chunk in req) {
        builder.add(chunk);
      }
      final body = builder.takeBytes();
      // Like S3: a signed Content-MD5 must be sent, and must be the body's.
      final signedMd5 = record.md5;
      if (signedMd5 != null) {
        final sent = req.headers.value('content-md5');
        if (sent == null) {
          _respondJson(req, 403, {
            'error': {
              'code': 'SignatureDoesNotMatch',
              'message': 'content-md5 is signed but missing'
            }
          });
          return;
        }
        if (sent != base64.encode(md5.convert(body).bytes) ||
            md5.convert(body).toString() != signedMd5) {
          _respondJson(req, 400, {
            'error': {'code': 'BadDigest', 'message': 'Content-MD5 mismatch'}
          });
          return;
        }
      }
      record.bytes = body;
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
    if (body['status'] == true && record.md5 != null && record.bytes == null) {
      _record(req, body, 409);
      _respondJson(req, 409, {
        'error': {
          'code': 'NOT_UPLOADED',
          'message': 'nothing was stored for this file'
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
    final pre = _validateRestOp(session: session, body: body);
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
    final pre = _validateRestOp(session: session, body: body);
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

    // Joi on the real route: these keys and no others, one edit at least.
    const allowed = {'op_id', 'client_timestamp_ms', 'name', 'avatar_url'};
    final unknown = body.keys.where((k) => !allowed.contains(k)).toList();
    final namePresent = body.containsKey('name');
    final avatarPresent = body.containsKey('avatar_url');
    if (unknown.isNotEmpty || !(namePresent || avatarPresent)) {
      _record(req, body, 400);
      _respondJson(req, 400, {
        'error': {
          'code': 'validation_failed',
          'message': unknown.isEmpty
              ? 'name or avatar_url required'
              : '"${unknown.first}" is not allowed',
        }
      });
      return;
    }
    if (namePresent) channel.name = body['name'] as String?;
    if (avatarPresent) channel.avatarUrl = body['avatar_url'] as String?;
    state.markDirty();

    final result = {
      'channel_id': channelId,
      'name': channel.name,
      'avatar_url': channel.avatarUrl,
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
        actorUserId: session.userId,
      );
    }
  }

  /// `channelView` on the real server: the group as GET returns it.
  Map<String, dynamic> _channelView(ChannelRecord c) => {
        'channel_id': c.channelId,
        'kind': c.kind,
        'name': c.name,
        'avatar_url': c.avatarUrl,
        'members': c.members.toList(),
        'roles': {for (final m in c.members) m: c.roleOf(m)},
        'created_at': c.createdAt,
      };

  /// `GET /v3.0/channels[/{id}]` — the caller's groups, or one of them
  /// (404 when it isn't one of theirs).
  Future<void> _handleGetChannels(HttpRequest req, String path) async {
    final session = _authenticate(req);
    if (session == null) return;
    _record(req, const {}, 200);
    if (path == '/v3.0/channels') {
      _respondJsonValue(req, 200, [
        for (final c in state.channels.values)
          if (c.kind == 'group' && c.members.contains(session.userId))
            _channelView(c),
      ]);
      return;
    }
    final channel = state.channels[path.substring('/v3.0/channels/'.length)];
    if (channel == null || !channel.members.contains(session.userId)) {
      _respondJson(req, 404, {
        'error': {'code': 'not_found', 'message': 'unknown channel'}
      });
      return;
    }
    _respondJson(req, 200, _channelView(channel));
  }

  /// `POST /v3.0/channels/{id}/members` — owner and admins add people;
  /// everyone in the group afterwards, the actor's device aside, hears
  /// `ChannelMemberAdded`.
  Future<void> _handleAddChannelMembers(HttpRequest req, String channelId) async {
    final session = _authenticate(req);
    if (session == null) return;
    final body = await _readJsonBody(req);
    final pre = _validateRestOp(session: session, body: body);
    if (pre != null) {
      _respondOutcome(req, body, pre);
      return;
    }
    final channel = state.channels[channelId];
    if (channel == null) {
      _record(req, body, 404);
      _respondJson(req, 404, {
        'error': {'code': 'not_found', 'message': 'unknown channel'}
      });
      return;
    }
    if (!channel.members.contains(session.userId) ||
        channel.roleOf(session.userId) == 'member') {
      _record(req, body, 403);
      _respondJson(req, 403, {
        'error': {'code': 'forbidden', 'message': 'owner or admin only'}
      });
      return;
    }
    final added = [
      for (final id in (body['members'] as List? ?? const []).cast<String>())
        if (!channel.members.contains(id)) id,
    ];
    channel.members.addAll(added);
    state.markDirty();
    final result = {'member_count': channel.members.length};
    final opId = body['op_id'];
    if (opId is String) {
      state.recordOutcome(session.userId, opId,
          StoredOutcome(success: true, status: 200, body: result));
    }
    _record(req, body, 200);
    _respondJson(req, 200, result);
    if (added.isEmpty) return;
    for (final memberId in channel.members) {
      if (memberId == session.userId) continue;
      _enqueueChannelMemberAdded(
        recipientUserId: memberId,
        channelId: channelId,
        newMemberUserIds: added,
        role: 'member',
        actorUserId: session.userId,
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
  final String? md5;
  Uint8List? bytes;
  bool complete = false;

  _AssetRecord({
    required this.owner,
    required this.category,
    required this.contentType,
    required this.declaredSize,
    this.md5,
  });
}
