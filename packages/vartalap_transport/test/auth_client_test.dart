import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  late _TestServer server;
  late AuthClient client;

  setUp(() async {
    server = _TestServer();
    await server.start();
    client = AuthClient(baseUrl: server.uri);
    client.setDeviceId('device-001');
  });

  tearDown(() async {
    client.dispose();
    await server.stop();
  });

  group('sendOtp', () {
    test('200 returns OtpSendResult with sessionId', () async {
      server.handler = (req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/v3.0/auth/otp/send');
        final body =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        expect(body['phone'], '+919876543210');
        expect(body['deviceId'], 'device-001');
        _respond(req, 200, {
          'sessionId': 'sess-123',
          'resendAfterSec': 30,
          'expiresInSec': 600,
          'isExistingAccount': true,
        });
      };

      final result = await client.sendOtp(phone: '+919876543210');
      expect(result.sessionId, 'sess-123');
      expect(result.retryAfter, const Duration(seconds: 30));
      expect(result.expiresIn, const Duration(seconds: 600));
      expect(result.isExistingAccount, true);
    });

    test('429 throws AuthClientException with rate-limit info', () async {
      server.handler = (req) async {
        _respond(req, 429, {
          'error': {
            'code': 'OTP_RATE_LIMITED',
            'message': 'Too many requests',
            'retryAfterSec': 1800,
          }
        });
      };

      try {
        await client.sendOtp(phone: '+919876543210');
        fail('should throw');
      } on AuthClientException catch (e) {
        expect(e.statusCode, 429);
        expect(e.errorCode, 'OTP_RATE_LIMITED');
        expect(e.isRateLimited, true);
      }
    });
  });

  group('verifyOtp', () {
    test('200 stores tokens in memory and returns OtpVerifyResult', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      server.handler = (req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/v3.0/auth/otp/verify');
        final body =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        expect(body['sessionId'], 'sess-123');
        expect(body['code'], '654321');
        expect(body['deviceId'], 'device-001');
        _respond(req, 200, {
          'status': true,
          'user_id': 'a3f2e8c5d',
          'username': null,
          'phone': '+919876543210',
          'accesskey': 'ak-new',
          'refreshToken': 'rt-new',
          'accesskeyExpiresAt': now + 2592000000,
          'refreshTokenExpiresAt': now + 7776000000,
          'isNew': true,
        });
      };

      final result = await client.verifyOtp(
        phone: '+919876543210',
        code: '654321',
        sessionId: 'sess-123',
      );

      expect(result.accesskey, 'ak-new');
      expect(result.refreshToken, 'rt-new');
      expect(result.userId, 'a3f2e8c5d');
      expect(result.isNewUser, true);

      // In-memory state updated.
      expect(client.currentAccesskey, 'ak-new');
      expect(client.currentUserId, 'a3f2e8c5d');
    });

    test('401 INVALID_CODE throws', () async {
      server.handler = (req) async {
        _respond(req, 401, {
          'error': {'code': 'INVALID_CODE', 'message': 'wrong OTP'}
        });
      };

      try {
        await client.verifyOtp(
          phone: '+919876543210',
          code: '000000',
          sessionId: 'sess-123',
        );
        fail('should throw');
      } on AuthClientException catch (e) {
        expect(e.statusCode, 401);
        expect(e.errorCode, 'INVALID_CODE');
        expect(e.isAuthFailure, true);
      }
    });
  });

  group('refresh (AuthTokenProvider)', () {
    test('exchanges refreshToken for new accesskey', () async {
      // Seed a session so refresh has tokens to use.
      client.restoreSession(
        accesskey: 'old-ak',
        userId: 'a3f2e8c5d',
        refreshToken: 'rt-old',
        deviceId: 'device-001',
      );

      server.handler = (req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/v3.0/auth/session/refresh');
        final body =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        expect(body['refreshToken'], 'rt-old');
        expect(body['deviceId'], 'device-001');
        _respond(req, 200, {
          'user_id': 'a3f2e8c5d',
          'accesskey': 'ak-fresh',
          'refreshToken': 'rt-fresh',
          'accesskeyExpiresAt': 1749859200000,
          'refreshTokenExpiresAt': 1755043200000,
        });
      };

      final newKey = await client.refresh();
      expect(newKey, 'ak-fresh');
      expect(client.currentAccesskey, 'ak-fresh');
    });

    test('returns null when no refreshToken', () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');
      final newKey = await client.refresh();
      expect(newKey, isNull);
    });
  });

  group('revokeSession', () {
    test('200 succeeds silently', () async {
      client.restoreSession(
        accesskey: 'ak-1',
        userId: 'u',
        refreshToken: 'rt-1',
      );

      server.handler = (req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/v3.0/auth/session/revoke');
        expect(req.headers.value('authorization'), 'Bearer ak-1');
        final body =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        expect(body['refreshToken'], 'rt-1');
        _respond(req, 200, {'status': true});
      };

      await client.revokeSession(); // no throw
    });
  });

  group('getOwnProfile', () {
    test('200 returns profile map', () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');

      server.handler = (req) async {
        expect(req.method, 'GET');
        expect(req.uri.path, '/v3.0/users/me');
        expect(req.headers.value('authorization'), 'Bearer ak');
        _respond(req, 200, {
          'user_id': 'u',
          'username': 'alice',
          'phone': '+91123',
          'displayName': 'Alice',
          'avatarUrl': null,
          'statusText': null,
          'createdAt': 1744675200000,
        });
      };

      final profile = await client.getOwnProfile();
      expect(profile['username'], 'alice');
      expect(profile['user_id'], 'u');
    });
  });

  group('lookupContacts', () {
    test('200 returns ContactMatch list', () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');

      server.handler = (req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/v3.0/contacts/lookup');
        _respond(req, 200, {
          'matches': [
            {
              'phoneHash': 'abc123',
              'user_id': 'b1c2d3e4f',
              'username': 'bob',
            },
            {
              'phoneHash': 'def456',
              'user_id': 'c2d3e4f5a',
              'username': null,
            },
          ]
        });
      };

      final matches = await client.lookupContacts(['abc123', 'def456']);
      expect(matches, hasLength(2));
      expect(matches[0].userId, 'b1c2d3e4f');
      expect(matches[0].username, 'bob');
      expect(matches[1].username, isNull);
    });
  });

  group('deleteAccount', () {
    test('200 succeeds', () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');

      server.handler = (req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/v3.0/users/me/delete');
        final body =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        expect(body['confirmation'], 'DELETE alice');
        _respond(req, 200, {'status': true});
      };

      await client.deleteAccount(confirmation: 'DELETE alice');
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal in-process HTTP server (reuses pattern from transport_test.dart)
// ---------------------------------------------------------------------------

class _TestServer {
  HttpServer? _http;
  Future<void> Function(HttpRequest req)? handler;

  Uri get uri => Uri.parse('http://127.0.0.1:${_http!.port}');

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http!.listen((req) async {
      final h = handler;
      if (h == null) {
        req.response.statusCode = 500;
        await req.response.close();
        return;
      }
      try {
        await h(req);
      } catch (e) {
        try {
          req.response.statusCode = 500;
          req.response.write('handler_error: $e');
        } catch (_) {}
        try {
          await req.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> stop() async {
    await _http?.close(force: true);
  }
}

void _respond(HttpRequest req, int status, Map<String, dynamic> body) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(body));
  req.response.close();
}
