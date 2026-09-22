/// L3 (plan §8) — the real UI on an Android emulator against a real
/// v3 server. Drives first launch end to end: consent → intro → login →
/// OTP → username → chats, then a DM from a second, out-of-band user
/// (a full second client stack in-process, exactly like
/// `test/integration/real_server_test.dart`) and a reply typed into the
/// real chat screen — then the group flow: handle lookup, group create
/// with both peers, messages both ways, chat info, and the owner
/// leaving with the server's succession applied.
///
/// No permissions needed: the emulator has no address book and never
/// grants READ_CONTACTS, and the Contacts tab's "Find by @username"
/// works without it.
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/smoke_test.dart -d emulator-5554 \
///     --flavor dev \
///     --dart-define=API_URL=http://10.0.2.2:8086 \
///     --dart-define=WS_URL=ws://10.0.2.2:8086/wss
@Timeout(Duration(minutes: 10))
library vartalap.smoke_test;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vartalap/main.dart' as app;
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/chat_info/chat_info.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/contact_info/contact_info.dart';
import 'package:vartalap/screens/group_create/group_create.dart';
import 'package:vartalap/screens/login/choose_username.dart';
import 'package:vartalap/screens/login/login.dart';
import 'package:vartalap/screens/login/verifyOtp.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const String _apiUrl =
    String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8086');

final Random _rng = Random.secure();

/// Fresh +91 number per run — a username can only be set once per 90
/// days, so an account is never reused.
String _freshPhone() => '+919${_rng.nextInt(900000000) + 100000000}';

/// Server rule: 3-30 chars of `a-z 0-9 . _`, starting with a letter.
String _freshUsername() =>
    'e${_rng.nextInt(1 << 30).toString().padLeft(9, '0')}';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first run: consent → login → chats → DM + group round trip',
      (tester) async {
    final phoneA = _freshPhone();
    final usernameA = _freshUsername();
    final groupName = 'Trip ${_rng.nextInt(1 << 30)}';
    late _Peer peer;
    late _Peer peerC;
    // The app user's server-side user_id, learned the only way the test
    // can: B looks A up by handle in step 8.
    late String appUserId;

    // Each peer stack opens its own ChatStore, and `ChatStore.open`
    // overwrites the `ChatStore.current` global that AuthService.logout
    // wipes — so BOTH boot BEFORE the app, leaving the app's store as
    // `current`. A third stack introduced mid-test would steal it.
    await tester.runAsync(() async {
      peer = await _Peer.boot('B');
      peerC = await _Peer.boot('C');
      await peer.login();
      await peerC.login();
    });

    final coldStart = Stopwatch()..start();
    app.main(const []);

    // ---- 1. destructive-reset consent ---------------------------------
    await _waitFor(tester, find.text('Continue and reset'));
    debugPrint('SMOKE cold start → first frame: '
        '${coldStart.elapsedMilliseconds}ms');
    await binding.convertFlutterSurfaceToImage();
    await _shot(tester, binding, '01-consent');
    await tester.tap(find.text('Continue and reset'));

    // ---- 2. intro -----------------------------------------------------
    await _waitFor(tester, find.text('Agree and continue'));
    await _shot(tester, binding, '02-intro');
    await tester.tap(find.text('Agree and continue'));

    // ---- 3. phone number ----------------------------------------------
    await _waitFor(tester, find.byType(LoginScreen));
    await tester.enterText(
      find.descendant(
        of: find.byType(LoginScreen),
        matching: find.byType(TextField),
      ).last,
      phoneA.substring(3),
    );
    await _pump(tester);
    await _shot(tester, binding, '03-login');
    await tester.tap(find.text('Next'));

    // ---- 4. OTP -------------------------------------------------------
    await _waitFor(tester, find.byType(VerifyOtpScreen));
    final code = await tester.runAsync(() => _devOtp(phoneA));
    await tester.enterText(
      find.descendant(
        of: find.byType(VerifyOtpScreen),
        matching: find.byType(TextField),
      ),
      code!,
    );
    await _pump(tester);
    await _shot(tester, binding, '04-otp');

    // ---- 5. username --------------------------------------------------
    await _waitFor(tester, find.byType(ChooseUsernameScreen));
    await tester.enterText(
      find.descendant(
        of: find.byType(ChooseUsernameScreen),
        matching: find.byType(TextField),
      ),
      usernameA,
    );
    // Continue only enables once the debounced availability check lands.
    await _waitFor(tester, find.textContaining('is available'));
    await _shot(tester, binding, '05-username');
    await tester.tap(find.text('Continue'));

    // ---- 6. ntfy onboarding (no distributor on the emulator) ----------
    await _waitFor(
      tester,
      find.byType(ChatsScreen),
      also: find.text('Later'),
    );
    if (find.text('Later').evaluate().isNotEmpty) {
      await _shot(tester, binding, '06-push-onboarding');
      await tester.tap(find.text('Later'));
    }

    // ---- 7. chats -----------------------------------------------------
    await _waitFor(tester, find.byIcon(Icons.chat));
    coldStart.stop();
    debugPrint('SMOKE launch → chats (whole signup): '
        '${coldStart.elapsedMilliseconds}ms');
    await _shot(tester, binding, '07-chats-empty');
    _step('1-7 signup');

    // ---- 8. the peer opens a DM and sends ------------------------------
    const inbound = 'hello from the peer';
    await tester.runAsync(() async {
      final contact = await peer.chat.findByUsername(usernameA);
      appUserId = contact.userId;
      peer.channelId = await peer.chat.startDirectMessage(
        localUserId: peer.userId,
        peerUserId: contact.userId,
        peerName: usernameA,
      );
      await peer.settle();
      await peer.chat.sendMessage(
        channelId: peer.channelId,
        body: inbound,
        authorUserId: peer.userId,
      );
    });

    await _waitFor(tester, find.byType(ChannelTile));
    // Decision 79: this DM's ChannelCreated carries no name (one_to_one,
    // peer never in our contacts) — the row must resolve the peer's
    // profile and show "@<handle>", not fall back to "Unknown".
    await _waitFor(tester, find.text('@${peer.username}'));
    expect(find.text('Unknown'), findsNothing,
        reason: 'decision 79: a stranger DM must not render as "Unknown" '
            'in the chat list.');
    await _shot(tester, binding, '08-chats-row');

    // ---- 9. open the chat, see the bubble ------------------------------
    await tester.tap(find.byType(ChannelTile).first);
    await _waitFor(tester, find.text(inbound));
    expect(find.text('@${peer.username}'), findsWidgets,
        reason: 'decision 79: the chat header must also show the peer\'s '
            '@handle, not "Unknown".');
    await _shot(tester, binding, '09-chat-inbound');

    // ---- 10. reply -----------------------------------------------------
    const reply = 'reply from the emulator';
    await tester.enterText(
      find.descendant(
        of: find.byType(ChatScreen),
        matching: find.byType(TextField),
      ),
      reply,
    );
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await _waitFor(tester, find.text(reply));
    // Single tick = sent, double = delivered (chat.dart `_stateIcon`).
    await _waitFor(tester, find.byIcon(Icons.check), also: find.byIcon(Icons.done_all));
    await _shot(tester, binding, '10-chat-reply-sent');

    // ---- 11. the peer receives it ---------------------------------------
    var got = <String>[];
    for (var i = 0; i < 100 && !got.contains(reply); i++) {
      await _pump(tester);
      got = (await tester.runAsync(() => peer.bodies()))!;
    }
    expect(got, contains(reply),
        reason: 'the reply typed into the real chat screen must reach the '
            'peer stack over the real server. Peer sees: $got');
    _step('11 dm-round-trip');

    // ---- 12. C becomes a contact via the @username lookup ---------------
    // B is already a contact row — the decision-79 backfill on B's
    // inbound ChannelCreated upserts one (that is what step 8 asserted
    // by seeing "@handle" rather than "Unknown"). C has never touched
    // us, so C has to come in through the handle lookup, which is the
    // only in-app path to a stranger and is what a real user would do.
    await tester.pageBack();
    await _waitFor(tester, find.byIcon(Icons.chat));
    await tester.tap(find.byIcon(Icons.chat));
    await _waitFor(tester, find.byType(NewChatScreen));
    await tester.enterText(
      find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.hintText == 'Find by @username'),
      peerC.username,
    );
    await _pump(tester);
    // onSubmitted, not the arrow button: the button can sit below the
    // fold on a short emulator screen, and the field is the same code
    // path.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _waitFor(tester, find.byType(ContactInfoScreen));
    await _shot(tester, binding, '12-contact-found');
    // Not pageBack(): the route underneath is still built, so there are
    // two back buttons on screen and pageBack refuses to guess. The
    // topmost route's is the last one in the tree.
    await tester.tap(find.byType(BackButton).last);
    // The route below is already in the tree, so "New Chat" matches
    // mid-transition — wait for the popped route to actually go, or the
    // tab tap below lands on a route that is still animating out.
    await _waitGone(tester, find.byType(ContactInfoScreen));
    _step('12 handle-lookup');

    // ---- 13. create the group with both peers ---------------------------
    await tester.tap(find.text('Groups'));
    await _waitFor(tester, find.text('New group'));
    await _settle(tester);
    await tester.tap(find.text('New group'));
    await _waitFor(tester, find.byType(GroupCreateScreen));
    // Both contact rows render as "@handle" — displayLabel prefers the
    // address-book name, and neither peer has one here.
    await _waitFor(tester, find.text('@${peer.username}'));
    await _waitFor(tester, find.text('@${peerC.username}'));
    await _settle(tester);
    await tester.tap(find.text('@${peer.username}'));
    await tester.tap(find.text('@${peerC.username}'));
    await _pump(tester);
    await _shot(tester, binding, '13-group-members-picked');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await _waitFor(tester, find.text('Group Name'));
    await _settle(tester);
    await tester.enterText(
      find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Group name'),
      groupName,
    );
    await _pump(tester);
    await tester.tap(find.text('Create Group'));
    await _waitFor(tester, find.byType(ChatScreen));
    await _settle(tester);
    expect(
      find.descendant(
          of: find.byType(AppBar), matching: find.text(groupName)),
      findsOneWidget,
      reason: 'Create Group pushReplaces into the group ChatScreen, whose '
          'header is the group name.',
    );
    await _shot(tester, binding, '14-group-created');
    _step('13 group-create');

    // ---- 14. send into the group; both peers receive --------------------
    const groupOut = 'first message in the group';
    await tester.enterText(
      find.descendant(
        of: find.byType(ChatScreen),
        matching: find.byType(TextField),
      ),
      groupOut,
    );
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await _waitFor(tester, find.text(groupOut));
    await _waitFor(tester, find.byIcon(Icons.check),
        also: find.byIcon(Icons.done_all));
    await _shot(tester, binding, '15-group-message-sent');

    for (final p in [peer, peerC]) {
      var seen = <String>[];
      for (var i = 0; i < 200 && !seen.contains(groupOut); i++) {
        await _pump(tester);
        seen = (await tester.runAsync(() async {
          final gid = await p.groupChannelId();
          if (gid == null) return const <String>[];
          return p.bodies(gid);
        }))!;
      }
      expect(seen, contains(groupOut),
          reason: 'peer ${p.label} must receive the group message over the '
              'real server (ChannelCreated fanout first, then the '
              'message). Sees: $seen');
    }
    _step('14 group-message-out');

    // ---- 15. a peer sends into the group; the open screen shows it ------
    const groupIn = 'and one back from B';
    await tester.runAsync(() async {
      final gid = await peer.groupChannelId();
      await peer.chat.sendMessage(
        channelId: gid!,
        body: groupIn,
        authorUserId: peer.userId,
      );
    });
    await _waitFor(tester, find.text(groupIn));
    await _shot(tester, binding, '16-group-message-in');
    _step('15 group-message-in');

    // ---- 16. chat info lists all three, app user as owner ---------------
    await tester.tap(
        find.descendant(of: find.byType(AppBar), matching: find.text(groupName)));
    await _waitFor(tester, find.byType(ChatInfoScreen));
    await _waitFor(tester, find.text('3 members'));
    await _settle(tester);
    for (final label in ['You', '@${peer.username}', '@${peerC.username}']) {
      expect(find.text(label), findsWidgets,
          reason: 'group info must list every member; missing "$label".');
    }
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'You'),
        matching: find.text('Owner'),
      ),
      findsOneWidget,
      reason: 'the creator is the owner (decision 80), and the badge on '
          'their own row is where the UI says so.',
    );
    await _shot(tester, binding, '17-group-info');
    _step('16 group-info');

    // ---- 17. the owner leaves; the server promotes a successor ----------
    await _scrollTo(tester, find.text('Leave group'));
    await _settle(tester);
    await tester.tap(find.text('Leave group'));
    await _waitFor(tester, find.text('Leave $groupName?'));
    await _settle(tester);
    await _shot(tester, binding, '18-leave-confirm');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Leave group')));

    // Back at Chats, and the group is gone from the list.
    await _waitFor(tester, find.byIcon(Icons.chat));
    await _waitGone(tester, find.text(groupName));
    await _shot(tester, binding, '19-chats-after-leave');

    // Decision 9: the server hands the group to the longest-standing
    // remaining member. Which of B/C that is depends on the order the
    // server recorded them, so assert the invariant, not the name:
    // exactly one owner, and not us.
    var owners = <String>[];
    for (var i = 0; i < 200; i++) {
      await _pump(tester);
      owners = (await tester.runAsync(() async {
        final gid = await peer.groupChannelId();
        if (gid == null) return const <String>[];
        return [
          for (final m in await peer.store.fetchChannelMembers(gid))
            if (m.role == 'owner') m.userId
        ];
      }))!;
      if (owners.length == 1 && owners.single != appUserId) break;
    }
    expect(owners, hasLength(1),
        reason: 'decision 9: after the owner leaves the group carries on '
            'under exactly one new owner. Peer B sees owners: $owners');
    expect(owners.single, isNot(appUserId),
        reason: 'decision 9: the successor is a remaining member, never '
            'the user who left.');
    _step('17 owner-leaves');

    await tester.runAsync(() async {
      await peer.shutdown();
      await peerC.shutdown();
    });
  });
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// One frame plus a slice of real time — the live binding runs real
/// timers, so the app's async work only advances while we yield.
Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)));
}

/// Pump until [finder] (or [also], whichever lands first) has a match.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Finder? also,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    await _pump(tester);
    if (finder.evaluate().isNotEmpty) return;
    if (also != null && also.evaluate().isNotEmpty) return;
  }
  fail('timed out after ${timeout.inSeconds}s waiting for $finder');
}

/// Yield enough real time for an in-flight route, tab or dialog
/// animation to finish.
///
/// Route pushes/pops, `TabBarView` scrolls and dialog fades are all
/// fixed 300ms transitions, and a tap that lands while one is running is
/// silently swallowed — the finder matches (the widget is in the tree)
/// but the gesture goes nowhere. `pumpAndSettle` is not an option under
/// the live binding, whose real timers and streams never go quiet, so
/// this waits out the known duration instead.
Future<void> _settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await _pump(tester);
  }
}

/// Drag the on-screen list until [finder] matches. A `ListView` only
/// instantiates what is on screen, so the actions at the bottom of the
/// group-info screen genuinely do not exist in the element tree until
/// scrolled to — a finder for them comes back empty, not off-screen.
Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  int maxDrags = 20,
}) async {
  for (var i = 0; i < maxDrags && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -320));
    await _pump(tester);
  }
  await _waitFor(tester, finder, timeout: const Duration(seconds: 5));
}

/// Pump until [finder] has no match — the leave flow's "and it's gone".
Future<void> _waitGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    await _pump(tester);
    if (finder.evaluate().isEmpty) return;
  }
  fail('timed out after ${timeout.inSeconds}s waiting for $finder to go');
}

/// Wall clock since the previous [_step], printed as the drive runs so a
/// slow step is obvious in the log without instrumenting anything else.
final Stopwatch _stepClock = Stopwatch()..start();
void _step(String label) {
  debugPrint('SMOKE step $label: ${_stepClock.elapsedMilliseconds}ms');
  _stepClock.reset();
}

Future<void> _shot(WidgetTester tester,
    IntegrationTestWidgetsFlutterBinding binding, String name) async {
  await tester.pump();
  await binding.takeScreenshot(name);
}

/// `GET /v3.0/auth/dev/otp` — the dev-only readback standing in for the
/// SMS the emulator can't receive.
Future<String> _devOtp(String phone) async {
  final uri = Uri.parse(_apiUrl).resolve(
    '/v3.0/auth/dev/otp?phone=${Uri.encodeQueryComponent(phone)}',
  );
  final resp = await http.get(uri);
  if (resp.statusCode != 200) {
    throw StateError('dev OTP readback failed for $phone: '
        '${resp.statusCode} ${resp.body}');
  }
  return (jsonDecode(resp.body) as Map<String, dynamic>)['code'] as String;
}

/// The second user: a full client stack (store, auth, transports,
/// scheduler, chat service, inbound receiver) in the same process,
/// wired like `initializeApp` and like the headless real-server suite.
class _Peer {
  /// Which peer this is in the log ("B", "C").
  final String label;
  final Uri baseUrl;
  final String phone;
  final ChatStore store;
  final AuthClient authClient;
  final AuthService authService;
  final WsTransport ws;
  final RestTransport rest;
  final SyncScheduler scheduler;
  final ChatService chat;
  InboundReceiver? inbound;
  String channelId = '';
  String username = '';

  _Peer._(this.label, this.baseUrl, this.phone, this.store, this.authClient,
      this.authService, this.ws, this.rest, this.scheduler, this.chat);

  String get userId => authService.currentUserId ?? '';

  static Future<_Peer> boot(String label) async {
    final baseUrl = Uri.parse(_apiUrl);
    // In-memory, like every other test-side store. ChatStore.open turns
    // sqflite's singleInstance caching off for `:memory:`, so the two
    // peers and the app under test get three separate databases in this
    // one process — with the caching on they would all be one.
    final store = await ChatStore.open(path: inMemoryDatabasePath);
    final authClient = AuthClient(baseUrl: baseUrl);
    // Never the real secure storage: the app under test owns those keys.
    final authService =
        AuthService(client: authClient, storage: _InMemoryStorage());
    await authService.init();
    final ws = WsTransport(
      endpoint: baseUrl.replace(
          scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws', path: '/wss'),
      auth: authClient,
    );
    final rest = RestTransport(baseUrl: baseUrl, auth: authClient);
    final scheduler = SyncScheduler(
      store: store,
      wsTransport: ws,
      restTransport: rest,
      backoff: const FixedBackoff(Duration(milliseconds: 200)),
      clock: Clock.system,
    );
    await scheduler.start();
    final chat = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: authClient,
      wsTransport: ws,
      uuidGen: Uuid7Gen(userIdBits: 0),
      clock: Clock.system,
    );
    return _Peer._(label, baseUrl, _freshPhone(), store, authClient,
        authService, ws, rest, scheduler, chat);
  }

  Future<void> login() async {
    await authService.sendOtp(phone);
    await authService.verifyOtp(phone, await _devOtp(phone));
    username = _freshUsername();
    await authService.setUsername(username);
    chat.reseedForUser(userId);
    final receiver = InboundReceiver(
      store: store,
      pushes: ws.pushes,
      localUserId: userId,
    );
    await receiver.start();
    inbound = receiver;
    await ws.start();
    final sw = Stopwatch()..start();
    while (ws.currentState != TransportState.connected &&
        sw.elapsed < const Duration(seconds: 20)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await pullPendingSync();
  }

  Future<void> pullPendingSync() async {
    try {
      for (final env in await rest.pullPendingSync()) {
        ws.injectPush(env);
      }
      await inbound?.drainPending();
    } finally {
      ws.endSyncBuffer();
    }
  }

  /// Wait for the outbound queue to drain (the channel create is a REST
  /// op; sending before its ACK would be out of order).
  Future<void> settle() async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < const Duration(seconds: 25)) {
      final r =
          await store.db.rawQuery('SELECT COUNT(*) c FROM outbound_ops');
      if (((r.single['c'] as int?) ?? 0) == 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// The group this peer has been added to, or null until the
  /// ChannelCreated fanout has landed. One group per run.
  Future<String?> groupChannelId() async {
    final rows = await store.db.query(
      'channels',
      columns: const ['channel_id'],
      where: 'kind = ?',
      whereArgs: const ['group'],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['channel_id'] as String;
  }

  Future<List<String>> bodies([String? channel]) async {
    final id = channel ?? channelId;
    if (id.isEmpty) return const [];
    final rows = await store.fetchChannelMessages(id);
    return [
      for (final m in rows.reversed)
        if (m.body != null) m.body!
    ];
  }

  Future<void> shutdown() async {
    await inbound?.stop();
    await scheduler.stop();
    await ws.dispose();
    await rest.dispose();
    await authService.dispose();
    await store.close();
  }
}

/// The app under test owns the platform secure storage; the peer gets a
/// map (same stand-in the headless suites use).
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
        '_InMemoryStorage.${invocation.memberName} — not implemented',
      );
}
