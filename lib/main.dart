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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/startup/destructive_reset_consent.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/crashlystics.dart';
import 'package:vartalap/services/performance_metric.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/app_services.dart';
import 'package:vartalap/widgets/Inherited/config_provider.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

final ConfigStore configStore = ConfigStore();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await initializeApp();
  FlutterError.onError = Crashlytics.recordFlutterError;
  PlatformDispatcher.instance.onError = (error, stack) {
    Crashlytics.recordError(error, stack);
    return true;
  };
  runApp(App(services: services));
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
  final bool consentAccepted;

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
    required this.consentAccepted,
    this.inboundReceiver,
  });

  /// Stop any previous receiver and construct + start a fresh one
  /// bound to [userIdHex]. Called on every login so the new session's
  /// user_id flows into [InboundReceiver.localUserId] before any push
  /// frame can apply.
  Future<void> rebuildInboundReceiverForUser(String userIdHex) async {
    final prev = inboundReceiver;
    inboundReceiver = null;
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
  }
}

Future<AppServices> initializeApp() async {
  await configStore.init();
  Crashlytics.init();
  PerformanceMetric.init();

  // --- config / secure-storage bootstrapping --------------------------------
  final prefs = await SharedPreferences.getInstance();
  final consentAccepted = prefs.getBool(kV3ConsentAcceptedKey) ?? false;

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
  final restTransport = RestTransport(baseUrl: apiUrl, auth: authClient);

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
    uuidGen: uuidGen,
    clock: Clock.system,
  );

  final services = AppServices(
    store: store,
    authClient: authClient,
    authService: authService,
    chatService: chatService,
    scheduler: scheduler,
    wsTransport: wsTransport,
    consentAccepted: consentAccepted,
  );

  // If we already have a signed-in session (restoreSession populated
  // currentUserId), stand up the inbound receiver now so push frames
  // apply from first WS connection. Otherwise it lands on authStateChange.
  final restoredUserId = authClient.currentUserId;
  if (restoredUserId != null) {
    await services.rebuildInboundReceiverForUser(restoredUserId);
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
  late StreamSubscription<bool> _authSub;

  @override
  void initState() {
    super.initState();
    _consentAccepted = widget.services.consentAccepted;
    _isLogin = widget.services.authService.isLoggedIn;
    _authSub = widget.services.authService.authStateChange.listen((loggedIn) {
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
          // new session. Fire-and-forget: setState below flips the UI
          // into the chat list; the receiver coming up a few ticks
          // later just means the first push frame arrives against the
          // already-visible shell.
          unawaited(
            widget.services.rebuildInboundReceiverForUser(userId),
          );
          // Kick the WS transport so it connects now that we have an
          // accesskey. If already connected this is a no-op.
          unawaited(widget.services.wsTransport.start());
        }
      }
      setState(() => _isLogin = loggedIn);
    });
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
    return ChatsScreen(
      chatService: widget.services.chatService,
      authService: widget.services.authService,
      config: configStore,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConfigProvider(
      configStore: configStore,
      child: AppServicesProvider(
        services: widget.services,
        child: MaterialApp(
          title: configStore.packageInfo.appName,
          debugShowCheckedModeBanner: kDebugMode,
          themeMode: VartalapTheme.themeMode,
          theme: VartalapTheme.lightTheme.appTheme,
          darkTheme: VartalapTheme.darkTheme.appTheme,
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
    unawaited(widget.services.inboundReceiver?.stop());
    unawaited(widget.services.scheduler.stop());
    unawaited(widget.services.authService.dispose());
    unawaited(widget.services.store.close());
    super.dispose();
  }
}
