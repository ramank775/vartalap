/// Push wake path — UnifiedPush with the ntfy Android app pinned as the
/// only distributor (V3_ARCHITECTURE.md decision 6, decisions 3/35/57).
///
/// The wake is content-free (SYNC_PROTOCOL.md §12.1: title "Vartalap",
/// body "New activity"), so everything this service can do on a message
/// is: pull `/sync/pending`, nudge the WS back up, and — if the app is
/// not on screen — post a local "New activity" notification.
///
/// Endpoint lifecycle:
///   register with ntfy → `onNewEndpoint(url)` → `POST /v3.0/push/topic`
///   (AUTH_CONTRACT §5.1) → remember what we posted → logout posts null
///   and unregisters.
library vartalap.services.push_service;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// The one distributor v3.0 supports. A user-facing distributor picker
/// is v3.1 (decision 6).
const String kNtfyDistributorPackage = 'io.heckel.ntfy';

/// Where "Install" sends the user. F-Droid first — it is the FOSS
/// store the rest of the app assumes; ntfy.sh/docs carries the direct
/// APK and the Play link for anyone without F-Droid.
const String kNtfyInstallUrl = 'https://f-droid.org/packages/io.heckel.ntfy/';

const int _wakeNotificationId = 1;

enum PushState {
  /// Before [PushService.start] has looked at the system.
  unknown,

  /// Endpoint held AND accepted by the server for this user.
  registered,

  /// The ntfy app is not installed — nothing can be registered.
  distributorMissing,

  /// Registered with nobody: logged out, or the distributor dropped us.
  disabled,

  /// We have (or can get) an endpoint but the server said no.
  failed,
}

/// The slice of the `unifiedpush` plugin this service uses. A seam, not
/// an abstraction: it exists so the state machine can be unit-tested
/// without an Android distributor.
abstract class UnifiedPushApi {
  Future<void> initialize({
    required void Function(String endpointUrl) onNewEndpoint,
    required void Function() onUnregistered,
    required void Function() onMessage,
    required void Function(String reason) onRegistrationFailed,
  });
  Future<List<String>> getDistributors();
  Future<void> saveDistributor(String distributor);
  Future<void> register();
  Future<void> unregister();
}

/// The real plugin.
class PluginUnifiedPush implements UnifiedPushApi {
  const PluginUnifiedPush();

  @override
  Future<void> initialize({
    required void Function(String endpointUrl) onNewEndpoint,
    required void Function() onUnregistered,
    required void Function() onMessage,
    required void Function(String reason) onRegistrationFailed,
  }) async {
    await UnifiedPush.initialize(
      onNewEndpoint: (endpoint, _) => onNewEndpoint(endpoint.url),
      onRegistrationFailed: (reason, _) => onRegistrationFailed(reason.name),
      onUnregistered: (_) => onUnregistered(),
      onMessage: (_, __) => onMessage(),
    );
  }

  @override
  Future<List<String>> getDistributors() => UnifiedPush.getDistributors();

  @override
  Future<void> saveDistributor(String distributor) =>
      UnifiedPush.saveDistributor(distributor);

  @override
  Future<void> register() => UnifiedPush.register();

  @override
  Future<void> unregister() => UnifiedPush.unregister();
}

class PushService {
  /// The endpoint the distributor handed us, whatever the server knows.
  static const String keyEndpoint = 'v3.push.endpoint';

  /// `<user_id>|<endpoint>` — the pair we last got a 200 for. There is
  /// no server readback route (notification-ms exposes register and an
  /// internal delete only), so this is the client's record of "what the
  /// server has". A mismatch on login or app start means re-post.
  static const String keyRegisteredEndpoint = 'v3.push.registeredEndpoint';

  final AuthClient _authClient;
  final UnifiedPushApi _push;
  final FlutterSecureStorage _storage;
  final Future<void> Function()? _notifyOverride;
  final Future<void> Function()? _requestPermission;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// Set by `main.dart`: pull `/sync/pending` and nudge the WS. Not a
  /// constructor arg because the service graph it needs is built after
  /// this service.
  Future<void> Function()? onWake;

  /// Set by `main.dart`: what tapping the local notification does. The
  /// wake carries no content, so there is nothing to deep-link to — the
  /// best we can do is surface the chat list.
  VoidCallback? onNotificationTap;

  final ValueNotifier<PushState> state =
      ValueNotifier<PushState>(PushState.unknown);

  String? _endpoint;

  /// The endpoint currently held, or null if we have none.
  String? get endpoint => _endpoint;

  PushService({
    required AuthClient authClient,
    UnifiedPushApi? unifiedPush,
    FlutterSecureStorage? storage,
    Future<void> Function()? notifyWake,
    Future<void> Function()? requestPermission,
  })  : _authClient = authClient,
        _push = unifiedPush ?? const PluginUnifiedPush(),
        _storage = storage ?? const FlutterSecureStorage(),
        _notifyOverride = notifyWake,
        _requestPermission = requestPermission;

  /// Wire the distributor callbacks and reconcile. Called once per
  /// isolate at boot — including the background isolate the ntfy app
  /// starts (`--unifiedpush-bg`), which is where a wake lands when the
  /// app is not running.
  Future<void> start() async {
    _endpoint = await _storage.read(key: keyEndpoint);
    await _push.initialize(
      onNewEndpoint: _onNewEndpoint,
      onUnregistered: _onUnregistered,
      onMessage: _onMessage,
      onRegistrationFailed: _onRegistrationFailed,
    );
    if (_notifyOverride == null) {
      // Registers the tap handler; harmless if it is never shown.
      await _initNotifications();
    }
    await refresh();
  }

  /// Pin ntfy and (re)register. Safe to call repeatedly — the settings
  /// row's "re-register" action and every login go through here.
  Future<void> refresh() async {
    final distributors = await _push.getDistributors();
    if (!distributors.contains(kNtfyDistributorPackage)) {
      state.value = PushState.distributorMissing;
      return;
    }
    await _push.saveDistributor(kNtfyDistributorPackage);
    await _push.register();
    // Nothing else to do until onNewEndpoint fires — except when we
    // already hold an endpoint the server has not confirmed for this
    // user (fresh login on a device that was registered before).
    await _syncEndpoint();
  }

  /// AUTH_CONTRACT §4.6 step 3 — the server drops the topic on revoke
  /// too, but we say it explicitly first (the revoke may never reach
  /// it) and stop the distributor from holding a dead registration.
  Future<void> deregister() async {
    if (_authClient.currentAccesskey != null) {
      try {
        await _authClient.registerPushTopic(topicUrl: null);
      } catch (_) {
        // Offline logout — the server clears the topic on revoke, and
        // a stale topic only ever produces a content-free wake.
      }
    }
    try {
      await _push.unregister();
    } catch (_) {/* distributor gone */}
    _endpoint = null;
    await _storage.delete(key: keyEndpoint);
    await _storage.delete(key: keyRegisteredEndpoint);
    state.value = PushState.disabled;
  }

  void dispose() => state.dispose();

  // ---- distributor callbacks -------------------------------------------

  Future<void> _onNewEndpoint(String url) async {
    _endpoint = url;
    await _storage.write(key: keyEndpoint, value: url);
    await _syncEndpoint();
    await _requestNotificationPermission();
  }

  Future<void> _onUnregistered() async {
    _endpoint = null;
    await _storage.delete(key: keyEndpoint);
    await _storage.delete(key: keyRegisteredEndpoint);
    state.value = PushState.disabled;
  }

  void _onRegistrationFailed(String reason) {
    debugPrint('UnifiedPush registration failed: $reason');
    state.value = PushState.failed;
  }

  /// A wake is content-free: pull whatever the server queued, get the
  /// WS back up, and tell the user something happened if they are not
  /// already looking at the app.
  Future<void> _onMessage() async {
    try {
      await onWake?.call();
    } catch (e) {
      debugPrint('Push wake pull failed: $e');
    }
    await (_notifyOverride ?? _showWakeNotification)();
  }

  // ---- server registration ---------------------------------------------

  Future<void> _syncEndpoint() async {
    final url = _endpoint;
    final userId = _authClient.currentUserId;
    if (url == null || userId == null) return;
    final marker = '$userId|$url';
    if (await _storage.read(key: keyRegisteredEndpoint) == marker) {
      state.value = PushState.registered;
      return;
    }
    try {
      await _authClient.registerPushTopic(topicUrl: url);
      await _storage.write(key: keyRegisteredEndpoint, value: marker);
      state.value = PushState.registered;
    } catch (e) {
      debugPrint('push/topic registration failed: $e');
      state.value = PushState.failed;
    }
  }

  // ---- local notification ----------------------------------------------

  Future<void> _initNotifications() async {
    try {
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (_) => onNotificationTap?.call(),
      );
    } catch (e) {
      debugPrint('Local notifications init failed: $e');
    }
  }

  Future<void> _showWakeNotification() async {
    // On screen → the chat list already repainted off the pull.
    // `lifecycleState` is null in the background isolate the ntfy app
    // starts, which is exactly when we do want the notification.
    if (SchedulerBinding.instance.lifecycleState ==
        AppLifecycleState.resumed) {
      return;
    }
    await _initNotifications();
    try {
      await _notifications.show(
        id: _wakeNotificationId,
        // SYNC_PROTOCOL §12.1 — the wake carries no content, so neither
        // can this. Per-channel mute cannot be honoured for the same
        // reason: we do not know which channel woke us until the pull
        // has already landed, and the pull is not per-channel.
        title: 'Vartalap',
        body: 'New activity',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'wake',
            'New activity',
            channelDescription:
                'Tells you something arrived while Vartalap was closed.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Wake notification failed: $e');
    }
  }

  /// POST_NOTIFICATIONS is API 33+ only; `permission_handler` answers
  /// "granted" everywhere else.
  ///
  /// ponytail: fired when an endpoint lands, which is a foreground
  /// moment in practice (app start / just-finished login). In the
  /// background isolate there is no activity to show the dialog on and
  /// this silently returns denied — the onboarding screen and the
  /// Settings row are the paths that re-ask.
  Future<void> _requestNotificationPermission() async {
    try {
      await (_requestPermission ?? Permission.notification.request)();
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
  }
}
