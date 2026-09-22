/// The v3.0 client golden path against a REAL chat-server stack.
///
/// Two complete client stacks run in-process — two [ChatStore]s on temp
/// files, two [AuthClient] / [WsTransport] / [RestTransport] /
/// [SyncScheduler] / [InboundReceiver] / [AuthService] / [ChatService]
/// sets, wired exactly the way `test/golden_path_test.dart` wires one
/// against the mock — and talk to each other through the real gateway.
/// Nothing here is faked: fresh random phone numbers, the dev OTP
/// endpoint, real REST, a real WebSocket per client.
///
/// Skipped unless the server URL is supplied. Run it with:
///
///   flutter test test/integration/real_server_test.dart \
///     --dart-define=REAL_SERVER_URL=http://localhost:8085
///
/// `REAL_SERVER_URL` in the process environment works too, for CI jobs
/// that can't pass `--dart-define`.
@Timeout(Duration(minutes: 5))
library vartalap.real_server_test;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const String _define = String.fromEnvironment('REAL_SERVER_URL');

String get _serverUrl {
  if (_define.isNotEmpty) return _define;
  return Platform.environment['REAL_SERVER_URL'] ?? '';
}

/// Real network round-trips plus an async fanout bus — generous, but
/// every wait is a poll that exits the moment the condition holds.
const Duration budget = Duration(seconds: 25);

final Random _rng = Random.secure();

/// A phone nobody owns, in the +1555 test range, fresh per run so the
/// account is always new (a username can only be set once per 90 days,
/// so reusing an account would 429).
String _freshPhone() =>
    '+1555${_rng.nextInt(9000000) + 1000000}';

/// Server rule: 3-30 chars of `a-z 0-9 . _`, starting with a letter.
String _freshUsername() =>
    'c${(_rng.nextInt(1 << 30)).toString().padLeft(9, '0')}';

/// A send that the server accepted: promoted past pending/sending.
final Matcher _isAcked = isIn(const [
  MessageState.sent,
  MessageState.delivered,
  MessageState.read,
]);

void main() {
  final baseUrl = _serverUrl;

  group(
    'golden path (real server)',
    skip: baseUrl.isEmpty
        ? 'set --dart-define=REAL_SERVER_URL=http://localhost:8085 '
            '(or the REAL_SERVER_URL env var) to run this'
        : null,
    () {
      late _Client a;
      late _Client b;
      late _Client c;
      late String usernameB;
      String dmChannel = '';
      String groupChannelId = '';
      String trioChannelId = '';
      final sent = <String>[];

      setUpAll(() async {
        a = await _Client.boot(baseUrl, label: 'A');
        // C boots BETWEEN A and B on purpose: `ChatStore.open` sets the
        // process-wide `ChatStore.current`, step 9 leans on that being
        // B's store, and booting last is what decides it.
        c = await _Client.boot(baseUrl, label: 'C');
        b = await _Client.boot(baseUrl, label: 'B');
      });

      tearDownAll(() async {
        await a.shutdown();
        await b.shutdown();
        await c.shutdown();
      });

      // ---- 1 ------------------------------------------------------------
      test('1. OTP → verify → username, for both clients', () async {
        await a.login();
        await b.login();
        await c.login();

        expect(
          [a.userId, b.userId, c.userId],
          everyElement(matches(RegExp(r'^[0-9a-f]{9}$'))),
          reason: 'AUTH_CONTRACT §2: otp/verify returns a 9-hex-char '
              'user_id. Got ${a.userId} / ${b.userId}.',
        );
        expect({a.userId, b.userId, c.userId}, hasLength(3));

        // Until a handle is set, every non-exempt route is 403.
        await a.setUsername(_freshUsername());
        usernameB = _freshUsername();
        await b.setUsername(usernameB);
        await c.setUsername(_freshUsername());

        expect(
          [a.authService.username, b.authService.username],
          isNot(contains(null)),
          reason: 'AUTH_CONTRACT §2.4: the USERNAME_REQUIRED gate stays '
              'closed until PATCH /v3.0/users/me sets a handle.',
        );
      });

      // ---- 2 ------------------------------------------------------------
      test('2. A finds B by @username → the DM id is derived, not created',
          () async {
        final contact = await a.chat.findByUsername(usernameB);
        expect(
          contact.userId,
          b.userId,
          reason: 'AUTH_CONTRACT §7.6: GET /v3.0/users/by-username/{handle} '
              "resolves to the holder's user_id.",
        );

        dmChannel = await a.chat.startDirectMessage(
          localUserId: a.userId,
          peerUserId: b.userId,
          peerName: usernameB,
        );
        expect(
          dmChannel,
          dmChannelId(a.userId, b.userId),
          reason: 'SYNC_PROTOCOL §11.3 (trim 4): the client and the server '
              'derive the same id from the pair. If this fails against the '
              'real server the two implementations of the hash have drifted '
              'and every DM op will come back `forbidden`.',
        );
        expect(
          await a.opDebug(dmChannel),
          contains('<empty>'),
          reason: 'trim 4: opening a DM enqueues nothing at all — there is '
              'no create op to ACK off the queue.',
        );

        // B learns about the DM from the first message on it (test 3):
        // there is no ChannelCreated for a channel the server has no row
        // for, so until somebody speaks, B holds nothing.
        expect(
          await b.hasChannel(dmChannel),
          isFalse,
          reason: 'nothing has been said yet, so there is nothing B could '
              'have heard about.',
        );
      });

      // ---- 2b -----------------------------------------------------------
      test('2b. the gateway refuses a client-authored 0x53 payload '
          '(decision 56)', () async {
        final acks = <AckFrame>[];
        final sub = a.ws.acks.listen(acks.add);
        addTearDown(sub.cancel);

        final forgedOpId =
            Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(a.userId))
                .next(nowMs: DateTime.now().millisecondsSinceEpoch);
        // 0x53 || a minimal ServerEventPayload{version:1}. The gateway
        // looks at exactly one byte of `payload`, so the rest is filler.
        a.ws.sendEphemeral(
          opId: forgedOpId,
          channelId: dmChannel,
          payload: Uint8List.fromList(const [0x53, 0x08, 0x01]),
        );

        await a.waitFor(() => acks.any((f) => f.opId == forgedOpId));
        final ack =
            acks.where((f) => f.opId == forgedOpId).firstOrNull?.outcome;
        expect(
          ack,
          isA<AckPermanentReject>().having(
              (r) => r.reason, 'reason', 'validation_failed'),
          reason: 'SYNC_PROTOCOL §10.2: server events are server-authored. '
              'This is the constraint decision 56 exists to satisfy — if it '
              'ever stops holding, read receipts and typing could go back '
              'to being 0x53 server events. Got $ack.',
        );
      });

      // ---- 3 ------------------------------------------------------------
      test('3. A sends 3 messages → B receives all three, in order',
          () async {
        for (var i = 1; i <= 3; i++) {
          final body = 'real-server message $i';
          sent.add(body);
          final row = await a.sendAndSettle(dmChannel, body);
          expect(
            row?.state,
            anyOf(MessageState.sent, MessageState.delivered, MessageState.read),
            reason: 'SYNC_PROTOCOL §5.3/§8.1: each WS_OP must come back '
                'ACK_SUCCESS. Trim 4: nothing was created, so the first WS '
                'op on a DM is resource_seq 1 and the gateway accepts it on '
                'the `peer` derivation alone. ${await a.opDebug(dmChannel)}',
          );
        }

        await b.waitForAsync(() async =>
            (await b.bodiesIn(dmChannel)).length >= sent.length);
        expect(
          await b.hasChannel(dmChannel),
          isTrue,
          reason: 'trim 4: the first message IS the introduction. B had no '
              'row for this channel a moment ago and never saw a '
              'ChannelCreated; it materialized the DM from the frame after '
              'checking the id derives from itself and sender_user_id.',
        );
        expect(
          await b.memberIds(dmChannel),
          {a.userId, b.userId},
          reason: 'with the membership the derivation implies, not one the '
              'server sent.',
        );
        expect(
          await b.bodiesIn(dmChannel),
          sent,
          reason: 'SYNC_PROTOCOL §10.1 + SPIKE_A_SCHEMA §13: the recipient '
              'orders by delivery_sequence, so the three bodies must read '
              'back in send order.',
        );
      });

      // ---- 4 ------------------------------------------------------------
      test("4. B marks read → A's messages flip to read (decision 56)",
          () async {
        await b.chat.markRead(dmChannel);
        await b.waitForAsync(() async => await b.opCount() == 0);

        final newest = (await a.store.fetchChannelMessages(dmChannel))
            .lastWhere((m) => m.body == sent.last);
        await a.waitForAsync(() async =>
            (await a.store.fetchMessage(newest.messageId))?.state ==
            MessageState.read);
        expect(
          [
            for (final body in sent)
              (await a.store.fetchMessage(
                      (await a.store.fetchChannelMessages(dmChannel))
                          .firstWhere((m) => m.body == body)
                          .messageId))
                  ?.state,
          ],
          everyElement(MessageState.read),
          reason: 'Decision 56: the receipt is a '
              'ChatPayload{TYPE_READ_RECEIPT} whose message_id is a '
              'read-up-to marker, so every earlier message the author sent '
              'flips too. ${await b.opDebug(dmChannel)}',
        );
      });

      // ---- 5 ------------------------------------------------------------
      test('5. B offline → A sends → /sync/pending delivers it exactly once',
          () async {
        await b.goOffline();
        expect(b.ws.currentState, TransportState.disconnected);

        const offlineBody = 'sent while B was offline';
        final row = await a.sendAndSettle(dmChannel, offlineBody);
        expect(
          row?.state,
          isNot(MessageState.rejected),
          reason: 'A recipient being offline must not fail the sender\'s op '
              '— the gateway queues the fanout (SYNC_PROTOCOL §10.4).',
        );

        await b.goOnline();
        await b.waitForAsync(
            () async => (await b.bodiesIn(dmChannel)).contains(offlineBody));
        expect(
          (await b.bodiesIn(dmChannel))
              .where((x) => x == offlineBody)
              .length,
          1,
          reason: 'SYNC_PROTOCOL §7.2 + §10.4: GET /v3.0/sync/pending drains '
              'the queue destructively and the op_id_seen set makes a '
              'second delivery a no-op — the message lands exactly once.',
        );

        // The drain is destructive: a second pull returns nothing new.
        final before = (await b.bodiesIn(dmChannel)).length;
        await b.pullPendingSync();
        await b.pump();
        expect(
          (await b.bodiesIn(dmChannel)).length,
          before,
          reason: 'GET /v3.0/sync/pending has no cursor and no ack — the '
              'same drain must not replay.',
        );
      });

      // ---- 6 ------------------------------------------------------------
      test('6. A creates a group with B → B sees it', () async {
        groupChannelId = await a.chat.createGroup(
          name: 'real server group',
          creatorUserId: a.userId,
          memberUserIds: [b.userId],
        );
        await a.waitForAsync(() async => await a.opCount() == 0);
        expect(
          await a.opDebug(groupChannelId),
          contains('<empty>'),
          reason: 'SYNC_PROTOCOL §11.3: POST /v3.0/channels with '
              'kind="group" must be accepted.',
        );

        await b.waitForAsync(() async => await b.hasChannel(groupChannelId));
        expect(
          await b.hasChannel(groupChannelId),
          isTrue,
          reason: 'SYNC_PROTOCOL §10.2 CHANNEL_CREATED: an added member must '
              'materialize the group locally, roster and all.',
        );
        expect(
          (await b.chat.fetchChannelMembers(groupChannelId))
              .map((m) => m.userId),
          containsAll([a.userId, b.userId]),
          reason: 'The ChannelCreated body carries the full member list.',
        );
      });

      // ---- 7 ------------------------------------------------------------
      test('7. B leaves the group → A sees the member drop off', () async {
        await b.chat.leaveGroup(groupChannelId, selfUserId: b.userId);
        await b.waitForAsync(() async => await b.opCount() == 0);
        expect(
          await b.opDebug(groupChannelId),
          contains('<empty>'),
          reason: 'decision 80: a leave is DELETE /v3.0/channels/{id}/'
              'members/{self} and must be accepted (the body carries '
              'op_id + resource_seq).',
        );

        await a.waitForAsync(() async =>
            !(await a.chat.fetchChannelMembers(groupChannelId))
                .any((m) => m.userId == b.userId));
        expect(
          (await a.chat.fetchChannelMembers(groupChannelId))
              .map((m) => m.userId),
          isNot(contains(b.userId)),
          reason: 'SYNC_PROTOCOL §10.2 CHANNEL_MEMBER_REMOVED: the remaining '
              'members must drop the leaver from their local roster.',
        );
      });

      // ---- 8 ------------------------------------------------------------
      test('8. A edits, reacts and deletes → B sees each', () async {
        final target = (await a.store.fetchChannelMessages(dmChannel))
            .firstWhere((m) => m.body == sent.first);

        // Edit.
        await a.chat.editMessage(
          channelId: dmChannel,
          messageId: target.messageId,
          newBody: 'edited on the real server',
        );
        await a.waitForAsync(() async => await a.opCount() == 0);
        await b.waitForAsync(() async =>
            (await b.store.fetchMessage(target.messageId))?.body ==
            'edited on the real server');
        expect(
          (await b.store.fetchMessage(target.messageId))?.body,
          'edited on the real server',
          reason: 'SYNC_PROTOCOL §6a.3: a MESSAGE_UPDATE from the original '
              'author replaces the recipient\'s copy.',
        );

        // React.
        await a.chat.reactToMessage(
          channelId: dmChannel,
          messageId: target.messageId,
          userId: a.userId,
          emoji: '🎯',
          add: true,
        );
        await a.waitForAsync(() async => await a.opCount() == 0);
        await b.waitForAsync(
            () async => (await b.reactionsOf(target.messageId)).isNotEmpty);
        expect(
          await b.reactionsOf(target.messageId),
          contains('${a.userId}:🎯'),
          reason: 'SYNC_PROTOCOL §6a: REACTION_ADD projects onto the '
              "recipient's reactions table under the sender's user_id.",
        );

        // Delete for everyone (skip the undo window — commit directly).
        await a.chat.deleteMessage(
          messageId: target.messageId,
          undoWindow: Duration.zero,
        );
        final committed = await a.chat.commitDelete(
          channelId: dmChannel,
          messageId: target.messageId,
        );
        expect(committed, isTrue,
            reason: 'Decision 11: once the undo window elapses the tombstone '
                'is queued for sync.');
        await a.waitForAsync(() async => await a.opCount() == 0);
        await b.waitForAsync(() async =>
            (await b.store.fetchMessage(target.messageId))?.tombstoned == true);
        expect(
          (await b.store.fetchMessage(target.messageId))?.body,
          isNull,
          reason: 'SPIKE_A_SCHEMA §5.4: an inbound delete tombstones the row '
              'and drops its content on the recipient too.',
        );
      });

      // ---- 8b -----------------------------------------------------------
      // The group flow proper, on its own channel: step 6's group has
      // only A left in it after step 7. Same assertions the emulator
      // drive makes through the UI, minus the widgets.
      test('8b. A creates a group with B and C → both see the full roster',
          () async {
        trioChannelId = await a.chat.createGroup(
          name: 'trio ${_freshUsername()}',
          creatorUserId: a.userId,
          memberUserIds: [b.userId, c.userId],
        );
        await a.waitForAsync(() async => await a.opCount() == 0);
        expect(
          await a.opDebug(trioChannelId),
          contains('<empty>'),
          reason: 'SYNC_PROTOCOL §11.3: POST /v3.0/channels with two members '
              'must be accepted. ${await a.opDebug(trioChannelId)}',
        );

        for (final p in [b, c]) {
          await p.waitForAsync(() async => await p.hasChannel(trioChannelId));
          expect(
            (await p.chat.fetchChannelMembers(trioChannelId))
                .map((m) => m.userId),
            containsAll([a.userId, b.userId, c.userId]),
            reason: 'SYNC_PROTOCOL §10.2 CHANNEL_CREATED: ${p.label} must '
                'materialize the group with the whole roster.',
          );
        }

        // What the group-info screen renders: the creator is the owner.
        final roster = await a.chat.fetchChannelMembers(trioChannelId);
        expect(roster, hasLength(3));
        expect(
          roster.where((m) => m.role == 'owner').map((m) => m.userId),
          [a.userId],
          reason: 'decision 80: the creator is the group owner, and nobody '
              'else is. Roster: '
              '${roster.map((m) => '${m.userId}:${m.role}').toList()}',
        );
      });

      // ---- 8c -----------------------------------------------------------
      test('8c. group messages travel both ways', () async {
        const fromA = 'trio hello from A';
        const fromB = 'trio hello from B';

        expect(
          (await a.sendAndSettle(trioChannelId, fromA))?.state,
          _isAcked,
          reason: 'the owner must be able to send into their own group. '
              '${await a.opDebug(trioChannelId)}',
        );
        for (final p in [b, c]) {
          await p.waitForAsync(
              () async => (await p.bodiesIn(trioChannelId)).contains(fromA));
          expect(await p.bodiesIn(trioChannelId), contains(fromA),
              reason: 'SYNC_PROTOCOL §10.1: every other member receives the '
                  'group message. ${p.label} sees '
                  '${await p.bodiesIn(trioChannelId)}');
        }

        expect(
          (await b.sendAndSettle(trioChannelId, fromB))?.state,
          _isAcked,
          reason: 'a plain member sends into the group too. '
              '${await b.opDebug(trioChannelId)}',
        );
        for (final p in [a, c]) {
          await p.waitForAsync(
              () async => (await p.bodiesIn(trioChannelId)).contains(fromB));
          expect(await p.bodiesIn(trioChannelId), contains(fromB),
              reason: 'the fanout reaches the owner and the third member '
                  'alike. ${p.label} sees '
                  '${await p.bodiesIn(trioChannelId)}');
        }
      });

      // ---- 8d -----------------------------------------------------------
      test('8d. the owner leaves → the server hands the group to a member '
          '(decision 9)', () async {
        await a.chat.leaveGroup(trioChannelId, selfUserId: a.userId);
        await a.waitForAsync(() async => await a.opCount() == 0);
        expect(
          await a.opDebug(trioChannelId),
          contains('<empty>'),
          reason: "decision 80: the owner's leave is DELETE …/members/{self} "
              'like anybody else\'s, not the owner-only hard delete.',
        );
        expect(
          await a.hasChannel(trioChannelId),
          isFalse,
          reason: 'leaveGroup drops the local channel row right away.',
        );

        // Which member inherits depends on the join order the server
        // recorded, so assert the invariant: exactly one owner, and not
        // the user who left.
        for (final p in [b, c]) {
          await p.waitForAsync(() async {
            final owners = (await p.chat.fetchChannelMembers(trioChannelId))
                .where((m) => m.role == 'owner')
                .toList();
            return owners.length == 1 && owners.single.userId != a.userId;
          });
          final roster = await p.chat.fetchChannelMembers(trioChannelId);
          final owners =
              roster.where((m) => m.role == 'owner').map((m) => m.userId);
          expect(
            owners,
            hasLength(1),
            reason: 'decision 9: the group carries on under exactly one new '
                'owner. ${p.label} roster: '
                '${roster.map((m) => '${m.userId}:${m.role}').toList()}',
          );
          expect(owners.single, isNot(a.userId),
              reason: 'decision 9: the successor is a remaining member, '
                  'never the user who left.');
          expect(
            roster.map((m) => m.userId),
            isNot(contains(a.userId)),
            reason: 'CHANNEL_MEMBER_REMOVED must also drop the leaver from '
                "${p.label}'s roster.",
          );
        }
      });

      // ---- 9 ------------------------------------------------------------
      test('9. both log out → session revoked, local store wiped', () async {
        await a.authService.logout();
        await b.authService.logout();
        await b.pump();

        expect(
          [a.authService.isLoggedIn, b.authService.isLoggedIn],
          everyElement(isFalse),
          reason: 'AUTH_CONTRACT §4.6: POST /v3.0/auth/session/revoke plus '
              'the local teardown leaves no accesskey behind.',
        );
        expect(
          await b.counts(),
          {'channels': 0, 'messages': 0, 'contacts': 0},
          reason: 'AUTH_CONTRACT §8: logout destroys the on-device account '
              'state — no channels, messages or contacts survive.',
        );
        // ponytail: only B's store is checked. AuthService.logout reaches
        // the store through the `ChatStore.current` GLOBAL, which
        // `ChatStore.open` overwrites — so in this two-stack process both
        // logouts wipe B's store (the last one opened) and A's is
        // untouched. Harmless in the app (one store per process); if
        // AuthService ever takes the store as a constructor arg, assert
        // both here.
        expect(
          ChatStore.current,
          same(b.store),
          reason: 'If this stops holding, the note above is stale and both '
              'stores can be asserted.',
        );
      });
    },
  );
}

// ---------------------------------------------------------------------------
// One full client stack — the lib/main.dart initializeApp() wiring, minus
// the widgets, pointed at a real server.
// ---------------------------------------------------------------------------

class _Client {
  final String label;
  final Uri baseUrl;
  final String phone;
  final Directory tmpDir;
  final ChatStore store;
  final AuthClient authClient;
  final AuthService authService;
  final WsTransport ws;
  final RestTransport rest;
  final SyncScheduler scheduler;
  final ChatService chat;
  final http.Client _http = http.Client();
  InboundReceiver? inbound;
  late final StreamSubscription<TransportState> _wsStateSub;

  _Client._({
    required this.label,
    required this.baseUrl,
    required this.phone,
    required this.tmpDir,
    required this.store,
    required this.authClient,
    required this.authService,
    required this.ws,
    required this.rest,
    required this.scheduler,
    required this.chat,
  });

  String get userId => authService.currentUserId ?? '';

  static Future<_Client> boot(String url, {required String label}) async {
    final baseUrl = Uri.parse(url);
    final tmpDir =
        await Directory.systemTemp.createTemp('vartalap_real_$label');
    // In-memory, and A and B really do get separate databases:
    // ChatStore.open turns sqflite's singleInstance caching OFF for
    // `:memory:`, without which both stacks in this one process would
    // share one Database and A's close() would shut B's down.
    final store = await ChatStore.open(path: inMemoryDatabasePath);

    final authClient = AuthClient(baseUrl: baseUrl);
    final authService =
        AuthService(client: authClient, storage: _InMemoryStorage());
    await authService.init();

    final wsUrl = baseUrl.replace(
      scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws',
      path: '/wss',
    );
    final ws = WsTransport(endpoint: wsUrl, auth: authClient);
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

    final c = _Client._(
      label: label,
      baseUrl: baseUrl,
      phone: _freshPhone(),
      tmpDir: tmpDir,
      store: store,
      authClient: authClient,
      authService: authService,
      ws: ws,
      rest: rest,
      scheduler: scheduler,
      chat: chat,
    );
    // main.dart App.initState: re-pull on every WS reconnect.
    c._wsStateSub = ws.state.listen((s) {
      if (s == TransportState.connected) unawaited(c.pullPendingSync());
    });
    return c;
  }

  Future<void> shutdown() async {
    await _wsStateSub.cancel();
    await inbound?.stop();
    await scheduler.stop();
    await ws.dispose();
    await rest.dispose();
    await authService.dispose();
    await store.close();
    _http.close();
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  }

  // ---- auth ------------------------------------------------------------

  /// `GET /v3.0/auth/dev/otp?phone=<urlencoded E.164>` — the dev-only
  /// readback that stands in for the SMS the test can't receive.
  Future<String> _devOtpCode() async {
    final uri = baseUrl.resolve(
      '/v3.0/auth/dev/otp?phone=${Uri.encodeQueryComponent(phone)}',
    );
    final resp = await _http.get(uri);
    if (resp.statusCode != 200) {
      throw StateError(
        'dev OTP readback failed for $phone: ${resp.statusCode} ${resp.body}. '
        'The server must run with --expose-dev-otp.',
      );
    }
    return (jsonDecode(resp.body) as Map<String, dynamic>)['code'] as String;
  }

  /// AUTH_CONTRACT §3.1/§3.2 plus the post-login wiring `App.initState`
  /// runs off authStateChange.
  Future<void> login() async {
    await authService.sendOtp(phone);
    await authService.verifyOtp(phone, await _devOtpCode());
    chat.reseedForUser(userId);
    await rebuildInboundReceiverForUser(userId);
    await goOnline();
  }

  Future<void> setUsername(String username) =>
      authService.setUsername(username);

  // ---- connection ------------------------------------------------------

  Future<void> goOnline() async {
    await ws.start();
    await waitFor(() => ws.currentState == TransportState.connected);
    if (ws.currentState != TransportState.connected) {
      throw StateError('$label: WS never reached connected — check that '
          '$baseUrl accepts the accesskey.<key> subprotocol on /wss');
    }
    await pullPendingSync();
    await pump();
  }

  Future<void> goOffline() async {
    await ws.stop();
    await pump();
  }

  /// AppServices.pullPendingSync.
  Future<void> pullPendingSync() async {
    try {
      final envelopes = await rest.pullPendingSync();
      for (final env in envelopes) {
        ws.injectPush(env);
      }
      await inbound?.drainPending();
    } finally {
      ws.endSyncBuffer();
    }
  }

  /// AppServices.rebuildInboundReceiverForUser.
  Future<void> rebuildInboundReceiverForUser(String userIdHex) async {
    final prev = inbound;
    inbound = null;
    chat.bindTypingSource(null);
    await prev?.stop();
    final next = InboundReceiver(
      store: store,
      pushes: ws.pushes,
      localUserId: userIdHex,
    );
    await next.start();
    inbound = next;
    chat.bindTypingSource(next.typingEvents);
  }

  // ---- queries ---------------------------------------------------------

  Future<bool> hasChannel(String channelId) async {
    final rows = await store.db.query(
      'channels',
      columns: const ['channel_id'],
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Message bodies oldest-first. `fetchChannelMessages` is the chat
  /// screen's query, so it comes back newest-first (delivery_sequence
  /// DESC); reversing it gives send order.
  Future<Set<String>> memberIds(String channelId) async {
    final rows = await store.db.query(
      'channel_members',
      columns: const ['user_id'],
      where: 'channel_id = ? AND removed_at IS NULL',
      whereArgs: [channelId],
    );
    return rows.map((r) => r['user_id'] as String).toSet();
  }

  Future<List<String>> bodiesIn(String channelId) async {
    final rows = await store.fetchChannelMessages(channelId);
    return [
      for (final m in rows.reversed)
        if (m.body != null) m.body!
    ];
  }

  Future<List<String>> reactionsOf(String messageId) async {
    final rows = await store.db.query(
      'reactions',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return rows.map((r) => '${r['user_id']}:${r['emoji']}').toList();
  }

  Future<int> opCount() async {
    final r = await store.db.rawQuery('SELECT COUNT(*) c FROM outbound_ops');
    return (r.single['c'] as int?) ?? 0;
  }

  Future<Map<String, int>> counts() async {
    Future<int> count(String table) async {
      final r = await store.db.rawQuery('SELECT COUNT(*) c FROM $table');
      return (r.single['c'] as int?) ?? 0;
    }

    return {
      'channels': await count('channels'),
      'messages': await count('messages'),
      'contacts': await count('contacts'),
    };
  }

  /// The outbound queue for one resource — turns a bare "nothing
  /// arrived" into the server's own reject reason.
  Future<String> opDebug(String resourceId) async {
    final rows = await store.db.query(
      'outbound_ops',
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      orderBy: 'resource_seq',
    );
    final dump = rows
        .map((r) => 'seq=${r['resource_seq']} status=${r['status']} '
            'err=${r['last_error']}')
        .join(' | ');
    return '$label outbound_ops[$resourceId]: '
        '${dump.isEmpty ? '<empty>' : dump}';
  }

  Future<MessageRow?> sendAndSettle(String channelId, String body) async {
    await chat.sendMessage(
      channelId: channelId,
      body: body,
      authorUserId: userId,
    );
    String? messageId;
    await waitForAsync(() async {
      final rows = await store.fetchChannelMessages(channelId);
      final row = rows.where((m) => m.body == body).firstOrNull;
      messageId = row?.messageId;
      return row != null &&
          row.state != MessageState.pending &&
          row.state != MessageState.sending;
    });
    if (messageId == null) return null;
    return store.fetchMessage(messageId!);
  }

  // ---- waiting ---------------------------------------------------------

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 80));

  Future<void> waitFor(bool Function() cond,
      {Duration timeout = budget}) async {
    final sw = Stopwatch()..start();
    while (!cond() && sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> waitForAsync(Future<bool> Function() cond,
      {Duration timeout = budget}) async {
    final sw = Stopwatch()..start();
    while (!(await cond()) && sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// flutter_secure_storage has no platform channel under `flutter test`;
/// same in-memory stand-in the mock-based suites use.
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
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      '_InMemoryStorage.${invocation.memberName} — not implemented for tests',
    );
  }
}
