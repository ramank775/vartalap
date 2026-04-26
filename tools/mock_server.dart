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

  const OtpSession({
    required this.sessionId,
    required this.phone,
    required this.deviceId,
    required this.createdAt,
  });
}

class ChannelRecord {
  final String channelId;
  final String kind;
  final String? name;
  final String ownerUserId;
  final Set<String> members;
  final int createdAt;

  ChannelRecord({
    required this.channelId,
    required this.kind,
    this.name,
    required this.ownerUserId,
    required this.members,
    required this.createdAt,
  });

  Map<String, dynamic> toPersistJson() => {
        'channelId': channelId,
        'kind': kind,
        'name': name,
        'ownerUserId': ownerUserId,
        'members': members.toList(),
        'createdAt': createdAt,
      };

  static ChannelRecord fromPersistJson(Map<String, dynamic> j) => ChannelRecord(
        channelId: j['channelId'] as String,
        kind: j['kind'] as String,
        name: j['name'] as String?,
        ownerUserId: j['ownerUserId'] as String,
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
  final Map<String, Set<String>> opIdSeen = {};
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
        'opIdSeen': opIdSeen.map(
          (k, v) => MapEntry(k, v.toList()),
        ),
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
      final seen = j['opIdSeen'] as Map<String, dynamic>? ?? {};
      seen.forEach((k, v) =>
          opIdSeen[k] = (v as List<dynamic>).cast<String>().toSet());
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

  bool hasSeenOp(String userId, String channelId, String opId) {
    final key = '$userId:$channelId';
    return opIdSeen.putIfAbsent(key, () => {}).contains(opId);
  }

  void markOpSeen(String userId, String channelId, String opId) {
    opIdSeen.putIfAbsent('$userId:$channelId', () => {}).add(opId);
    markDirty();
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
    markDirty();
    return user;
  }
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

late MockState state;
late bool seedPeerEnabled;
const String seedPeerUserId = '000000001';

void main(List<String> args) async {
  final port = _parseArg(args, '--port', '9777');
  seedPeerEnabled = args.contains('--seed-peer');
  // Default state file lives next to the script. `--state-file=-`
  // disables persistence (back to pure in-memory).
  final scriptDir = File.fromUri(Platform.script).parent.path;
  final stateArg = _parseArg(args, '--state-file', '$scriptDir/.mock_state.json');
  final statePath = stateArg == '-' ? null : stateArg;

  state = MockState();
  if (statePath != null) {
    state.loadFromFile(statePath);
    state.persistencePath = statePath;
    _log('Persistence: $statePath '
        '(${state.usersById.length} user(s), '
        '${state.sessions.length} session(s), '
        '${state.channels.length} channel(s))');
  } else {
    _log('Persistence: disabled (--state-file=-)');
  }
  if (seedPeerEnabled && !state.usersById.containsKey(seedPeerUserId)) {
    state.createSeedPeer();
    _log('Seed peer created: userId=$seedPeerUserId');
  }
  // Flush IO on Ctrl-C so the in-flight debounce timer doesn't drop
  // the last mutation.
  ProcessSignal.sigint.watch().listen((_) {
    if (statePath != null) state._saveSync(statePath);
    exit(0);
  });

  final server = await HttpServer.bind(InternetAddress.anyIPv4, int.parse(port));
  _log('Mock server listening on http://localhost:$port');
  _log('  WS endpoint: ws://localhost:$port/wss');
  _log('  Emulator:    http://10.0.2.2:$port');
  _log('  Seed peer:   ${seedPeerEnabled ? "enabled" : "disabled"}');
  _log('---');

  await for (final req in server) {
    try {
      await _handleRequest(req);
    } catch (e, st) {
      _log('ERROR handling ${req.method} ${req.uri}: $e\n$st');
      try {
        req.response.statusCode = 500;
        _respondJson(req, 500, {'error': {'code': 'INTERNAL_ERROR', 'message': '$e'}});
      } catch (_) {}
    }
  }
}

String _parseArg(List<String> args, String flag, String defaultValue) {
  final idx = args.indexOf(flag);
  if (idx >= 0 && idx + 1 < args.length) return args[idx + 1];
  return defaultValue;
}

void _log(String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  print('[$ts] $msg');
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
  } else if (method == 'GET' && path.startsWith('/v3.0/users/')) {
    await _handleGetUser(req);
  } else if (method == 'POST' && path == '/v3.0/contacts/lookup') {
    await _handleContactLookup(req);
  } else if (method == 'POST' && path == '/v3.0/push/topic') {
    await _handlePushTopic(req);
  } else if (method == 'POST' && path == '/v3.0/channels') {
    await _handleCreateChannel(req);
  } else if (method == 'GET' && path == '/v3.0/sync/pending') {
    await _handleSyncPending(req);
  } else if (method == 'POST' && path == '/v3.0/_dev/seed-users') {
    await _handleDevSeedUsers(req);
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

  final otpSession = state.otpSessions.remove(sessionId);
  if (otpSession == null) {
    _respondJson(req, 404, {
      'error': {'code': 'SESSION_NOT_FOUND', 'message': 'Unknown sessionId'}
    });
    return;
  }

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
  if (seedPeerEnabled) {
    defaultChannelId = 'dm-${user.userId}-$seedPeerUserId';
    if (!state.channels.containsKey(defaultChannelId)) {
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      state.channels[defaultChannelId] = ChannelRecord(
        channelId: defaultChannelId,
        kind: 'dm',
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
  final session = _authenticate(req);
  if (session == null) return;
  state.revokeSession(session);
  _log('Session revoked: userId=${session.userId}');
  _respondJson(req, 200, {'status': true});
}

// ---------------------------------------------------------------------------
// Profile / contacts handlers
// ---------------------------------------------------------------------------

Future<void> _handleGetProfile(HttpRequest req) async {
  final session = _authenticate(req);
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
  final session = _authenticate(req);
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
    user.username = body['username'] as String?;
    newUsername = user.username;
    usernameTouched = true;
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

Future<void> _handlePushTopic(HttpRequest req) async {
  final session = _authenticate(req);
  if (session == null) return;
  _log('Push topic registered for userId=${session.userId}');
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
  final kind = body['kind'] as String? ?? 'dm';
  final name = body['name'] as String?;
  final membersList = (body['members'] as List<dynamic>?)?.cast<String>() ?? [];

  // Members the client explicitly asked for (creator + picked peers).
  final clientRequested = <String>{session.userId, ...membersList};
  // Final server-side roster — same as requested, plus the seed peer
  // when --seed-peer is on so groups demo Echo replies.
  final members = <String>{...clientRequested};
  if (seedPeerEnabled) members.add(seedPeerUserId);

  state.channels[channelId] = ChannelRecord(
    channelId: channelId,
    kind: kind,
    name: name,
    ownerUserId: session.userId,
    members: members,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
  state.markDirty();

  _log('Channel created: $channelId kind=$kind members=$members');

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

  _respondJson(req, 201, {
    'channel_id': channelId,
    'kind': kind,
    'name': name,
    'members': members.toList(),
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });
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

  // Dedup check
  if (state.hasSeenOp(senderUserId, channelId, opId)) {
    _log('WS dedup: opId=$opId from $senderUserId');
    return pb.Ack(
      opId: opId,
      outcome: pb.AckOutcome.ACK_SUCCESS,
      serverTimestampMs: fixnum.Int64(now),
    );
  }

  // Channel membership check
  final channel = state.channels[channelId];
  if (channel == null || !channel.members.contains(senderUserId)) {
    _log('WS forbidden: $senderUserId not member of $channelId');
    return pb.Ack(
      opId: opId,
      outcome: pb.AckOutcome.ACK_PERMANENT,
      reason: 'forbidden',
    );
  }

  // Ephemeral envelopes bypass dedup, deliverySeq, undelivered queue,
  // ACK emission, and any of the post-fanout receipts. Fan to currently-
  // connected members live and drop the rest. See v3-envelope.proto.
  if (env.ephemeral) {
    _fanoutEphemeral(env, senderUserId, channel, now);
    if (seedPeerEnabled &&
        senderUserId != seedPeerUserId &&
        channel.members.contains(seedPeerUserId)) {
      _scheduleSeedPeerTypingEcho(channelId, env.payload);
    }
    // Return null-ish via a no-outcome Ack — the client ignores ACKs
    // with op_ids it doesn't track. (Safer than skipping the return:
    // the calling site builds an AckBatch from a List<Ack>.)
    return null;
  }

  // Accept the op
  state.markOpSeen(senderUserId, channelId, opId);
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

  // Skip delivered-receipt + seed-peer echo for server-event payloads
  // (e.g. client-originated MessageStateChanged{READ}). Those are
  // already a state-change envelope being relayed; treating them as
  // chat content would loop a delivered receipt back to the reader and
  // produce an "Echo: <binary>" garbage reply.
  final isServerEventPayload =
      env.payload.isNotEmpty && env.payload[0] == 0x53;

  // Send a MessageStateChanged{DELIVERED} back to the author so the
  // local row flips from single tick to double. Only if there was at
  // least one other channel member (otherwise nothing was delivered).
  if (!isServerEventPayload && channel.members.length > 1) {
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
  if (!isServerEventPayload &&
      seedPeerEnabled &&
      senderUserId != seedPeerUserId &&
      channel.members.contains(seedPeerUserId)) {
    _scheduleSeedPeerReply(channelId, senderUserId, env.payload);
    final readId = _extractMessageId(env.payload);
    if (readId != null) {
      Timer(const Duration(milliseconds: 1500), () {
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
void _enqueueChannelMemberAdded({
  required String recipientUserId,
  required String channelId,
  required List<String> newMemberUserIds,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final sep = pb.ServerEventPayload(
    version: 1,
    type: pb.ServerEventType.CHANNEL_MEMBER_ADDED,
    memberAdded: pb.ChannelMemberAdded(
      channelId: channelId,
      members: newMemberUserIds,
      addedAtMs: fixnum.Int64(now),
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
  if (payload.length < 2 || payload[0] != 0x53) return;
  pb.ServerEventPayload sep;
  try {
    sep = pb.ServerEventPayload.fromBuffer(payload.sublist(1));
  } catch (_) {
    return;
  }
  if (sep.whichBody() != pb.ServerEventPayload_Body.typing) return;
  if (!sep.typing.isTyping) return;

  void send(bool isTyping) {
    final reply = pb.ServerEventPayload(
      version: 1,
      type: pb.ServerEventType.TYPING,
      typing: pb.Typing(isTyping: isTyping),
    );
    final replyBytes = Uint8List.fromList([0x53, ...reply.writeToBuffer()]);
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
  Timer(const Duration(milliseconds: 3000), () => send(true));
  Timer(const Duration(milliseconds: 6000), () => send(false));
}

// Pull `message_id` out of an inbound ChatPayload (best-effort). The
// production client encodes via protobuf; the v3 spike client (current
// `ChatService._encodeChatPayload`) ships a JSON placeholder with
// `message_id` / `type` / `body` keys. Try proto first, fall back to
// JSON. Returns null if neither works — a prepended 0x53 means it's a
// server event, not a chat op, so skip.
String? _extractMessageId(List<int> payload) {
  if (payload.isEmpty) return null;
  if (payload[0] == 0x53) return null;
  try {
    final chat = pb.ChatPayload.fromBuffer(payload);
    if (chat.messageId.isNotEmpty) return chat.messageId;
  } catch (_) {
    // Fall through to JSON.
  }
  try {
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is Map<String, dynamic>) {
      final id = decoded['message_id'];
      if (id is String && id.isNotEmpty) return id;
    }
  } catch (_) {
    // Not JSON either.
  }
  return null;
}

// ---------------------------------------------------------------------------
// Seed peer auto-reply
// ---------------------------------------------------------------------------

void _scheduleSeedPeerReply(
    String channelId, String realUserId, List<int> incomingPayload) {
  Timer(const Duration(seconds: 1), () {
    _sendSeedPeerReply(channelId, realUserId, incomingPayload);
  });
}

void _sendSeedPeerReply(
    String channelId, String realUserId, List<int> incomingPayload) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final deliverySeq = state.nextDeliverySeq(channelId);
  final opId = state.generateUuid();

  // Build a simple ChatPayload for the reply. This is the one place
  // the mock server touches the payload schema.
  final messageId = state.generateUuid();

  // Try to extract original body for echo
  String replyBody = 'Hello from Seed Peer!';
  try {
    final incoming = pb.ChatPayload.fromBuffer(incomingPayload);
    if (incoming.body.isNotEmpty) {
      replyBody = 'Echo: ${incoming.body}';
    }
  } catch (_) {
    // Payload isn't a ChatPayload (could be JSON placeholder) — try JSON.
    try {
      final json = jsonDecode(utf8.decode(incomingPayload)) as Map<String, dynamic>;
      final body = json['body'] as String?;
      if (body != null && body.isNotEmpty) {
        replyBody = 'Echo: $body';
      }
    } catch (_) {
      // Can't decode — use default reply.
    }
  }

  final replyPayload = pb.ChatPayload(
    version: 1,
    type: pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
    messageId: messageId,
    body: replyBody,
    contentType: 'text/plain',
  );

  final pushEnv = pb.Envelope(
    opId: opId,
    channelId: channelId,
    resourceSeq: fixnum.Int64(1),
    clientTimestampMs: fixnum.Int64(now),
    payload: replyPayload.writeToBuffer(),
    senderUserId: seedPeerUserId,
    serverTimestampMs: fixnum.Int64(now),
    deliverySequence: fixnum.Int64(deliverySeq),
  );

  final pushFrame = pb.WsEnvelope(
    type: pb.WsType.WS_PUSH,
    push: pushEnv,
  );
  final pushBytes = pushFrame.writeToBuffer();

  // Send to the real user only (seed peer has no WS connection).
  final channel = state.channels[channelId];
  if (channel == null) return;
  for (final memberId in channel.members) {
    if (memberId == seedPeerUserId) continue;
    _sendToUser(memberId, pushBytes);
  }

  _log('Seed peer reply: channel=$channelId deliverySeq=$deliverySeq body="$replyBody"');
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
SessionRecord? _authenticate(HttpRequest req) {
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
  return session;
}
