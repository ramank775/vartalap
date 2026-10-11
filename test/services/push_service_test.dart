/// PushService is a small state machine over a distributor it cannot
/// have in a headless test: the user's choice picks a distributor, the
/// server's VAPID key goes into the registration, the distributor hands
/// back an endpoint with Web Push keys, and those are posted
/// (AUTH_CONTRACT §5). A wake makes it pull. These tests drive that
/// machine through a fake distributor.
library vartalap.services.push_service_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/services/push_service.dart';

import '../fake_unified_push.dart';

const _ntfy = 'io.heckel.ntfy';
const _nextPush = 'org.unifiedpush.distributor.nextpush';
const _vapidB =
    'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

void main() {
  group('resolvePushChoice', () {
    String? resolve(String? saved, bool google, List<String> apps) =>
        resolvePushChoice(
            saved: saved, googleAvailable: google, distributors: apps);

    test('nothing saved: ask unless there is exactly one way and no Google',
        () {
      // googleAvailable x number of push apps.
      expect(resolve(null, false, []), isNull, reason: 'install prompt');
      expect(resolve(null, false, [_ntfy]), _ntfy, reason: 'silent');
      expect(resolve(null, false, [_ntfy, _nextPush]), isNull,
          reason: 'pick one');
      expect(resolve(null, true, []), isNull,
          reason: 'Google is never picked for the user');
      expect(resolve(null, true, [_ntfy]), isNull, reason: 'must ask');
      expect(resolve(null, true, [_ntfy, _nextPush]), isNull);
    });

    test('a saved choice wins while it still works', () {
      for (final google in [false, true]) {
        for (final apps in [
          <String>[],
          [_ntfy],
          [_ntfy, _nextPush],
        ]) {
          expect(resolve(kPushChoiceNone, google, apps), kPushChoiceNone);
        }
        expect(resolve(_nextPush, google, [_ntfy, _nextPush]), _nextPush);
        expect(resolve(_ntfy, google, [_ntfy]), _ntfy);
      }
      expect(resolve(kPushChoiceGoogle, true, []), kPushChoiceGoogle);
      expect(resolve(kPushChoiceGoogle, true, [_ntfy]), kPushChoiceGoogle);
    });

    test('a saved choice that stopped working is decided afresh', () {
      // The push app was uninstalled.
      expect(resolve(_nextPush, false, [_ntfy]), _ntfy);
      expect(resolve(_nextPush, false, []), isNull);
      expect(resolve(_nextPush, true, [_ntfy]), isNull);
      // Google went away (Play services disabled, or a foss build).
      expect(resolve(kPushChoiceGoogle, false, [_ntfy]), _ntfy);
      expect(resolve(kPushChoiceGoogle, false, []), isNull);
      expect(resolve(kPushChoiceGoogle, false, [_ntfy, _nextPush]), isNull);
    });
  });

  group('PushService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('Google on offer → ask; choosing it registers with the VAPID key '
        'and posts endpoint + keys', () async {
      final f = _Fixture(google: true, distributors: const [_ntfy]);
      await f.service.start();

      expect(f.service.state.value, PushState.choiceNeeded);
      expect(f.push.registerVapids, isEmpty);
      expect(f.permissionRequests, 0, reason: 'nothing chosen yet');

      await f.service.choose(kPushChoiceGoogle);

      expect(f.permissionRequests, 1, reason: 'asked after the choice');
      expect(f.push.savedDistributor, kPushChoiceGoogle);
      expect(f.push.registerVapids, [vapidA],
          reason: 'AUTH_CONTRACT §5.0: the server key goes to register');
      expect(f.client.posts, isEmpty, reason: 'no endpoint yet');

      await f.push.emitEndpoint('https://fcm.googleapis.com/fcm/send/t1');

      expect(f.client.posts, [
        {
          'endpoint': 'https://fcm.googleapis.com/fcm/send/t1',
          'p256dh': 'p256dh-1',
          'auth': 'auth-1',
        }
      ]);
      expect(f.service.state.value, PushState.registered);
      expect(f.service.choiceLabel, 'Google Play services');
      expect((await SharedPreferences.getInstance()).getString(kPushChoiceKey),
          kPushChoiceGoogle);
    });

    test('one push app and no Google → used silently, and remembered',
        () async {
      final f = _Fixture(distributors: const [_ntfy]);
      await f.service.start();

      expect(f.push.savedDistributor, _ntfy);
      expect(f.push.registerVapids, [vapidA]);
      expect(f.permissionRequests, 1);
      expect(f.service.choiceLabel, 'ntfy');
      expect((await SharedPreferences.getInstance()).getString(kPushChoiceKey),
          _ntfy);

      await f.push.emitEndpoint('https://ntfy.sh/upAbC');
      expect(f.service.state.value, PushState.registered);
      expect(f.service.endpoint, 'https://ntfy.sh/upAbC');
    });

    test('no push app and no Google → ask (install prompt)', () async {
      final f = _Fixture(distributors: const []);
      await f.service.start();

      expect(f.service.state.value, PushState.choiceNeeded);
      expect(f.push.registerVapids, isEmpty);
      expect(f.client.posts, isEmpty);
      expect(f.permissionRequests, 0);
    });

    test('options list Google and each push app by name', () async {
      final f =
          _Fixture(google: true, distributors: const [_ntfy, _nextPush]);
      final options = await f.service.options();

      expect(options.google, isTrue);
      expect(options.distributors,
          {_ntfy: 'ntfy', _nextPush: _nextPush},
          reason: 'no label → the package name');
    });

    test('an endpoint without Web Push keys is an error, never posted',
        () async {
      final f = _Fixture(distributors: const [_ntfy]);
      await f.service.start();

      await f.push.emitEndpoint('https://ntfy.sh/upAbC', keys: false);

      expect(f.service.state.value, PushState.failed);
      expect(f.client.posts, isEmpty);
      expect(await f.storage.read(key: PushService.keyEndpoint), isNull);
    });

    test('a rotated VAPID key re-registers and re-posts', () async {
      final f = _Fixture(distributors: const [_ntfy]);
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.sh/upAbC');
      expect(f.client.posts, hasLength(1));

      // Same key on the next start: nothing new is posted.
      await f.newService().start();
      expect(f.client.posts, hasLength(1));

      f.client.vapid = _vapidB;
      final restarted = f.newService();
      await restarted.start();

      expect(f.push.registerVapids.last, _vapidB);
      expect(restarted.endpoint, isNull,
          reason: 'the endpoint was minted for the old key');
      await f.push.emitEndpoint('https://ntfy.sh/upAbC', p256dh: 'p256dh-2');
      expect(f.client.posts, hasLength(2));
      expect(f.client.posts.last['p256dh'], 'p256dh-2');
      expect(restarted.state.value, PushState.registered);
    });

    test('offline start registers with the cached VAPID key', () async {
      final f = _Fixture(distributors: const [_ntfy]);
      await f.service.start();

      f.client.vapidFails = true;
      await f.newService().start();

      expect(f.push.registerVapids, [vapidA, vapidA]);
    });

    test('no VAPID key at all → failed, nothing registered', () async {
      final f = _Fixture(distributors: const [_ntfy]);
      f.client.vapidFails = true;
      await f.service.start();

      expect(f.service.state.value, PushState.failed);
      expect(f.push.registerVapids, isEmpty);
    });

    test('an unchanged endpoint is not re-posted, a changed one is',
        () async {
      final f = _Fixture(distributors: const [_ntfy]);
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.sh/upAbC');

      // App restart: same user, same endpoint → the server already has
      // it, so no second POST.
      final restarted = f.newService();
      await restarted.start();
      expect(f.client.posts, hasLength(1));
      expect(restarted.state.value, PushState.registered);

      // The distributor rotates the endpoint → re-post.
      await f.push.emitEndpoint('https://ntfy.sh/rotated');
      expect(f.client.posts.map((p) => p['endpoint']),
          ['https://ntfy.sh/upAbC', 'https://ntfy.sh/rotated']);
    });

    test('a different user on the same device re-posts the endpoint',
        () async {
      final f = _Fixture(distributors: const [_ntfy]);
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.sh/upAbC');

      f.client.restoreSession(accesskey: 'sk_b', userId: 'b00000001');
      await f.service.refresh();

      expect(f.client.posts, hasLength(2),
          reason: 'the endpoint is stored per (user_id, deviceId)');
    });

    test('switching push method unregisters the old one first', () async {
      final f = _Fixture(google: true, distributors: const [_ntfy]);
      await f.service.start();
      await f.service.choose(_ntfy);
      await f.push.emitEndpoint('https://ntfy.sh/upAbC');

      await f.service.choose(kPushChoiceGoogle);

      expect(f.push.unregisterCalls, 1);
      expect(f.push.savedDistributor, kPushChoiceGoogle);
      expect(f.service.endpoint, isNull);
      await f.push.emitEndpoint('https://fcm.googleapis.com/fcm/send/t2');
      expect(f.client.posts.last['endpoint'],
          'https://fcm.googleapis.com/fcm/send/t2');
    });

    test('"Not now" deregisters, sticks, and asks for nothing', () async {
      final f = _Fixture(google: true, distributors: const [_ntfy]);
      await f.service.start();

      await f.service.choose(kPushChoiceNone);
      await f.newService().start();

      expect(f.service.state.value, PushState.off);
      expect(f.service.choice, kPushChoiceNone);
      expect(f.push.registerVapids, isEmpty);
      expect(f.permissionRequests, 0);
      expect(f.client.posts.single, {'endpoint': null});
    });

    test('logout deregisters the endpoint and the distributor', () async {
      final f = _Fixture(distributors: const [_ntfy]);
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.sh/upAbC');

      await f.service.deregister();

      expect(f.client.posts.last, {'endpoint': null},
          reason: 'null deregisters');
      expect(f.push.unregisterCalls, 1);
      expect(f.service.endpoint, isNull);
      expect(await f.storage.read(key: PushService.keyEndpoint), isNull);
      expect(
          await f.storage.read(key: PushService.keyRegisteredEndpoint), isNull);
      expect(f.service.state.value, PushState.disabled);
    });

    test('the distributor dropping us clears the stored endpoint',
        () async {
      final f = _Fixture(distributors: const [_ntfy]);
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.sh/upAbC');

      await f.push.emitUnregistered();

      expect(f.service.state.value, PushState.disabled);
      expect(await f.storage.read(key: PushService.keyEndpoint), isNull);
    });

    test('a rejected endpoint leaves the service in failed', () async {
      final f = _Fixture(distributors: const [_ntfy]);
      f.client.throwOnRegister = true;
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.sh/upAbC');

      expect(f.service.state.value, PushState.failed);
      expect(await f.storage.read(key: PushService.keyRegisteredEndpoint),
          isNull);
    });

    test('a wake pulls and then notifies — in that order', () async {
      final f = _Fixture(distributors: const [_ntfy]);
      final order = <String>[];
      f.service.onWake = () async => order.add('wake');
      f.notified = () async => order.add('notify');
      await f.service.start();

      await f.push.emitMessage();

      expect(order, ['wake', 'notify']);
    });

    test('a failing pull still notifies', () async {
      final f = _Fixture(distributors: const [_ntfy]);
      f.service.onWake = () async => throw StateError('offline');
      await f.service.start();

      await f.push.emitMessage();

      expect(f.notifyCount, 1);
    });
  });
}

class _Fixture {
  final FakeUnifiedPush push;
  final FakePushAuthClient client = FakePushAuthClient();
  final InMemorySecureStorage storage = InMemorySecureStorage();
  late PushService service;

  int notifyCount = 0;
  int permissionRequests = 0;
  Future<void> Function()? notified;

  _Fixture({bool google = false, List<String> distributors = const []})
      : push = FakeUnifiedPush(
            google: google,
            distributors: distributors,
            labels: const {_ntfy: 'ntfy'}) {
    client.restoreSession(accesskey: 'sk_a', userId: 'a00000001');
    service = newService();
  }

  PushService newService() => PushService(
        authClient: client,
        unifiedPush: push,
        storage: storage,
        notifyWake: () async {
          notifyCount++;
          await notified?.call();
        },
        requestPermission: () async => permissionRequests++,
      );
}
