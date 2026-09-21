/// v3 app entry.
///
/// Boots the v3 service graph: config → store → auth → transports →
/// scheduler → chat service → inbound receiver. Picks the root widget
/// based on two flags:
///
/// 1. `v3_consent_accepted` (SharedPreferences) — show the destructive-
///    reset consent screen on first v3 launch.
/// 2. [AuthService.isLoggedIn] — show the intro/login flow or the
///    chat list.
library vartalap.main;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/config/sentry_config.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/login/choose_username.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/login/push_onboarding.dart';
import 'package:vartalap/screens/startup/destructive_reset_consent.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/app_services.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

final ConfigStore configStore = ConfigStore();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await initializeApp();

  // The ntfy distributor starts this entrypoint in a background engine
  // to deliver a wake (`unifiedpush` README). Everything the wake needs
  // — pull `/sync/pending`, reconnect the WS, post the local
  // notification — is already wired by initializeApp; there is no UI to
  // run, so we stop short of runApp and let the callback fire.
  if (args.contains('--unifiedpush-bg')) return;

  // Decision 8 (docs/V3_ARCHITECTURE.md): Sentry is only initialized when
  // the user has already opted in from Settings. Off (the default) means
  // nothing is initialized here and no events can ever be sent — the
  // toggle itself starts/stops the SDK at runtime for the already-running
  // app (see lib/config/sentry_config.dart).
  final prefs = await SharedPreferences.getInstance();
  final sentryOptIn = prefs.getBool(kSentryOptInPrefKey) ?? false;
  final sentryDsn = sentryOptIn ? await effectiveSentryDsn() : '';
  if (sentryOptIn && sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) => options.dsn = sentryDsn,
      appRunner: () => runApp(App(services: services)),
    );
  } else {
    runApp(App(services: services));
  }
}

/// Bundle of long-lived services wired up at app boot. Passed to the
/// root widget through an InheritedWidget ([AppServicesProvider]) so
/// screens can pull out just the pieces they need.
class AppServices {
  final ChatStore store;
  final AuthClient authClient;
  final AuthService authService;
  final ChatService chatService;
  final SyncScheduler scheduler;
  final WsTransport wsTransport;
  final RestTransport restTransport;
  final PushService pushService;
  final bool consentAccepted;

  /// False until the user has answered the "install ntfy" prompt once
  /// (decision 6 first-run onboarding). Only ever gates the prompt.
  final bool pushPromptSeen;

  /// Inbound WS_PUSH fanout applier. Null pre-login: it's constructed
  /// by [rebuildInboundReceiverForUser] on [AuthService.authStateChange]
  /// because it needs the authenticated `user_id` for the §5.4 "don't
  /// bump unread on own message" rule. Pre-login push frames would
  /// have no session to target anyway (WS can't connect without a
  /// token), so we drop the window.
  InboundReceiver? inboundReceiver;

  AppServices({
    required this.store,
    required this.authClient,
    required this.authService,
    required this.chatService,
    required this.scheduler,
    required this.wsTransport,
    required this.restTransport,
    required this.pushService,
    required this.consentAccepted,
    required this.pushPromptSeen,
    this.inboundReceiver,
  });

  /// Pull whatever the server has queued for us, feed each frame into
  /// the same fanout stream as live WS_PUSHes, wait for the inbound
  /// receiver to apply them, and then release the WS post-connect
  /// buffer (live frames captured during the window flush in arrival
  /// order). Safe to call many times — `InboundReceiver` dedups by
  /// op_id; [WsTransport.endSyncBuffer] is idempotent.
  Future<void> pullPendingSync() async {
    try {
      final envelopes = await restTransport.pullPendingSync();
      for (final env in envelopes) {
        wsTransport.injectPush(env);
      }
      await inboundReceiver?.drainPending();
    } finally {
      wsTransport.endSyncBuffer();
    }
  }

  /// Stop any previous receiver and construct + start a fresh one
  /// bound to [userIdHex]. Called on every login so the new session's
  /// user_id flows into [InboundReceiver.localUserId] before any push
  /// frame can apply.
  Future<void> rebuildInboundReceiverForUser(String userIdHex) async {
    final prev = inboundReceiver;
    inboundReceiver = null;
    chatService.bindTypingSource(null);
    if (prev != null) {
      await prev.stop();
    }
    final next = InboundReceiver(
      store: store,
      pushes: wsTransport.pushes,
      localUserId: userIdHex,
    );
    await next.start();
    inboundReceiver = next;
    chatService.bindTypingSource(next.typingEvents);
  }
}

Future<AppServices> initializeApp() async {
  await configStore.init();

  // --- config / secure-storage bootstrapping --------------------------------
  final prefs = await SharedPreferences.getInstance();
  final consentAccepted = prefs.getBool(kV3ConsentAcceptedKey) ?? false;
  VartalapTheme.themeMode = switch (prefs.getString('theme_mode')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  // --- local store ----------------------------------------------------------
  final docsDir = await getApplicationDocumentsDirectory();
  final dbPath = '${docsDir.path}/vartalap_v3.db';
  final store = await ChatStore.open(path: dbPath);

  // --- transport + auth -----------------------------------------------------
  final apiUrl = Uri.parse(ConfigStore.apiUrl);
  final wsUrl = Uri.parse(ConfigStore.wsUrl);

  final authClient = AuthClient(baseUrl: apiUrl);
  final authService = AuthService(client: authClient);
  await authService.init();

  final wsTransport = WsTransport(endpoint: wsUrl, auth: authClient);
  // `connectivity_plus` is Flutter-only, so the pure-Dart transport
  // package takes a plain `Stream<bool>` instead of depending on it
  // directly — mapped here from "no connectivity path at all" to the
  // scheduler-visible connected/disconnected state (§4.7 plumbing).
  final restTransport = RestTransport(
    baseUrl: apiUrl,
    auth: authClient,
    connectivityStream: Connectivity()
        .onConnectivityChanged
        .map((results) => !results.contains(ConnectivityResult.none)),
  );

  // --- sync scheduler -------------------------------------------------------
  //
  // UUIDv7 generator needs the 36-bit user_id (SPIKE_B_SYNC §4). If no
  // one is logged in yet we seed zero; once login finishes,
  // reseedForUser() in the authStateChange listener swaps in the real
  // user_id bits.
  final userIdBits = _parseUserIdOrZero(authClient.currentUserId);
  final uuidGen = Uuid7Gen(userIdBits: userIdBits);

  final scheduler = SyncScheduler(
    store: store,
    wsTransport: wsTransport,
    restTransport: restTransport,
    backoff: ExponentialJitterBackoff(),
    clock: Clock.system,
  );
  await scheduler.start();
  // Start the WS transport. If no accesskey yet (pre-login), it stays
  // disconnected and auto-connects once auth lands. Reconnect with
  // backoff on disconnect.
  await wsTransport.start();

  final chatService = ChatService(
    store: store,
    scheduler: scheduler,
    authClient: authClient,
    wsTransport: wsTransport,
    uuidGen: uuidGen,
    clock: Clock.system,
  );

  final pushService = PushService(authClient: authClient);

  final services = AppServices(
    store: store,
    authClient: authClient,
    authService: authService,
    chatService: chatService,
    scheduler: scheduler,
    wsTransport: wsTransport,
    restTransport: restTransport,
    pushService: pushService,
    consentAccepted: consentAccepted,
    pushPromptSeen: prefs.getBool(kPushPromptSeenKey) ?? false,
  );

  // SYNC_PROTOCOL §12.3 — the wake says nothing, so the client owns
  // the follow-up: WS back up, then drain whatever was queued.
  pushService.onWake = () async {
    await wsTransport.start();
    await services.pullPendingSync();
  };
  // AUTH_CONTRACT §5.1 — deregister while the accesskey still works.
  authService.onBeforeLogout = pushService.deregister;
  try {
    await pushService.start();
  } catch (e) {
    // No distributor plugin (desktop, tests) — push is simply off.
    debugPrint('Push init failed: $e');
  }

  // If we already have a signed-in session (restoreSession populated
  // currentUserId), stand up the inbound receiver now so push frames
  // apply from first WS connection. Otherwise it lands on authStateChange.
  final restoredUserId = authClient.currentUserId;
  if (restoredUserId != null) {
    await services.rebuildInboundReceiverForUser(restoredUserId);
    // Best-effort initial pull — picks up anything the server queued
    // between the last connection and now (e.g. seed-peer DM created
    // at OTP-verify on a fresh install). Server never auto-pushes.
    unawaited(services.pullPendingSync());
  }

  return services;
}

/// The 9-hex user_id lives in `AuthClient.currentUserId` after
/// restoreSession. Before first login, we pass 0; the scheduler won't
/// dispatch anyway because the pre-login UI never enqueues ops.
int _parseUserIdOrZero(String? userId) {
  if (userId == null) return 0;
  try {
    return Uuid7Gen.parseUserIdHex(userId);
  } catch (_) {
    // Corrupt stored user_id — log and proceed with 0. On the next
    // OTP verify the fresh user_id replaces this and the scheduler is
    // rebuilt on auth state change (see App._onAuthChange).
    return 0;
  }
}

/// Root widget. Subscribes to [AuthService.authStateChange] and swaps
/// the home widget without tearing down the service graph underneath.
class App extends StatefulWidget {
  final AppServices services;
  const App({super.key, required this.services});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late bool _isLogin;
  late bool _consentAccepted;
  late bool _pushPromptSeen;
  /// AUTH_CONTRACT §2.4 — null means the mandatory "choose username"
  /// step is still outstanding, for a fresh signup AND for a restored
  /// session whose stored profile has no handle.
  String? _username;
  late StreamSubscription<bool> _authSub;
  late StreamSubscription<String?> _usernameSub;
  StreamSubscription<TransportState>? _wsStateSub;
  StreamSubscription<void>? _authFailureSub;
  StreamSubscription<void>? _reauthRequiredSub;
  // Held so the auth-state listener can pop the navigator back to the
  // root before [_home] swaps in the login flow. Without this, screens
  // pushed on top of the chat list (Profile, Settings, …) survive the
  // logout and the user has to back out of them manually.
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _consentAccepted = widget.services.consentAccepted;
    _pushPromptSeen = widget.services.pushPromptSeen;
    // The wake is content-free, so a tap can only mean "show me the
    // app" — the chat list is the root route.
    widget.services.pushService.onNotificationTap =
        () => _navKey.currentState?.popUntil((route) => route.isFirst);
    _isLogin = widget.services.authService.isLoggedIn;
    _username = widget.services.authService.username;
    _usernameSub = widget.services.authService.usernameChange.listen((u) {
      setState(() => _username = u);
      // AUTH_CONTRACT §2.4: push/topic is behind the USERNAME_REQUIRED
      // gate like every other authenticated route, so the topic can
      // only be registered once the handle lands.
      if (u != null) unawaited(widget.services.pushService.refresh());
    });
    _authSub = widget.services.authService.authStateChange.listen((loggedIn) {
      if (!loggedIn) {
        // Tear down any pushed routes (Profile, Settings, Chat, …) so
        // the login screen replaces the *whole* surface, not just the
        // root underneath an existing stack.
        _navKey.currentState?.popUntil((route) => route.isFirst);
      }
      if (loggedIn) {
        // Reseed the op_id generator with the just-authenticated
        // user's user_id. Before this point main.dart constructed the
        // gen with zero bits; the first sendMessage after login would
        // otherwise embed those zeros and be rejected server-side as
        // prefix_mismatch (SYNC_PROTOCOL.md §3).
        final userId = widget.services.authService.currentUserId;
        if (userId != null) {
          widget.services.chatService.reseedForUser(userId);
          // Rebuild the inbound receiver so localUserId reflects the
          // new session, then pull whatever the server has queued.
          // Order matters: receiver must be live before frames arrive.
          unawaited(
            widget.services
                .rebuildInboundReceiverForUser(userId)
                .then((_) => widget.services.pullPendingSync()),
          );
          // Kick the WS transport so it connects now that we have an
          // accesskey. If already connected this is a no-op.
          unawaited(widget.services.wsTransport.start());
          // AUTH_CONTRACT §5.1: the topic is stored per (user, device),
          // so a new session must re-post the endpoint it holds — once
          // the §2.4 username gate is open (the usernameChange listener
          // above covers the signup case).
          if (widget.services.authService.username != null) {
            unawaited(widget.services.pushService.refresh());
          }
        }
      }
      setState(() => _isLogin = loggedIn);
    });
    // Re-pull on every WS reconnect so frames queued while offline
    // arrive without waiting for an app restart. Server never pushes
    // on connect; the client owns the trigger.
    _wsStateSub = widget.services.wsTransport.state.listen((s) {
      if (s == TransportState.connected) {
        unawaited(widget.services.pullPendingSync());
      }
    });

    // Refresh accesskey on AUTH_FAILURE / WS_REAUTH_REQUIRED. Both
    // streams just say "something failed auth" — AuthService coalesces
    // concurrent attempts so two near-simultaneous signals only hit
    // the server once. On success, unpause the scheduler; on failure
    // AuthService logs out, which fires authStateChange=false above.
    _authFailureSub = widget.services.scheduler.authFailures.listen((_) {
      _refreshAuthOnDemand();
    });
    _reauthRequiredSub =
        widget.services.wsTransport.reauthRequired.listen((_) {
      _refreshAuthOnDemand();
    });
  }

  Future<void> _refreshAuthOnDemand() async {
    if (!widget.services.authService.isLoggedIn) return;
    final ok = await widget.services.authService.refreshSession();
    if (ok && mounted) {
      widget.services.scheduler.resumeAfterAuthRefresh();
    }
  }

  void _onConsentAccepted() {
    setState(() => _consentAccepted = true);
  }

  Widget _home() {
    if (!_consentAccepted) {
      return DestructiveResetConsentScreen(onAccepted: _onConsentAccepted);
    }
    if (!_isLogin) {
      return IntroductionScreen(authService: widget.services.authService);
    }
    if (_username == null) {
      // §2.4: not a route the user can pop out of — every other
      // authenticated route is 403 USERNAME_REQUIRED until this lands.
      return ChooseUsernameScreen(
        authService: widget.services.authService,
      );
    }
    final chats = ChatsScreen(
      chatService: widget.services.chatService,
      authService: widget.services.authService,
      config: configStore,
    );
    if (_pushPromptSeen) return chats;
    // Decision 6 first-run onboarding: the one screen that asks for the
    // ntfy app, shown after the username step and only while the
    // distributor is actually missing.
    return ValueListenableBuilder<PushState>(
      valueListenable: widget.services.pushService.state,
      builder: (context, pushState, child) =>
          pushState == PushState.distributorMissing
              ? PushOnboardingScreen(onDone: _onPushPromptDone)
              : child!,
      child: chats,
    );
  }

  Future<void> _onPushPromptDone() async {
    setState(() => _pushPromptSeen = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPushPromptSeenKey, true);
  }

  @override
  Widget build(BuildContext context) {
    return AppServicesProvider(
        services: widget.services,
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: VartalapTheme.themeModeNotifier,
          builder: (context, themeMode, _) => MaterialApp(
            title: configStore.packageInfo.appName,
            debugShowCheckedModeBanner: kDebugMode,
            themeMode: themeMode,
            theme: VartalapTheme.light.data,
            darkTheme: VartalapTheme.dark.data,
            navigatorKey: _navKey,
            home: _home(),
            onGenerateRoute: (settings) {
            // No named routes in v3.0 — screens push each other
            // through direct constructor calls so dependencies are
            // explicit. Intent deep-links and push-notification
            // deep-links re-land in step 11 on their own route table.
            if (settings.name == '/chats') {
              return MaterialPageRoute(
                builder: (_) => ChatsScreen(
                  chatService: widget.services.chatService,
                  authService: widget.services.authService,
                  config: configStore,
                ),
              );
            }
            if (settings.name?.startsWith('/chat/') ?? false) {
              final channelId = settings.name!.substring('/chat/'.length);
              return MaterialPageRoute(
                builder: (_) => ChatScreen(
                  channelId: channelId,
                  channelName: channelId,
                  // Deep-link route doesn't know the kind yet — step 11
                  // will resolve it from the store before constructing
                  // the route. Defaulting to 'one_to_one' (SYNC_PROTOCOL
                  // §11.3) is wrong for groups (they'd lose the Leave
                  // option) but matches the v3.0 deep-link surface,
                  // which only fires for DMs.
                  channelKind: 'one_to_one',
                  chatService: widget.services.chatService,
                  authService: widget.services.authService,
                ),
              );
            }
            return null;
          },
          ),
        ),
      );
  }

  @override
  void dispose() {
    _authSub.cancel();
    _usernameSub.cancel();
    _wsStateSub?.cancel();
    _authFailureSub?.cancel();
    _reauthRequiredSub?.cancel();
    widget.services.pushService.dispose();
    unawaited(widget.services.inboundReceiver?.stop());
    unawaited(widget.services.scheduler.stop());
    unawaited(widget.services.authService.dispose());
    unawaited(widget.services.store.close());
    super.dispose();
  }
}
