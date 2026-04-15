/// v3 app entry.
///
/// Boots the config store, opens [ChatStore], constructs [AuthClient]
/// + [WsTransport] + [RestTransport] against the config URLs, wraps
/// them in [AuthService] and [ChatService], starts the
/// [SyncScheduler], and picks the root widget based on two flags:
///
/// 1. `v3_consent_accepted` (SharedPreferences) — unset means this is
///    the first launch of the v3 build. Show the destructive-reset
///    consent screen until accepted (V3_ARCHITECTURE "v3 release
///    model").
/// 2. [AuthService.isLoggedIn] — once consent is accepted, show the
///    intro/login flow if not logged in, otherwise the chat list.
///
/// Transport bodies currently throw `UnimplementedError` (step 8).
/// That means the scheduler's initial dispatch tick effectively
/// no-ops (transports report themselves disconnected). Outbound
/// messages accumulate in `outbound_ops` and will drain as soon as
/// step 8 lands.
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
  final bool consentAccepted;

  AppServices({
    required this.store,
    required this.authClient,
    required this.authService,
    required this.chatService,
    required this.scheduler,
    required this.consentAccepted,
  });
}

Future<AppServices> initializeApp() async {
  await configStore.loadConfig();
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
  final apiUrl = Uri.parse(configStore.get<String>('api_url'));
  final wsUrl = Uri.parse(configStore.get<String>('ws_url'));

  final authClient = AuthClient(baseUrl: apiUrl);
  final authService = AuthService(client: authClient);
  await authService.init();

  final wsTransport = WsTransport(endpoint: wsUrl, auth: authClient);
  final restTransport = RestTransport(baseUrl: apiUrl, auth: authClient);

  // --- sync scheduler -------------------------------------------------------
  //
  // UUIDv7 generator needs the 36-bit user_id (SPIKE_B_SYNC §4). If no
  // one is logged in yet we seed a placeholder; once login finishes,
  // sendMessage() uses the value in `AuthClient.currentUserId`. For
  // v3.0 we regenerate the gen on login via `AppServices.rebuildAfterLogin`
  // below, but for the current pre-step-7 scaffold the placeholder is
  // never reached (the UI is blocked on login).
  final userIdBits = _parseUserIdOrZero(authClient.currentUserId);
  final uuidGen = Uuid7Gen(userIdBits: userIdBits);

  final scheduler = SyncScheduler(
    store: store,
    wsTransport: wsTransport,
    restTransport: restTransport,
    backoff: ExponentialJitterBackoff(),
    clock: Clock.system,
  );
  // scheduler.start() reads the transport state (`currentState`) and
  // subscribes to [Transport.acks]. Both transports currently return
  // `TransportState.disconnected` from `currentState` and throw on
  // `acks` access. To keep the scaffold bootable while step 8 is
  // pending we guard .start() behind a try/catch; the scheduler will
  // be re-started once the WS/REST bodies land.
  try {
    await scheduler.start();
  } catch (_) {
    // Transport adapters aren't implemented yet — that's fine. The
    // outbound queue still drains locally; it just doesn't hit the
    // wire. Once step 8 wires up real transports, this try/catch is
    // redundant and gets removed.
  }

  final chatService = ChatService(
    store: store,
    scheduler: scheduler,
    uuidGen: uuidGen,
    clock: Clock.system,
  );

  return AppServices(
    store: store,
    authClient: authClient,
    authService: authService,
    chatService: chatService,
    scheduler: scheduler,
    consentAccepted: consentAccepted,
  );
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
    _authSub = widget.services.authService.authStateChange.listen(
      (loggedIn) => setState(() => _isLogin = loggedIn),
    );
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
    unawaited(widget.services.scheduler.stop());
    unawaited(widget.services.authService.dispose());
    unawaited(widget.services.store.close());
    super.dispose();
  }
}
