/// L3 (plan §8) — the real UI on an Android emulator against a real
/// v3 server. Drives first launch end to end: consent → intro → login →
/// OTP → username → chats, then a DM from a second, out-of-band user
/// (a full second client stack in-process, exactly like
/// `test/integration/real_server_test.dart`) and a reply typed into the
/// real chat screen.
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/smoke_test.dart -d emulator-5554 \
///     --flavor dev \
///     --dart-define=API_URL=http://10.0.2.2:8086 \
///     --dart-define=WS_URL=ws://10.0.2.2:8086/wss
@Timeout(Duration(minutes: 10))
library vartalap.smoke_test;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:vartalap/main.dart' as app;
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/login/choose_username.dart';
import 'package:vartalap/screens/login/login.dart';
import 'package:vartalap/screens/login/verifyOtp.dart';
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

  testWidgets('first run: consent → login → chats → DM round trip',
      (tester) async {
    final phoneA = _freshPhone();
    final usernameA = _freshUsername();
    late _Peer peer;

    // The peer stack opens its own ChatStore, and `ChatStore.open`
    // overwrites the `ChatStore.current` global that AuthService.logout
    // wipes — so it boots BEFORE the app, leaving the app's store as
    // `current`.
    await tester.runAsync(() async {
      peer = await _Peer.boot();
      await peer.login();
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

    // ---- 8. the peer opens a DM and sends ------------------------------
    const inbound = 'hello from the peer';
    await tester.runAsync(() async {
      final contact = await peer.chat.findByUsername(usernameA);
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
    await _shot(tester, binding, '08-chats-row');

    // ---- 9. open the chat, see the bubble ------------------------------
    await tester.tap(find.byType(ChannelTile).first);
    await _waitFor(tester, find.text(inbound));
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

    await tester.runAsync(peer.shutdown);
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

  _Peer._(this.baseUrl, this.phone, this.store, this.authClient,
      this.authService, this.ws, this.rest, this.scheduler, this.chat);

  String get userId => authService.currentUserId ?? '';

  static Future<_Peer> boot() async {
    final baseUrl = Uri.parse(_apiUrl);
    final dir = await Directory.systemTemp.createTemp('vartalap_peer');
    final store = await ChatStore.open(path: '${dir.path}/peer.db');
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
    return _Peer._(baseUrl, _freshPhone(), store, authClient, authService, ws,
        rest, scheduler, chat);
  }

  Future<void> login() async {
    await authService.sendOtp(phone);
    await authService.verifyOtp(phone, await _devOtp(phone));
    await authService.setUsername(_freshUsername());
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

  Future<List<String>> bodies() async {
    if (channelId.isEmpty) return const [];
    final rows = await store.fetchChannelMessages(channelId);
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
