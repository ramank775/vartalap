/// Vartalap v3 mock server for golden-path testing.
///
/// Serves REST (auth, channels) and WebSocket (chat ops) on a single
/// port. All state is in-memory. OTP auto-accepts any 6-digit code.
///
/// Usage:
///   dart run tools/mock_server.dart [--port 9777] [--seed-peer]
///
/// Then run the app:
///   flutter run --dart-define=API_URL=http://10.0.2.2:9777 \
///               --dart-define=WS_URL=ws://10.0.2.2:9777/wss
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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

  final Random _rng = Random.secure();

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
    return session;
  }

  SessionRecord? lookupByAccesskey(String accesskey) => sessions[accesskey];

  void revokeSession(SessionRecord session) {
    sessions.remove(session.accesskey);
    sessionsByRefresh.remove(session.refreshToken);
  }

  int nextDeliverySeq(String channelId) {
    final seq = (channelDeliverySeq[channelId] ?? 0) + 1;
    channelDeliverySeq[channelId] = seq;
    return seq;
  }

  bool hasSeenOp(String userId, String channelId, String opId) {
    final key = '$userId:$channelId';
    return opIdSeen.putIfAbsent(key, () => {}).contains(opId);
  }

  void markOpSeen(String userId, String channelId, String opId) {
    opIdSeen.putIfAbsent('$userId:$channelId', () => {}).add(opId);
  }

  void addWsConnection(String userId, WebSocket ws) {
    wsConnections.putIfAbsent(userId, () => []).add(ws);
  }

  void removeWsConnection(String userId, WebSocket ws) {
    wsConnections[userId]?.remove(ws);
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

  state = MockState();
  if (seedPeerEnabled) {
    state.createSeedPeer();
    _log('Seed peer created: userId=$seedPeerUserId');
  }

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

  // If seed-peer is enabled and this is a new user, create a default DM channel.
  String? defaultChannelId;
  if (seedPeerEnabled && isNew) {
    defaultChannelId = 'dm-${user.userId}-$seedPeerUserId';
    if (!state.channels.containsKey(defaultChannelId)) {
      state.channels[defaultChannelId] = ChannelRecord(
        channelId: defaultChannelId,
        kind: 'dm',
        name: 'Seed Peer',
        ownerUserId: user.userId,
        members: {user.userId, seedPeerUserId},
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      _log('Created seed-peer DM channel: $defaultChannelId');
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
  if (body.containsKey('username')) user.username = body['username'] as String?;
  if (body.containsKey('displayName')) user.displayName = body['displayName'] as String?;
  if (body.containsKey('avatarUrl')) user.avatarUrl = body['avatarUrl'] as String?;
  if (body.containsKey('statusText')) user.statusText = body['statusText'] as String?;
  _respondJson(req, 200, user.toProfileJson());
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
  final matches = state.usersById.values
      .where((u) => u.userId != session.userId) // exclude self
      .map((u) => {
            'phoneHash': 'hash_${u.phone}',
            'user_id': u.userId,
            'username': u.username,
          })
      .toList();
  _respondJson(req, 200, {'matches': matches});
}

Future<void> _handlePushTopic(HttpRequest req) async {
  final session = _authenticate(req);
  if (session == null) return;
  _log('Push topic registered for userId=${session.userId}');
  _respondJson(req, 200, {'status': true});
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

  final members = <String>{session.userId, ...membersList};
  if (seedPeerEnabled) members.add(seedPeerUserId);

  state.channels[channelId] = ChannelRecord(
    channelId: channelId,
    kind: kind,
    name: name,
    ownerUserId: session.userId,
    members: members,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );

  _log('Channel created: $channelId kind=$kind members=$members');

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
    acks.add(ack);
  }

  // Send all ACKs back to sender.
  final ackFrame = pb.WsEnvelope(
    type: pb.WsType.WS_ACK,
    acks: pb.AckBatch(acks: acks),
  );
  _sendToUser(senderUserId, ackFrame.writeToBuffer());
}

pb.Ack _processEnvelope(String senderUserId, pb.Envelope env) {
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

  // Seed peer auto-reply
  if (seedPeerEnabled &&
      senderUserId != seedPeerUserId &&
      channel.members.contains(seedPeerUserId)) {
    _scheduleSeedPeerReply(channelId, senderUserId, env.payload);
  }

  return pb.Ack(
    opId: opId,
    outcome: pb.AckOutcome.ACK_SUCCESS,
    serverTimestampMs: fixnum.Int64(now),
    deliverySequence: fixnum.Int64(deliverySeq),
  );
}

void _sendToUser(String userId, Uint8List bytes) {
  final sockets = state.wsConnections[userId];
  if (sockets == null || sockets.isEmpty) return;
  for (final ws in sockets) {
    try {
      ws.add(bytes);
    } catch (e) {
      _log('WS send error to $userId: $e');
    }
  }
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
