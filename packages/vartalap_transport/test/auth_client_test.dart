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

  group('resendOtp', () {
    test('posts the session id and returns the same session', () async {
      server.handler = (req) async {
        expect(req.uri.path, '/v3.0/auth/otp/resend');
        final body =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        expect(body, {'sessionId': 'sess-123'});
        _respond(req, 200, {
          'sessionId': 'sess-123',
          'resendAfterSec': 30,
          'expiresInSec': 540,
          'isExistingAccount': false,
        });
      };
      final result = await client.resendOtp(sessionId: 'sess-123');
      expect(result.sessionId, 'sess-123');
      expect(result.expiresIn, const Duration(seconds: 540));
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
        req.response.headers.date = DateTime.utc(2026, 10, 18, 9, 30);
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
      // The server's clock at sign-in (seeds a fresh pull pointer).
      expect(client.signedInAt, DateTime.utc(2026, 10, 18, 9, 30));
    });

    test('an unparseable Date leaves signedInAt null', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      server.handler = (req) async {
        req.response.headers.set('date', 'not a date');
        _respond(req, 200, {
          'user_id': 'a3f2e8c5d',
          'accesskey': 'ak-new',
          'refreshToken': 'rt-new',
          'accesskeyExpiresAt': now + 2592000000,
          'refreshTokenExpiresAt': now + 7776000000,
        });
      };
      await client.verifyOtp(
        phone: '+919876543210',
        code: '654321',
        sessionId: 'sess-123',
      );
      expect(client.signedInAt, isNull);
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

  group('patchOwnProfile', () {
    test('absent stays absent, explicit null clears — AUTH_CONTRACT §4.5',
        () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');
      Map<String, dynamic>? sent;

      server.handler = (req) async {
        expect(req.method, 'PATCH');
        expect(req.uri.path, '/v3.0/users/me');
        sent = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        _respond(req, 200, {'user_id': 'u', 'username': 'alice'});
      };

      await client.patchOwnProfile(
        username: (value: 'alice'),
        usernameKey: (value: '4821'),
        statusText: (value: null),
      );

      expect(sent!['username'], 'alice');
      expect(sent!['usernameKey'], '4821');
      expect(
        sent!.containsKey('statusText'),
        isTrue,
        reason: '§4.5: explicit null is the only way to clear a field.',
      );
      expect(sent!['statusText'], isNull);
      expect(
        sent!.containsKey('displayName'),
        isFalse,
        reason: '§4.5: an absent key means "unchanged".',
      );
    });
  });

  group('lookupByUsername', () {
    test('200 returns the public profile, key goes on the query string',
        () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');

      server.handler = (req) async {
        expect(req.method, 'GET');
        expect(req.uri.path, '/v3.0/users/by-username/kavya_m');
        expect(req.uri.queryParameters['key'], '4821');
        _respond(req, 200, {
          'user_id': 'a3f2e8c5d',
          'username': 'kavya_m',
          'displayName': 'Kavya Menon',
          'avatarUrl': null,
          'statusText': 'Back in Kochi',
        });
      };

      final profile =
          await client.lookupByUsername('Kavya_M', key: '4821');
      expect(profile['user_id'], 'a3f2e8c5d');
      expect(
        profile.containsKey('phone'),
        isFalse,
        reason: 'AUTH_CONTRACT §2.5: no other user\'s phone, ever.',
      );
    });

    test('404 surfaces the error code so the picker can ask for a key',
        () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');

      server.handler = (req) async {
        expect(req.uri.queryParameters.containsKey('key'), isFalse);
        _respond(req, 404, {
          'error': {
            'code': 'USERNAME_KEY_REQUIRED',
            'message': 'This handle requires a key',
          }
        });
      };

      try {
        await client.lookupByUsername('kavya_m');
        fail('should throw');
      } on AuthClientException catch (e) {
        expect(e.statusCode, 404);
        expect(e.errorCode, 'USERNAME_KEY_REQUIRED');
      }
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

  group('push (AUTH_CONTRACT §5)', () {
    const vapid = 'BOr6qTqDDQ5GNw8yC2v2Q8x5LJQfj3zLc8l2E2kQyQ8hT4Pq9b0u8Q2uB7wF5yJ'
        'bL3pZ6nQ0kS1vX4cT9mA2dEQ';

    test('getVapidKey reads vapidPublicKey from GET /v3.0/push/vapid',
        () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');
      server.handler = (req) async {
        expect(req.method, 'GET');
        expect(req.uri.path, '/v3.0/push/vapid');
        expect(req.headers.value('authorization'), 'Bearer ak');
        _respond(req, 200, {'vapidPublicKey': vapid});
      };

      expect(await client.getVapidKey(), vapid);
    });

    test('registerPushTopic posts endpoint, p256dh and auth', () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');
      late Map<String, dynamic> body;
      server.handler = (req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/v3.0/push/topic');
        body =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        _respond(req, 200, {'status': true});
      };

      await client.registerPushTopic(
        endpoint: 'https://fcm.googleapis.com/fcm/send/tok',
        p256dh: 'BNcR',
        auth: 'tBHI',
      );
      expect(body, {
        'endpoint': 'https://fcm.googleapis.com/fcm/send/tok',
        'p256dh': 'BNcR',
        'auth': 'tBHI',
      });
    });

    test('a null endpoint deregisters and sends no keys', () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');
      late Map<String, dynamic> body;
      server.handler = (req) async {
        body =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        _respond(req, 200, {'status': true});
      };

      await client.registerPushTopic(endpoint: null);
      expect(body, {'endpoint': null});
    });

    test('400 INVALID_PUSH_KEYS surfaces the error code', () async {
      client.restoreSession(accesskey: 'ak', userId: 'u');
      server.handler = (req) async {
        _respond(req, 400, {
          'error': {'code': 'INVALID_PUSH_KEYS', 'message': 'bad keys'}
        });
      };

      await expectLater(
        client.registerPushTopic(endpoint: 'https://ntfy.sh/up1'),
        throwsA(isA<AuthClientException>()
            .having((e) => e.errorCode, 'errorCode', 'INVALID_PUSH_KEYS')),
      );
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

  group('E2EE device-key directory', () {
    const userId = 'a3f2e8c5d';
    const generation = 'b6cb8ea5-fcee-4bf2-8734-ad0a90252464';
    String publicKey([int value = 0]) =>
        base64.encode([5, ...List.filled(32, value)]);
    Map<String, dynamic> signedKey() => {
          'id': 1,
          'publicKey': publicKey(),
          'signature': base64.encode(List.filled(64, 0)),
        };
    Map<String, dynamic> bundle({String deviceId = 'device-001'}) => {
          'deviceId': deviceId,
          'generation': generation,
          'identityKey': publicKey(),
          'registrationId': 42,
          'signedPreKey': signedKey(),
        };
    E2eeKeyUpload upload({List<E2eePreKey>? keys}) => E2eeKeyUpload(
          identityKey: publicKey(),
          registrationId: 42,
          signedPreKey: E2eeSignedPreKey.fromJson(signedKey()),
          preKeys: keys ?? [E2eePreKey(id: 0, publicKey: publicKey())],
        );

    setUp(() => client.restoreSession(
        accesskey: 'ak', userId: userId, deviceId: 'device-001'));

    test('publishes only public material with authenticated PUT', () async {
      server.handler = (req) async {
        expect(req.method, 'PUT');
        expect(req.uri.path, '/v3.0/keys/me');
        expect(req.headers.value('Authorization'), 'Bearer ak');
        expect(req.headers.contentType?.mimeType, 'application/json');
        final body = jsonDecode(await utf8.decodeStream(req));
        expect(body, upload().toJson());
        // Retrying an older signed prekey may return a newer published key.
        _respond(req, 200, {
          ...bundle(),
          'signedPreKey': {...signedKey(), 'id': 2},
          'preKeyCount': 1
        });
      };
      final result = await client.publishDeviceKeys(upload());
      expect(result.bundle.deviceId, 'device-001');
      expect(result.bundle.generation, generation);
      expect(result.bundle.signedPreKey.id, 2);
      expect(result.preKeyCount, 1);
    });

    test('directory returns validated devices and permits an empty directory',
        () async {
      server.handler = (req) async {
        expect(req.method, 'GET');
        expect(req.uri.path, '/v3.0/keys/$userId');
        expect(req.headers.value('Authorization'), 'Bearer ak');
        _respond(req, 200, {
          'devices': [bundle(), bundle(deviceId: 'second-phone')]
        });
      };
      final devices = await client.getDeviceKeys(userId);
      expect(devices.map((device) => device.deviceId),
          ['device-001', 'second-phone']);
      expect(devices.first.identityKey, publicKey());
      expect(() => devices.clear(), throwsUnsupportedError);
      server.handler = (req) async => _respond(req, 200, {'devices': []});
      expect(await client.getDeviceKeys(userId), isEmpty);
    });

    test('claim accepts a one-time key or signed-prekey-only exhaustion',
        () async {
      for (final preKey in [
        null,
        {'id': 0xffffff, 'publicKey': publicKey()}
      ]) {
        server.handler = (req) async {
          expect(req.method, 'POST');
          expect(req.uri.path, '/v3.0/keys/$userId/claim');
          expect(req.headers.value('Authorization'), 'Bearer ak');
          expect(jsonDecode(await utf8.decodeStream(req)),
              {'deviceId': 'device-001', 'generation': generation});
          _respond(req, 200, {...bundle(), 'preKey': preKey});
        };
        final result = await client.claimDeviceKeys(userId,
            deviceId: 'device-001', generation: generation);
        expect(result.preKey?.id, preKey?['id']);
      }
    });

    test('upload validates limits and freezes the caller prekey list',
        () async {
      final keys = [E2eePreKey(id: 0, publicKey: publicKey())];
      final frozen = upload(keys: keys);
      keys.clear();
      expect(frozen.preKeys, hasLength(1));
      expect(() => frozen.preKeys.clear(), throwsUnsupportedError);
      expect(() => upload(keys: [frozen.preKeys.first, frozen.preKeys.first]),
          throwsFormatException);
      expect(
          () => upload(
              keys: List.generate(
                  201, (id) => E2eePreKey(id: id, publicKey: publicKey()))),
          throwsFormatException);
      expect(() => E2eePreKey(id: -1, publicKey: publicKey()),
          throwsFormatException);
      expect(() => E2eePreKey(id: 0x1000000, publicKey: publicKey()),
          throwsFormatException);
      expect(() => upload(keys: [E2eeSignedPreKey.fromJson(signedKey())]),
          throwsFormatException);
      server.handler = (req) async {
        expect((jsonDecode(await utf8.decodeStream(req)) as Map)['preKeys'],
            isEmpty);
        _respond(req, 200, {...bundle(), 'preKeyCount': 0});
      };
      expect((await client.publishDeviceKeys(upload(keys: []))).preKeyCount, 0);
    });

    test('all key endpoints preserve HTTP errors and error codes', () async {
      final calls = <Future<Object> Function()>[
        () => client.publishDeviceKeys(upload()),
        () => client.getDeviceKeys(userId),
        () => client.claimDeviceKeys(userId,
            deviceId: 'device-001', generation: generation),
      ];
      for (final status in [401, 403, 404, 409, 429, 503]) {
        server.handler = (req) async => _respond(req, status, {
              'error': {
                'code': 'KEY_ERROR',
                'message': 'retry or reauthenticate'
              }
            });
        for (final call in calls) {
          await expectLater(
              call(),
              throwsA(isA<AuthClientException>()
                  .having((error) => error.statusCode, 'status', status)
                  .having((error) => error.errorCode, 'code', 'KEY_ERROR')
                  .having((error) => error.message, 'message',
                      'retry or reauthenticate')));
        }
      }
    });

    test('requires authentication and rejects unsafe request identifiers',
        () async {
      var requests = 0;
      server.handler = (req) async {
        requests++;
        _respond(req, 500, {});
      };
      for (final user in ['../me', 'a3f2e8c5d/claim', 'A3F2E8C5D', '']) {
        await expectLater(client.getDeviceKeys(user), throwsFormatException);
        await expectLater(
            client.claimDeviceKeys(user,
                deviceId: 'device-001', generation: generation),
            throwsFormatException);
      }
      for (final device in ['', 'x' * 257]) {
        await expectLater(
            client.claimDeviceKeys(userId,
                deviceId: device, generation: generation),
            throwsFormatException);
      }
      await expectLater(
          client.claimDeviceKeys(userId,
              deviceId: 'device-001', generation: 'not-a-uuid'),
          throwsFormatException);
      client.clearSession();
      await expectLater(client.publishDeviceKeys(upload()), throwsStateError);
      await expectLater(client.getDeviceKeys(userId), throwsStateError);
      await expectLater(
          client.claimDeviceKeys(userId,
              deviceId: 'device-001', generation: generation),
          throwsStateError);
      expect(requests, 0);
    });

    test('rejects malformed directory key material and metadata', () async {
      final malformed = <Object?>[
        null,
        [],
        'bundle',
        {...bundle(), 'identityKey': base64.encode(List.filled(33, 0))},
        {
          ...bundle(),
          'identityKey': base64.encode([5, ...List.filled(31, 0)])
        },
        {...bundle(), 'identityKey': publicKey(255).replaceAll('/', '_')},
        {...bundle(), 'registrationId': 0},
        {...bundle(), 'registrationId': 16384},
        {...bundle(), 'registrationId': 42.0},
        {...bundle(), 'deviceId': ''},
        {...bundle(), 'deviceId': 'x' * 257},
        {...bundle(), 'generation': 'wrong'},
        {...bundle(), 'privateKey': 'must never be accepted'},
        {
          ...bundle(),
          'signedPreKey': {...signedKey(), 'id': -1}
        },
        {
          ...bundle(),
          'signedPreKey': {...signedKey(), 'id': 1.0}
        },
        {
          ...bundle(),
          'signedPreKey': {
            ...signedKey(),
            'signature': base64.encode(List.filled(63, 0))
          }
        },
        {
          ...bundle(),
          'signedPreKey': {
            ...signedKey(),
            'signature':
                (signedKey()['signature'] as String).replaceAll('=', '')
          }
        },
        {...bundle(), 'preKey': null},
      ];
      for (final device in malformed) {
        server.handler = (req) async => _respond(req, 200, {
              'devices': [device]
            });
        await expectLater(client.getDeviceKeys(userId), throwsFormatException);
      }
      for (final directory in [
        <String, dynamic>{},
        {'devices': null},
        {
          'devices': [bundle(), bundle()]
        },
        {'devices': [], 'privateKey': 'bad'}
      ]) {
        server.handler = (req) async => _respond(req, 200, directory);
        await expectLater(client.getDeviceKeys(userId), throwsFormatException);
      }
    });

    test('rejects malformed publication counts and mismatched ownership',
        () async {
      for (final response in [
        {...bundle()},
        {...bundle(), 'preKeyCount': -1},
        {...bundle(), 'preKeyCount': 201},
        {...bundle(), 'preKeyCount': 1.0},
        {...bundle(deviceId: 'wrong-device'), 'preKeyCount': 0},
        {...bundle(), 'identityKey': publicKey(1), 'preKeyCount': 0},
        {...bundle(), 'registrationId': 43, 'preKeyCount': 0},
      ]) {
        server.handler = (req) async => _respond(req, 200, response);
        await expectLater(
            client.publishDeviceKeys(upload()), throwsFormatException);
      }
    });

    test('rejects substituted claim targets and malformed one-time keys',
        () async {
      for (final response in [
        {...bundle()},
        {...bundle(), 'preKey': {}},
        {
          ...bundle(),
          'preKey': {'id': 1, 'publicKey': publicKey(), 'privateKey': 'bad'}
        },
        {
          ...bundle(),
          'preKey': {'id': 0x1000000, 'publicKey': publicKey()}
        },
        {...bundle(deviceId: 'different-device'), 'preKey': null},
        {
          ...bundle(),
          'generation': 'a9d892ad-821e-480f-8b87-6deded490654',
          'preKey': null
        },
      ]) {
        server.handler = (req) async => _respond(req, 200, response);
        await expectLater(
            client.claimDeviceKeys(userId,
                deviceId: 'device-001', generation: generation),
            throwsFormatException);
      }
    });

    test('rejects non-object JSON and malformed JSON responses', () async {
      for (final body in ['[]', 'null', '{bad-json']) {
        server.handler = (req) async {
          req.response.write(body);
          await req.response.close();
        };
        await expectLater(client.getDeviceKeys(userId), throwsFormatException);
      }
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
