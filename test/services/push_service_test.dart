/// PushService is a small state machine over a distributor it cannot
/// have in a headless test: ntfy hands it an endpoint, it posts that
/// endpoint as the push topic (AUTH_CONTRACT §5.1), and a wake makes it
/// pull. These tests drive that machine through a fake distributor.
library vartalap.services.push_service_test;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  group('PushService', () {
    test('endpoint from the distributor is registered as the push topic',
        () async {
      final f = _Fixture();
      await f.service.start();

      expect(f.push.registerCalls, 1);
      expect(f.push.savedDistributor, kNtfyDistributorPackage);
      expect(f.client.topics, isEmpty, reason: 'no endpoint yet');

      await f.push.emitEndpoint('https://ntfy.example/u/abc123');

      expect(f.client.topics, ['https://ntfy.example/u/abc123']);
      expect(f.service.state.value, PushState.registered);
      expect(f.service.endpoint, 'https://ntfy.example/u/abc123');
      expect(
        await f.storage.read(key: PushService.keyEndpoint),
        'https://ntfy.example/u/abc123',
        reason: 'the endpoint survives a restart',
      );
    });

    test('an unchanged endpoint is not re-posted, a changed one is',
        () async {
      final f = _Fixture();
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.example/u/abc123');

      // App restart: same user, same endpoint → the server already has
      // it, so no second POST.
      final restarted = f.newService();
      await restarted.start();
      expect(f.client.topics.length, 1);
      expect(restarted.state.value, PushState.registered);

      // The distributor rotates the endpoint → re-post.
      await f.push.emitEndpoint('https://ntfy.example/u/rotated');
      expect(f.client.topics,
          ['https://ntfy.example/u/abc123', 'https://ntfy.example/u/rotated']);
    });

    test('a different user on the same device re-posts the endpoint',
        () async {
      final f = _Fixture();
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.example/u/abc123');

      f.client.restoreSession(accesskey: 'sk_b', userId: 'b00000001');
      await f.service.refresh();

      expect(f.client.topics.length, 2,
          reason: 'the topic is stored per (user_id, deviceId)');
    });

    test('logout deregisters the topic and the distributor', () async {
      final f = _Fixture();
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.example/u/abc123');

      await f.service.deregister();

      expect(f.client.topics.last, isNull, reason: 'null deregisters');
      expect(f.push.unregisterCalls, 1);
      expect(f.service.endpoint, isNull);
      expect(await f.storage.read(key: PushService.keyEndpoint), isNull);
      expect(
          await f.storage.read(key: PushService.keyRegisteredEndpoint), isNull);
      expect(f.service.state.value, PushState.disabled);
    });

    test('no ntfy app → prompt state, nothing registered', () async {
      final f = _Fixture(distributors: const []);
      await f.service.start();

      expect(f.service.state.value, PushState.distributorMissing);
      expect(f.push.registerCalls, 0);
      expect(f.client.topics, isEmpty);
    });

    test('the distributor dropping us clears the stored endpoint',
        () async {
      final f = _Fixture();
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.example/u/abc123');

      await f.push.emitUnregistered();

      expect(f.service.state.value, PushState.disabled);
      expect(await f.storage.read(key: PushService.keyEndpoint), isNull);
    });

    test('a rejected topic leaves the service in failed', () async {
      final f = _Fixture();
      f.client.throwOnRegister = true;
      await f.service.start();
      await f.push.emitEndpoint('https://ntfy.example/u/abc123');

      expect(f.service.state.value, PushState.failed);
      expect(await f.storage.read(key: PushService.keyRegisteredEndpoint),
          isNull);
    });

    test('a wake pulls and then notifies — in that order', () async {
      final f = _Fixture();
      final order = <String>[];
      f.service.onWake = () async => order.add('wake');
      f.notified = () async => order.add('notify');
      await f.service.start();

      await f.push.emitMessage();

      expect(order, ['wake', 'notify']);
    });

    test('a failing pull still notifies', () async {
      final f = _Fixture();
      f.service.onWake = () async => throw StateError('offline');
      await f.service.start();

      await f.push.emitMessage();

      expect(f.notifyCount, 1);
    });
  });
}

class _Fixture {
  final _FakeUnifiedPush push;
  final _FakeAuthClient client = _FakeAuthClient();
  final _InMemoryStorage storage = _InMemoryStorage();
  late PushService service;

  int notifyCount = 0;
  Future<void> Function()? notified;

  _Fixture({List<String> distributors = const [kNtfyDistributorPackage]})
      : push = _FakeUnifiedPush(distributors) {
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
        requestPermission: () async {},
      );
}

/// Stands in for the ntfy distributor: holds the callbacks PushService
/// registers and lets the test fire them.
class _FakeUnifiedPush implements UnifiedPushApi {
  final List<String> distributors;
  String? savedDistributor;
  int registerCalls = 0;
  int unregisterCalls = 0;

  void Function(String)? _onNewEndpoint;
  void Function()? _onUnregistered;
  void Function()? _onMessage;

  _FakeUnifiedPush(this.distributors);

  @override
  Future<void> initialize({
    required void Function(String endpointUrl) onNewEndpoint,
    required void Function() onUnregistered,
    required void Function() onMessage,
    required void Function(String reason) onRegistrationFailed,
  }) async {
    _onNewEndpoint = onNewEndpoint;
    _onUnregistered = onUnregistered;
    _onMessage = onMessage;
  }

  @override
  Future<List<String>> getDistributors() async => distributors;

  @override
  Future<void> saveDistributor(String distributor) async =>
      savedDistributor = distributor;

  @override
  Future<void> register() async => registerCalls++;

  @override
  Future<void> unregister() async => unregisterCalls++;

  // The plugin's callbacks are `void Function(...)`, so the async work
  // they kick off is not awaited by the caller. Tests need it settled
  // before asserting — one microtask drain does it.
  Future<void> emitEndpoint(String url) async {
    _onNewEndpoint!(url);
    await _settle();
  }

  Future<void> emitUnregistered() async {
    _onUnregistered!();
    await _settle();
  }

  Future<void> emitMessage() async {
    _onMessage!();
    await _settle();
  }

  Future<void> _settle() => Future<void>.delayed(Duration.zero);
}

/// Real [AuthClient] session state, faked network.
class _FakeAuthClient extends AuthClient {
  final List<String?> topics = [];
  bool throwOnRegister = false;

  _FakeAuthClient() : super(baseUrl: Uri.parse('https://example.invalid'));

  @override
  Future<void> registerPushTopic({required String? topicUrl}) async {
    if (throwOnRegister) {
      throw StateError('simulated push/topic rejection');
    }
    topics.add(topicUrl);
  }
}

class _InMemoryStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        '_InMemoryStorage.${invocation.memberName} — not used in these tests',
      );
}
