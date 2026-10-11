/// The UnifiedPush plugin and its distributors, minus Android. Shared by
/// the push service, push chooser and golden-path tests.
library vartalap.test.fake_unified_push;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// A VAPID public key's shape: base64url, 87 chars.
const vapidA =
    'BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

/// Stands in for the UnifiedPush plugin and its distributors: holds the
/// callbacks PushService registers and lets the test fire them.
class FakeUnifiedPush implements UnifiedPushApi {
  bool google;
  List<String> distributors;
  final Map<String, String> labels;
  String? savedDistributor;
  final List<String> registerVapids = [];
  int unregisterCalls = 0;

  void Function(String, String?, String?)? _onNewEndpoint;
  void Function()? _onUnregistered;
  void Function()? _onMessage;

  FakeUnifiedPush({
    this.google = false,
    this.distributors = const [],
    this.labels = const {},
  });

  @override
  Future<void> initialize({
    required void Function(String url, String? p256dh, String? auth)
        onNewEndpoint,
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
  Future<bool> googleAvailable() async => google;

  @override
  Future<String?> label(String distributor) async => labels[distributor];

  @override
  Future<void> saveDistributor(String choice) async =>
      savedDistributor = choice;

  @override
  Future<void> register({required String vapid}) async =>
      registerVapids.add(vapid);

  @override
  Future<void> unregister() async => unregisterCalls++;

  // The plugin's callbacks are `void Function(...)`, so the async work
  // they kick off is not awaited by the caller. Tests need it settled
  // before asserting — one microtask drain does it.
  Future<void> emitEndpoint(
    String url, {
    bool keys = true,
    String p256dh = 'p256dh-1',
    String auth = 'auth-1',
  }) async {
    _onNewEndpoint!(url, keys ? p256dh : null, keys ? auth : null);
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
class FakePushAuthClient extends AuthClient {
  final List<Map<String, String?>> posts = [];
  String vapid = vapidA;
  bool vapidFails = false;
  bool throwOnRegister = false;

  FakePushAuthClient() : super(baseUrl: Uri.parse('https://example.invalid'));

  @override
  Future<String> getVapidKey() async {
    if (vapidFails) throw StateError('offline');
    return vapid;
  }

  @override
  Future<void> registerPushTopic({
    required String? endpoint,
    String? p256dh,
    String? auth,
  }) async {
    if (throwOnRegister) {
      throw StateError('simulated push/topic rejection');
    }
    posts.add(endpoint == null
        ? {'endpoint': null}
        : {'endpoint': endpoint, 'p256dh': p256dh, 'auth': auth});
  }
}
class InMemorySecureStorage implements FlutterSecureStorage {
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
        'InMemorySecureStorage.${invocation.memberName} — not used in these tests',
      );
}
