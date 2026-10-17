/// Push wake path — UnifiedPush with whichever distributor the user
/// picked: any push app (ntfy, NextPush, Sunup, a self-hosted ntfy, …)
/// or, in gms builds, the embedded FCM distributor that talks to Google
/// Play services (V3_ARCHITECTURE.md decision 6, DECISIONS 119-121).
///
/// Every endpoint is a Web Push endpoint: the server encrypts to this
/// device's keys and signs with its VAPID key (AUTH_CONTRACT §5); the
/// connector decrypts. The plaintext is a content-free wake
/// (SYNC_PROTOCOL.md §12.1), so everything this service can do on a
/// message is: pull `/sync/pending`, nudge the WS back up, and hand the
/// result to `MessageNotifications.afterWake`, which renders whatever
/// landed from the local store.
///
/// Endpoint lifecycle:
///   `GET /v3.0/push/vapid` → register with the chosen distributor →
///   `onNewEndpoint(url, keys)` → `POST /v3.0/push/topic` (AUTH_CONTRACT
///   §5.1) → remember what we posted → logout posts null and
///   unregisters.
library vartalap.services.push_service;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// SharedPreferences key: the push method the user chose —
/// [kPushChoiceGoogle], [kPushChoiceNone] or a push app's package name.
/// Per device, like the onboarding flag, so it survives logout.
const String kPushChoiceKey = 'push_choice';

/// Google Play services, through the embedded FCM distributor (gms only).
const String kPushChoiceGoogle = 'google';

/// "Not now": messages arrive only while the app is open.
const String kPushChoiceNone = 'none';

/// Which push method to use, or null when the user has to be asked.
///
/// A saved choice wins while it still works. Without one the app picks
/// only when there is nothing to ask: Google is not on offer and exactly
/// one push app is installed. Google is never picked for the user
/// (DECISIONS 120).
String? resolvePushChoice({
  required String? saved,
  required bool googleAvailable,
  required List<String> distributors,
}) {
  if (saved == kPushChoiceNone ||
      (saved == kPushChoiceGoogle && googleAvailable) ||
      distributors.contains(saved)) {
    return saved;
  }
  if (!googleAvailable && distributors.length == 1) {
    return distributors.single;
  }
  return null;
}

enum PushState {
  /// Before [PushService.refresh] has looked at the system, or while a
  /// registration is on its way.
  unknown,

  /// Endpoint held AND accepted by the server for this user.
  registered,

  /// No push method chosen and none the app may pick by itself — the
  /// chooser has to ask (onboarding, Settings).
  choiceNeeded,

  /// The user chose "Not now".
  off,

  /// Registered with nobody: logged out, or the distributor dropped us.
  disabled,

  /// The distributor refused, handed us no encryption keys, or the
  /// server said no.
  failed,
}

/// What the chooser can offer right now.
class PushOptions {
  /// A gms build on a phone with Play services.
  final bool google;

  /// Installed push apps: package → app name.
  final Map<String, String> distributors;

  const PushOptions({required this.google, required this.distributors});
}

/// The slice of the `unifiedpush` plugin (plus the app's `vartalap/push`
/// channel) this service uses. A seam, not an abstraction: it exists so
/// the state machine can be unit-tested without an Android distributor.
abstract class UnifiedPushApi {
  Future<void> initialize({
    required void Function(String url, String? p256dh, String? auth)
        onNewEndpoint,
    required void Function() onUnregistered,
    required void Function() onMessage,
    required void Function(String reason) onRegistrationFailed,
  });

  /// Installed push apps by package — not the embedded Google one.
  Future<List<String>> getDistributors();

  /// A gms build on a phone with Play services.
  Future<bool> googleAvailable();

  /// A push app's name, or null if the system won't say.
  Future<String?> label(String distributor);

  /// [choice] is [kPushChoiceGoogle] or a package from [getDistributors].
  Future<void> saveDistributor(String choice);

  Future<void> register({required String vapid});

  Future<void> unregister();
}

/// The real plugin.
class PluginUnifiedPush implements UnifiedPushApi {
  const PluginUnifiedPush();

  /// MainActivity's channel; the Google check lives only in the gms
  /// source set, the foss one always answers false.
  static const MethodChannel _channel = MethodChannel('vartalap/push');

  /// In gms builds the embedded FCM distributor answers as this app.
  static Future<String> _self() async =>
      (await PackageInfo.fromPlatform()).packageName;

  @override
  Future<void> initialize({
    required void Function(String url, String? p256dh, String? auth)
        onNewEndpoint,
    required void Function() onUnregistered,
    required void Function() onMessage,
    required void Function(String reason) onRegistrationFailed,
  }) async {
    await UnifiedPush.initialize(
      onNewEndpoint: (endpoint, _) => onNewEndpoint(endpoint.url,
          endpoint.pubKeySet?.pubKey, endpoint.pubKeySet?.auth),
      onRegistrationFailed: (reason, _) => onRegistrationFailed(reason.name),
      onUnregistered: (_) => onUnregistered(),
      // Already decrypted by the connector, and only ever a wake.
      onMessage: (_, __) => onMessage(),
    );
  }

  @override
  Future<List<String>> getDistributors() async {
    final self = await _self();
    return [
      for (final d in await UnifiedPush.getDistributors())
        if (d != self) d,
    ];
  }

  @override
  Future<bool> googleAvailable() async =>
      await _channel.invokeMethod<bool>('googleAvailable') ?? false;

  @override
  Future<String?> label(String distributor) =>
      _channel.invokeMethod<String>('appLabel', distributor);

  @override
  Future<void> saveDistributor(String choice) async =>
      UnifiedPush.saveDistributor(
          choice == kPushChoiceGoogle ? await _self() : choice);

  @override
  Future<void> register({required String vapid}) =>
      UnifiedPush.register(vapid: vapid);

  @override
  Future<void> unregister() => UnifiedPush.unregister();
}

typedef _Endpoint = ({String url, String p256dh, String auth});

class PushService {
  /// The endpoint and keys the distributor handed us, as JSON, whatever
  /// the server knows.
  static const String keyEndpoint = 'v3.push.endpoint';

  /// `<user_id>|<endpoint>|<p256dh>|<auth>` — what we last got a 200
  /// for. There is no server readback route, so this is the client's
  /// record of "what the server has". A mismatch on login or app start
  /// means re-post.
  static const String keyRegisteredEndpoint = 'v3.push.registeredEndpoint';

  /// The server's VAPID public key we last registered with.
  static const String keyVapid = 'v3.push.vapid';

  final AuthClient _authClient;
  final UnifiedPushApi _push;
  final FlutterSecureStorage _storage;

  /// What to post once a wake's pull is done ([pulled] is null when it
  /// failed or ran out of time): `MessageNotifications.afterWake`.
  final Future<void> Function(int? pulled)? _notifyWake;
  final Future<void> Function()? _requestPermission;

  /// Set by `main.dart`: pull `/sync/pending` and nudge the WS; returns
  /// how many frames the pull handed over. Not a constructor arg
  /// because the service graph it needs is built after this service.
  Future<int> Function()? onWake;

  final ValueNotifier<PushState> state =
      ValueNotifier<PushState>(PushState.unknown);

  _Endpoint? _endpoint;

  /// The endpoint currently held, or null if we have none.
  String? get endpoint => _endpoint?.url;

  /// The push method in use as of the last [refresh] — see
  /// [kPushChoiceKey] — or null while the user has not chosen one.
  String? choice;

  /// [choice] for people: "Google Play services" or the push app's name.
  String? choiceLabel;

  PushService({
    required AuthClient authClient,
    UnifiedPushApi? unifiedPush,
    FlutterSecureStorage? storage,
    Future<void> Function(int? pulled)? notifyWake,
    Future<void> Function()? requestPermission,
  })  : _authClient = authClient,
        _push = unifiedPush ?? const PluginUnifiedPush(),
        _storage = storage ?? const FlutterSecureStorage(),
        _notifyWake = notifyWake,
        _requestPermission = requestPermission;

  /// Wire the distributor callbacks and, unless [reconcile] is false,
  /// register. Called once per isolate at boot — including the
  /// background isolate a distributor starts (`--unifiedpush-bg`), which
  /// is where a wake lands when the app is not running. That one passes
  /// `reconcile: false`: it has no MainActivity channel to ask about
  /// Google, and the next foreground start registers anyway.
  Future<void> start({bool reconcile = true}) async {
    _endpoint = _decodeEndpoint(await _storage.read(key: keyEndpoint));
    await _push.initialize(
      onNewEndpoint: _onNewEndpoint,
      onUnregistered: _onUnregistered,
      onMessage: _onMessage,
      onRegistrationFailed: _onRegistrationFailed,
    );
    if (reconcile) await refresh();
  }

  /// What the chooser can offer.
  Future<PushOptions> options() async {
    final distributors = await _push.getDistributors();
    return PushOptions(
      google: await _push.googleAvailable(),
      distributors: {
        for (final d in distributors) d: await _push.label(d) ?? d,
      },
    );
  }

  /// The chooser's answer. Asks for the notification grant only now,
  /// after the user said yes to push — never before, where the dialog
  /// would cover the explanation.
  Future<void> choose(String choice) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(kPushChoiceKey);
    await prefs.setString(kPushChoiceKey, choice);
    if (choice == kPushChoiceNone) {
      await _dropRegistration();
      this.choice = choice;
      choiceLabel = null;
      state.value = PushState.off;
      return;
    }
    await _requestNotificationPermission();
    if (previous != null && previous != kPushChoiceNone && previous != choice) {
      // Switching: the old distributor's registration goes; the new
      // endpoint replaces it on the server (AUTH_CONTRACT §5.1).
      try {
        await _push.unregister();
      } catch (_) {/* distributor gone */}
      await _forgetEndpoint();
    }
    await refresh();
  }

  /// Apply the saved choice and (re)register. Safe to call repeatedly —
  /// app start, every login and the Settings row's Retry go through here.
  Future<void> refresh() async {
    // Nothing to register for before login, and no prompt belongs on
    // the intro screen; login calls back in here.
    if (_authClient.currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kPushChoiceKey);
    final resolved = resolvePushChoice(
      saved: saved,
      googleAvailable: await _push.googleAvailable(),
      distributors: await _push.getDistributors(),
    );
    choice = resolved;
    choiceLabel = switch (resolved) {
      null || kPushChoiceNone => null,
      kPushChoiceGoogle => 'Google Play services',
      final package => await _push.label(package) ?? package,
    };
    if (resolved == null) {
      state.value = PushState.choiceNeeded;
      return;
    }
    if (resolved == kPushChoiceNone) {
      state.value = PushState.off;
      return;
    }
    if (resolved != saved) {
      // Picked for the user — the one push app, no Google question.
      // Remember it like a choice, and ask for the grant the chooser
      // would have asked for.
      await prefs.setString(kPushChoiceKey, resolved);
      await _requestNotificationPermission();
    }
    final vapid = await _vapidKey();
    if (vapid == null) {
      state.value = PushState.failed;
      return;
    }
    state.value = PushState.unknown;
    await _push.saveDistributor(resolved);
    await _push.register(vapid: vapid);
    // Nothing else to do until onNewEndpoint fires — except when we
    // already hold an endpoint the server has not confirmed for this
    // user (fresh login on a device that was registered before).
    await _syncEndpoint();
  }

  /// AUTH_CONTRACT §4.6 step 3 — the server drops the endpoint on revoke
  /// too, but we say it explicitly first (the revoke may never reach
  /// it) and stop the distributor from holding a dead registration.
  Future<void> deregister() async {
    await _dropRegistration();
    state.value = PushState.disabled;
  }

  Future<void> _dropRegistration() async {
    if (_authClient.currentAccesskey != null) {
      try {
        await _authClient.registerPushTopic(endpoint: null);
      } catch (_) {
        // Offline logout — the server clears the endpoint on revoke,
        // and a stale one only ever produces a content-free wake.
      }
    }
    try {
      await _push.unregister();
    } catch (_) {/* distributor gone */}
    await _forgetEndpoint();
  }

  void dispose() => state.dispose();

  // ---- distributor callbacks -------------------------------------------

  Future<void> _onNewEndpoint(String url, String? p256dh, String? auth) async {
    if (p256dh == null || auth == null) {
      // The server only sends encrypted Web Push (AUTH_CONTRACT §5), so
      // an endpoint without keys can never be used — posting it would
      // only earn INVALID_PUSH_KEYS.
      debugPrint('UnifiedPush endpoint came without Web Push keys');
      state.value = PushState.failed;
      return;
    }
    _endpoint = (url: url, p256dh: p256dh, auth: auth);
    await _storage.write(
      key: keyEndpoint,
      value: jsonEncode({'endpoint': url, 'p256dh': p256dh, 'auth': auth}),
    );
    await _syncEndpoint();
  }

  Future<void> _onUnregistered() async {
    await _forgetEndpoint();
    state.value = PushState.disabled;
  }

  void _onRegistrationFailed(String reason) {
    debugPrint('UnifiedPush registration failed: $reason');
    state.value = PushState.failed;
  }

  /// How long a wake may spend pulling before the notifications go up.
  @visibleForTesting
  Duration wakeBudget = const Duration(seconds: 5);

  /// A wake is content-free: pull whatever the server queued, get the
  /// WS back up, and let the notifications say what landed.
  Future<void> _onMessage() async {
    // Android freezes a background app a few seconds after the push wakes
    // it, so the pull gets a short budget and the notifications always
    // follow: an unreachable server must not swallow the "you have mail".
    int? pulled;
    try {
      pulled = await onWake?.call().timeout(wakeBudget);
    } catch (e) {
      debugPrint('Push wake pull failed: $e');
    }
    await _notifyWake?.call(pulled);
  }

  // ---- server registration ---------------------------------------------

  /// AUTH_CONTRACT §5.0. Cached, so a start without network still
  /// registers with the last key. A rotated key invalidates the endpoint
  /// the distributor minted for the old one (FCM binds the token to it):
  /// forget it, so the one the re-register yields is posted fresh.
  Future<String?> _vapidKey() async {
    final cached = await _storage.read(key: keyVapid);
    final String fresh;
    try {
      fresh = await _authClient.getVapidKey();
    } catch (e) {
      // Offline, or not signed in yet.
      debugPrint('push/vapid failed: $e');
      return cached;
    }
    if (fresh != cached) {
      if (cached != null) await _forgetEndpoint();
      await _storage.write(key: keyVapid, value: fresh);
    }
    return fresh;
  }

  Future<void> _syncEndpoint() async {
    final ep = _endpoint;
    final userId = _authClient.currentUserId;
    if (ep == null || userId == null) return;
    final marker = '$userId|${ep.url}|${ep.p256dh}|${ep.auth}';
    if (await _storage.read(key: keyRegisteredEndpoint) == marker) {
      state.value = PushState.registered;
      return;
    }
    try {
      await _authClient.registerPushTopic(
          endpoint: ep.url, p256dh: ep.p256dh, auth: ep.auth);
      await _storage.write(key: keyRegisteredEndpoint, value: marker);
      state.value = PushState.registered;
    } catch (e) {
      debugPrint('push/topic registration failed: $e');
      state.value = PushState.failed;
    }
  }

  Future<void> _forgetEndpoint() async {
    _endpoint = null;
    await _storage.delete(key: keyEndpoint);
    await _storage.delete(key: keyRegisteredEndpoint);
  }

  static _Endpoint? _decodeEndpoint(String? raw) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        url: json['endpoint'] as String,
        p256dh: json['p256dh'] as String,
        auth: json['auth'] as String,
      );
    } catch (_) {
      // A pre-Web-Push install stored the bare URL: no keys, so it is
      // useless — the next registration brings a full one.
      return null;
    }
  }

  /// POST_NOTIFICATIONS is API 33+ only; `permission_handler` answers
  /// "granted" everywhere else.
  ///
  /// ponytail: asked once per choice (the chooser, or the silent pick of
  /// the only push app), both foreground moments. A user who denies it
  /// is re-asked only by choosing again in Settings.
  Future<void> _requestNotificationPermission() async {
    try {
      await (_requestPermission ?? Permission.notification.request)();
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
  }
}
