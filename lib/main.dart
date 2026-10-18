/// v3 app entry.
///
/// Boots the v3 service graph: config → store → auth → transports →
/// scheduler → chat service → inbound receiver. Picks the root widget
/// based on two flags:
///
/// 1. `v3_consent_accepted` (SharedPreferences) — show the destructive-
///    relaunch screen on first v3 launch over leftover v2 data.
/// 2. [AuthService.isLoggedIn] — show the intro/login flow or the
///    chat list.
library vartalap.main;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/config/sentry_config.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/contact_info/contact_info.dart';
import 'package:vartalap/utils/username_link.dart';
import 'package:vartalap/screens/login/choose_username.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/login/push_onboarding.dart';
import 'package:vartalap/screens/startup/destructive_reset_consent.dart';
import 'package:vartalap/services/account_db.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/notifications.dart';
import 'package:vartalap/services/v2_archive.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/app_services.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

final ConfigStore configStore = ConfigStore();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The system photo picker (redacts GPS, no storage permission) for
  // photos *and* videos; the plugin's default is a generic file browser.
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
  // A distributor starts this entrypoint in a background engine to
  // deliver a wake (`unifiedpush` README). Everything the wake needs —
  // pull `/sync/pending`, reconnect the WS, post the notifications — is
  // wired by initializeApp; there is no UI to run, so we stop short
  // of runApp and let the callback fire.
  final background = args.contains('--unifiedpush-bg');
  final services = await initializeApp(background: background);
  if (background) return;

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
  final AuthClient authClient;
  final AuthService authService;
  final WsTransport wsTransport;
  final RestTransport restTransport;
  final PushService pushService;
  final MessageNotifications notifications;
  final bool consentAccepted;

  /// False until the user has answered the push chooser once (decision
  /// 6 first-run onboarding). Only ever gates the prompt.
  final bool pushPromptSeen;

  /// Where each account's database lives ([accountDbPath]).
  final String dbDir;

  /// [ChatStore.open]; tests hand back in-memory stores.
  final Future<ChatStore> Function(String path) openDb;

  // The signed-in account's half of the graph: its own database
  // (AUTH_CONTRACT §8.4), the scheduler draining its outbound queue, the
  // service over both, and [inboundReceiver]. Built by [openAccount] at
  // login (or boot, for a restored session), torn down by [closeAccount]
  // at logout. Null while no one is signed in.
  String? _userId;
  ChatStore? store;
  SyncScheduler? scheduler;

  /// Unset until the first [openAccount]. [closeAccount] leaves the last
  /// one in place, over its closed store, so a widget built while the
  /// logout is still landing reads nothing rather than throwing.
  late ChatService chatService;

  /// Every account's scheduler AUTH_FAILUREs, in one stream that outlives
  /// them (see [SyncScheduler.authFailures]).
  final _authFailures = StreamController<void>.broadcast();
  Stream<void> get authFailures => _authFailures.stream;

  /// Inbound WS_PUSH fanout applier. Null pre-login: it's constructed
  /// by [rebuildInboundReceiverForUser] from [openAccount]
  /// because it needs the authenticated `user_id` for the §5.4 "don't
  /// bump unread on own message" rule. Pre-login push frames would
  /// have no session to target anyway (WS can't connect without a
  /// token), so we drop the window.
  InboundReceiver? inboundReceiver;

  AppServices({
    required this.authClient,
    required this.authService,
    required this.wsTransport,
    required this.restTransport,
    required this.pushService,
    required this.notifications,
    required this.consentAccepted,
    required this.pushPromptSeen,
    required this.dbDir,
    this.openDb = _openDb,
  });

  static Future<ChatStore> _openDb(String path) => ChatStore.open(path: path);

  /// Open [userId]'s own database and start what reads and writes it.
  /// [AuthService.onLogin] at login, `initializeApp` for a restored session.
  Future<void> openAccount(String userId, {bool adoptGroups = true}) async {
    await closeAccount();
    final store = await openDb(accountDbPath(dbDir, userId));
    await store.initSyncPointer(freshSyncPointer(authClient.signedInAt));
    // Trim 4: derived DM ops name their peer on the wire, which is
    // relative to the signed-in user.
    final scheduler = SyncScheduler(
      store: store,
      wsTransport: wsTransport,
      restTransport: restTransport,
      backoff: ExponentialJitterBackoff(),
      clock: Clock.system,
    )..selfUserId = userId;
    scheduler.authFailures.listen(_authFailures.add);
    await scheduler.start();
    _userId = userId;
    this.store = store;
    this.scheduler = scheduler;
    // The op_id generator carries the user_id bits (SPIKE_B_SYNC §4).
    chatService = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: authClient,
      wsTransport: wsTransport,
      uuidGen: Uuid7Gen(userIdBits: _parseUserIdOrZero(userId)),
      clock: Clock.system,
    )..onRead = notifications.cancelChat;
    await rebuildInboundReceiverForUser(userId, adoptGroups: adoptGroups);
  }

  /// [AuthService.onLogout]: stop everything that writes to the account's
  /// database (the socket's frames, inbound applies, the scheduler,
  /// delivery receipts), then close it. The file stays for the next
  /// sign-in unless [erase] (account deleted).
  Future<void> closeAccount({bool erase = false}) async {
    final store = this.store;
    if (store == null) return;
    final userId = _userId!;
    this.store = null;
    _userId = null;
    // Frames still arriving on this session's socket are this account's;
    // the next login starts it again.
    await wsTransport.stop();
    final receiver = inboundReceiver;
    inboundReceiver = null;
    chatService.bindTypingSource(null);
    chatService.bindDeliverySource(null);
    await receiver?.stop();
    await scheduler?.stop();
    scheduler = null;
    await store.close();
    if (erase) await deleteAccountDb(dbDir, userId);
  }

  /// Pull whatever the server holds for us ([pullPendingPages]).
  /// Returns how many frames the server handed over.
  Future<int> pullPendingSync() =>
      pullPendingPages(restTransport, wsTransport, inboundReceiver);

  /// Stop any previous receiver and construct + start a fresh one
  /// bound to [userIdHex]. Called on every login so the new session's
  /// user_id flows into [InboundReceiver.localUserId] before any push
  /// frame can apply.
  Future<void> rebuildInboundReceiverForUser(
    String userIdHex, {
    bool adoptGroups = true,
  }) async {
    final prev = inboundReceiver;
    inboundReceiver = null;
    chatService.bindTypingSource(null);
    chatService.bindDeliverySource(null);
    notifications.bindSource(null);
    if (prev != null) {
      await prev.stop();
    }
    final next = InboundReceiver(
      store: store!,
      pushes: wsTransport.pushes,
      localUserId: userIdHex,
      resolveProfile: (userId) => _resolveContactProfile(authClient, userId),
      resolveGroup: (channelId) async {
        final json = await authClient.getChannel(channelId);
        return json == null ? null : groupRosterFromJson(json);
      },
    );
    await next.start();
    inboundReceiver = next;
    // A push wake has seconds to deliver; the foreground app catches up.
    if (adoptGroups) unawaited(_adoptServerGroups(authClient, next));
    chatService.bindTypingSource(next.typingEvents);
    chatService.bindDeliverySource(next.peerMessagesStored);
    // Every inbound message, WS or pull, lands here: off screen it
    // notifies (the WS stays up while the app is in the background).
    notifications.bindSource(next.peerMessagesStored);
  }
}

/// Where a fresh account database's pull pointer starts (an existing
/// one keeps its own, so a re-login still gets what came while signed
/// out): the sign-in, in server time — the otp/verify `Date`, less a
/// minute for its one-second precision — so a new install does not
/// replay the 30 days the server keeps. No `Date`: 0, all of it.
/// Revisit with end-to-end encryption.
int freshSyncPointer(DateTime? signedInAt) =>
    signedInAt == null ? 0 : signedInAt.millisecondsSinceEpoch - 60000;

/// SYNC_PROTOCOL §10.6 pull loop. Pull a page of what the server holds
/// for us from the account's pointer on ([InboundReceiver.syncPointer],
/// inclusive), feed each frame into the same fanout stream as live
/// WS_PUSHes, wait for [receiver] to apply them, and if it handled them
/// all move the pointer to the page's newest stamp and pull again while
/// the server says there is `more`; then release the WS post-connect
/// buffer (live frames captured during the window flush in arrival
/// order). Safe to call many times — [InboundReceiver] dedups by op_id;
/// [WsTransport.endSyncBuffer] is idempotent. Returns how many frames
/// the server handed over.
Future<int> pullPendingPages(
  RestTransport rest,
  WsTransport ws,
  InboundReceiver? receiver,
) async {
  var pulled = 0;
  try {
    if (receiver == null) return 0;
    // Live frames stop moving the pointer while this runs: until it
    // has every page, they may be newer than what it has yet to bring.
    final token = receiver.holdSyncPointer();
    while (true) {
      final since = receiver.syncPointer;
      final page = await rest.pullPendingSync(since: since);
      if (page == null) break;
      pulled += page.envelopes.length;
      final ids = {for (final env in page.envelopes) env.opId}..remove('');
      final handled = <String>{};
      final sub = receiver.handled.listen((id) {
        if (ids.contains(id)) handled.add(id);
      });
      for (final env in page.envelopes) {
        ws.injectPush(env);
      }
      await receiver.drainPending();
      await sub.cancel();
      // A frame that failed keeps the pointer before it, so the next
      // pull from there brings it back.
      if (handled.length < ids.length) break;
      final newest = page.envelopes.isEmpty
          ? since
          : page.envelopes.last.serverTimestampMs.toInt();
      await receiver.advanceSyncPointer(newest,
          release: page.more ? null : token);
      // Never spin on a page that moved nothing. ponytail: more than a
      // page of frames in one millisecond stalls here; that needs an
      // op_id tie-break in the cursor.
      if (!page.more || receiver.syncPointer <= since) break;
    }
  } finally {
    ws.endSyncBuffer();
  }
  return pulled;
}

/// [background]: the engine a distributor starts to deliver a wake.
Future<AppServices> initializeApp({bool background = false}) async {
  await configStore.init();

  // --- config / secure-storage bootstrapping --------------------------------
  final prefs = await SharedPreferences.getInstance();
  await archiveV2Data();
  final consentAccepted =
      (prefs.getBool(kV3ConsentAcceptedKey) ?? false) || !await hasV2Data();
  VartalapTheme.themeMode = switch (prefs.getString('theme_mode')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  // --- local store: one file per account, opened once we know who ---------
  final docsDir = await getApplicationDocumentsDirectory();

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

  // Start the WS transport. If no accesskey yet (pre-login), it stays
  // disconnected and auto-connects once auth lands. Reconnect with
  // backoff on disconnect.
  await wsTransport.start();

  // The account's store comes and goes with sign-in ([AppServices.store]).
  late final AppServices services;
  final notifications = MessageNotifications(
    store: () => services.store,
    selfUserId: () => authClient.currentUserId,
  );
  await notifications.init();

  final pushService = PushService(
    authClient: authClient,
    notifyWake: notifications.afterWake,
  );

  services = AppServices(
    authClient: authClient,
    authService: authService,
    wsTransport: wsTransport,
    restTransport: restTransport,
    pushService: pushService,
    notifications: notifications,
    consentAccepted: consentAccepted,
    pushPromptSeen: prefs.getBool(kPushPromptSeenKey) ?? false,
    dbDir: docsDir.path,
  );
  // The store, scheduler and chat service are the account's: built at
  // login, closed (file kept) at logout.
  authService.onLogin = services.openAccount;
  authService.onLogout = services.closeAccount;

  // SYNC_PROTOCOL §12.3 — the wake says nothing, so the client owns
  // the follow-up: WS back up, then drain whatever was queued.
  pushService.onWake = () async {
    await wsTransport.start();
    return services.pullPendingSync();
  };
  // AUTH_CONTRACT §5.1 — deregister while the accesskey still works.
  authService.onBeforeLogout = () async {
    await notifications.cancelAll();
    await pushService.deregister();
  };
  try {
    await pushService.start(reconcile: !background);
  } catch (e) {
    // No distributor plugin (desktop, tests) — push is simply off.
    debugPrint('Push init failed: $e');
  }

  // If we already have a signed-in session (restoreSession populated
  // currentUserId), open its store and stand up the inbound receiver now
  // so push frames apply from first WS connection. Otherwise it lands on
  // login. A wake with no one signed in leaves the disk alone.
  final restoredUserId = authClient.currentUserId;
  if (restoredUserId != null || !background) {
    await migrateLegacyDb(docsDir.path, restoredUserId);
  }
  if (restoredUserId != null) {
    await services.openAccount(restoredUserId, adoptGroups: !background);
    // Best-effort initial pull — picks up anything the server queued
    // between the last connection and now (e.g. seed-peer DM created
    // at OTP-verify on a fresh install). Server never auto-pushes.
    unawaited(services.pullPendingSync());
  }

  return services;
}

/// The 9-hex user_id lives in `AuthClient.currentUserId` after
/// restoreSession or OTP verify.
int _parseUserIdOrZero(String userId) {
  try {
    return Uuid7Gen.parseUserIdHex(userId);
  } catch (_) {
    // Corrupt stored user_id — log and proceed with 0. On the next
    // OTP verify the fresh user_id replaces this and the account is
    // reopened with it.
    return 0;
  }
}

/// [InboundReceiver.resolveProfile] callback — the one place the sync
/// package's decision-79 stranger-DM backfill reaches into
/// `vartalap_transport` (the receiver itself must stay transport-free).
/// Errors propagate to the receiver's own best-effort catch.
Future<ContactProfile?> _resolveContactProfile(
  AuthClient client,
  String userId,
) async {
  final json = await client.getUser(userId);
  return ContactProfile(
    username: json['username'] as String?,
    displayName: json['displayName'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
  );
}

/// §15.6 — groups the server has for us that this device doesn't (a
/// reinstall, or an add whose event was lost). Best-effort: offline,
/// the next login tries again.
Future<void> _adoptServerGroups(
  AuthClient client,
  InboundReceiver receiver,
) async {
  try {
    final groups = await client.getChannels();
    await receiver.adoptGroups({
      for (final g in groups) g['channel_id'] as String: groupRosterFromJson(g),
    });
  } catch (e) {
    // ignore: avoid_print
    print('adoptServerGroups failed: $e');
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

class _AppState extends State<App> with WidgetsBindingObserver {
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

  /// A `vartalap://u/` profile link (decision 152) waiting for a signed
  /// in user with a handle: opened from the camera, a browser or chat.
  String? _pendingLink;

  /// The chat a tapped notification asked for, waiting like
  /// [_pendingLink] for a signed in user with a handle.
  String? _pendingChat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cold start: Flutter hands the link over as the initial route.
    final initial = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (parseUsernameLink(initial) != null) _pendingLink = initial;
    _consentAccepted = widget.services.consentAccepted;
    _pushPromptSeen = widget.services.pushPromptSeen;
    // A chat's notification opens that chat; "New activity" and the
    // summary name none, so they surface the chat list (the root route).
    final notifications = widget.services.notifications;
    notifications.onTap = (channelId) {
      if (channelId == null) {
        _navKey.currentState?.popUntil((route) => route.isFirst);
      } else {
        setState(() => _pendingChat = channelId);
      }
    };
    // Cold start: the plugin keeps the tap that launched us.
    unawaited(notifications.launchChannel().then((channelId) {
      if (channelId != null && mounted) {
        setState(() => _pendingChat = channelId);
      }
    }));
    unawaited(notifications.cancelWake());
    _isLogin = widget.services.authService.isLoggedIn;
    _username = widget.services.authService.username;
    _usernameSub = widget.services.authService.usernameChange.listen((u) {
      setState(() => _username = u);
      // AUTH_CONTRACT §2.4: push/vapid and push/topic are behind the
      // USERNAME_REQUIRED gate like every other authenticated route, so
      // the endpoint can only be registered once the handle lands.
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
        final userId = widget.services.authService.currentUserId;
        if (userId != null) {
          // AuthService.onLogin already opened the account (store,
          // scheduler, receiver bound to this user_id), so pull
          // whatever the server has queued.
          unawaited(widget.services.pullPendingSync());
          // Kick the WS transport so it connects now that we have an
          // accesskey. If already connected this is a no-op.
          unawaited(widget.services.wsTransport.start());
          // AUTH_CONTRACT §5.1: the endpoint is stored per (user, device),
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
    _authFailureSub = widget.services.authFailures.listen((_) {
      _refreshAuthOnDemand();
    });
    _reauthRequiredSub =
        widget.services.wsTransport.reauthRequired.listen((_) {
      _refreshAuthOnDemand();
    });
  }

  /// The app was running: the link comes as a pushed route. Ours, so
  /// the navigator never tries it as a page name.
  @override
  Future<bool> didPushRouteInformation(RouteInformation info) async {
    final link = info.uri.toString();
    if (parseUsernameLink(link) == null) return false;
    setState(() => _pendingLink = link);
    return true;
  }

  void _openPendingLink() {
    final link = _pendingLink;
    final context = _navKey.currentContext;
    if (link == null || context == null || !_isLogin || _username == null) {
      return;
    }
    _pendingLink = null;
    unawaited(openUsernameLink(
      context,
      link: link,
      chatService: widget.services.chatService,
      authService: widget.services.authService,
    ));
  }

  Future<void> _openPendingChat() async {
    final channelId = _pendingChat;
    if (channelId == null || !_isLogin || _username == null) return;
    _pendingChat = null;
    final chat = await widget.services.chatService.fetchChannel(channelId);
    final navigator = _navKey.currentState;
    if (chat == null || navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    unawaited(navigator.push(MaterialPageRoute<void>(
      builder: (_) => ChatScreen(
        channelId: chat.channelId,
        channelName: chat.title,
        channelKind: chat.kind,
        chatService: widget.services.chatService,
        authService: widget.services.authService,
      ),
    )));
  }

  /// Back on screen: the generic "New activity" has said its piece.
  /// Chat notifications stay until their chat is read.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.services.notifications.cancelWake());
    }
  }

  Future<void> _refreshAuthOnDemand() async {
    if (!widget.services.authService.isLoggedIn) return;
    final ok = await widget.services.authService.refreshSession();
    if (ok && mounted) {
      widget.services.scheduler?.resumeAfterAuthRefresh();
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
    // Decision 6 first-run onboarding: the push chooser, shown after the
    // username step and only while there is a question to ask (Google
    // on offer, or no single push app to use silently).
    return ValueListenableBuilder<PushState>(
      valueListenable: widget.services.pushService.state,
      builder: (context, pushState, child) =>
          pushState == PushState.choiceNeeded
              ? PushOnboardingScreen(
                  push: widget.services.pushService,
                  onDone: _onPushPromptDone,
                )
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
    if (_pendingLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingLink());
    }
    if (_pendingChat != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingChat());
    }
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
            navigatorObservers: [chatRouteObserver],
            builder: (context, child) => _SystemBars(child: child!),
            // Home, always (this is home's route, rebuilt with the app's
            // state): a cold-start profile link is the platform's initial
            // route, but it is opened over home, not as a page.
            onGenerateInitialRoutes: (_) => [
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/'),
                builder: (_) => _home(),
              ),
            ],
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
    WidgetsBinding.instance.removeObserver(this);
    _authSub.cancel();
    _usernameSub.cancel();
    _wsStateSub?.cancel();
    _authFailureSub?.cancel();
    _reauthRequiredSub?.cancel();
    widget.services.pushService.dispose();
    unawaited(widget.services.closeAccount());
    unawaited(widget.services.authService.dispose());
    super.dispose();
  }
}

/// The system nav bar follows the app's theme, not the phone's: the
/// window behind Flutter takes the theme's surface (Android 15+ tints
/// the bar from it) and the bar's icons flip with it. App bars only
/// reach the status bar, so this region is what sits at the bottom.
class _SystemBars extends StatelessWidget {
  final Widget child;
  const _SystemBars({required this.child});

  static int? _window;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface.toARGB32();
    if (_window != surface) {
      _window = surface;
      const MethodChannel('vartalap/window')
          .invokeMethod<void>('setBackground', surface)
          .catchError((Object _) {}); // widget tests have no platform
    }
    final dark = theme.brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(systemNavigationBarColor: theme.colorScheme.surface),
      child: child,
    );
  }
}
