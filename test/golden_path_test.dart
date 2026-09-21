/// Headless golden path, run against the strict mock server.
///
/// Boots the real service graph the way `lib/main.dart initializeApp()`
/// does — real [ChatStore] on a temp file (WAL path, not `:memory:`),
/// real [WsTransport] / [RestTransport] / [AuthClient] / [SyncScheduler]
/// / [InboundReceiver], the app's own [AuthService] + [ChatService] —
/// and drives it through the nine steps of the v3.0 golden path against
/// `tools/mock_server.dart` in strict mode.
///
/// This test is EXPECTED TO FAIL today. The mock enforces
/// docs/SYNC_PROTOCOL.md and docs/AUTH_CONTRACT.md; the client violates
/// four clauses of them. Each red assertion names the clause. Do not
/// "fix" the test — fix the client.
///
/// Each step is its own `test()` inside one ordered group sharing a
/// single harness, so one red step does not hide the eight others.
library vartalap.golden_path_test;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap_proto/vartalap_proto.dart' as pb;
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_sync/vartalap_sync.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

import '../tools/mock_server.dart';

const String phoneA = '+15550100001';
const String phoneB = '+15550100002';
const String peerPhone = '+10000000000'; // the mock's seed peer
const String usernameA = 'golden_alice';
const String usernameB = 'golden_bob';

/// A real 1x1 PNG, so the mock signs `image/png` and the bytes that
/// come back out of the blob store can be compared to what went in.
final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM'
  'IQAAAABJRU5ErkJggg==',
);

String attachmentChannelId = '';
String attachmentMessageId = '';
const Duration budget = Duration(seconds: 10);

/// A send the server accepted. `sent` OR any later lifecycle state:
/// the mock fans a `MessageStateChanged{DELIVERED}` to the author
/// immediately after the ACK (SYNC_PROTOCOL §10.2, mock_server
/// `_handleWsOp`), and SPIKE_A_SCHEMA §5.1 makes the lifecycle
/// monotonic, so `applyAckSuccess` must not pull the row back down to
/// `sent`. `rejected` is deliberately excluded.
final Matcher isAcked = isIn(const [
  MessageState.sent,
  MessageState.delivered,
  MessageState.read,
]);

late _Harness h;
late String userIdA;
late String peerUserId;
String dmChannelId = '';
String groupChannelId = '';
String peerCreatedChannelId = '';
String extraMemberId = '';
String keyedDmChannelId = '';
String peerMessageId = '';

void main() {
  group('golden path (strict mock)', () {
    setUpAll(() async {
      h = await _Harness.boot();
    });

    tearDownAll(() async {
      await h.shutdown();
    });

    // ---- 1 --------------------------------------------------------------
    test('1. OTP send → verify → logged in', () async {
      await h.login(phoneA);

      expect(
        h.authService.isLoggedIn,
        isTrue,
        reason: 'AUTH_CONTRACT §3.2: a successful otp/verify must leave '
            'AuthService logged in (accesskey + user_id in memory).',
      );
      userIdA = h.authService.currentUserId ?? '';
      expect(
        RegExp(r'^[0-9a-f]{9}$').hasMatch(userIdA),
        isTrue,
        reason: 'AUTH_CONTRACT §2: user_id is exactly 9 lowercase hex '
            'characters (36 bits). Got "$userIdA".',
      );
    });

    // ---- 1b -------------------------------------------------------------
    test('1b. USERNAME_REQUIRED gate blocks channels until username set',
        () async {
      expect(
        h.authService.username,
        isNull,
        reason: 'AUTH_CONTRACT §3.2: otp/verify never picks a username; a '
            'fresh signup comes back with username: null.',
      );

      // Every non-exempt authenticated route is 403 while the handle is
      // unset — contact discovery is the one the picker hits first.
      AuthClientException? blocked;
      try {
        await h.chat.discoverContacts(
          normalizedPhones: const [peerPhone],
          contactBookNamesByPhone: const {peerPhone: 'Seed Peer'},
        );
      } on AuthClientException catch (e) {
        blocked = e;
      }
      expect(
        blocked?.statusCode,
        403,
        reason: 'AUTH_CONTRACT §2.4: every authenticated route except the '
            'users/me + username/check + auth/* exempt list must answer '
            '403 USERNAME_REQUIRED while username is null. Got '
            '${blocked?.statusCode} ${blocked?.errorCode}.',
      );
      expect(blocked?.errorCode, 'USERNAME_REQUIRED');

      // The mandatory step: PATCH /v3.0/users/me. It is on the exempt
      // list, so it works from inside the gate.
      await h.authService.setUsername(usernameA);
      expect(h.authService.username, usernameA);
      final patches = h.mock.requests
          .where((r) => r.method == 'PATCH' && r.path == '/v3.0/users/me')
          .toList();
      expect(
        patches.map((r) => r.body['username']),
        contains(usernameA),
        reason: 'AUTH_CONTRACT §4.5: PATCH /v3.0/users/me is the only path '
            'that writes username.',
      );

      // …and the gate is down.
      final contacts = await h.chat.discoverContacts(
        normalizedPhones: const [peerPhone],
        contactBookNamesByPhone: const {peerPhone: 'Seed Peer'},
      );
      expect(
        contacts,
        isNotEmpty,
        reason: 'AUTH_CONTRACT §2.4: with a username set the gate lifts and '
            'the previously-403 route succeeds.',
      );
    });

    // ---- 2 --------------------------------------------------------------
    test('2. discover peer → start DM → channel kind is one_to_one', () async {
      final contacts = await h.chat.discoverContacts(
        normalizedPhones: const [peerPhone],
        contactBookNamesByPhone: const {peerPhone: 'Seed Peer'},
      );
      peerUserId = h.mock.seedPeer.userId;
      expect(
        contacts.map((c) => c.userId),
        contains(peerUserId),
        reason: 'AUTH_CONTRACT §7.2: POST /v3.0/contacts/lookup must return '
            'the peer for the submitted SHA-256 phone hash.',
      );

      dmChannelId = await h.chat.startDirectMessage(
        localUserId: userIdA,
        peerUserId: peerUserId,
        peerName: 'Seed Peer',
      );
      final local = await h.channelRow(dmChannelId);
      expect(
        local?['kind'],
        'one_to_one',
        reason: 'SYNC_PROTOCOL §11.3: `kind` is "one_to_one" or "group". '
            'ChatService.startDirectMessage writes "${local?['kind']}" into '
            'the local channels row (lib/services/chat_service.dart, '
            'startDirectMessage → createChannel(kind: \'dm\')).',
      );

      await h.waitFor(() => h.channelPosts(dmChannelId).isNotEmpty);
      final posts = h.channelPosts(dmChannelId);
      expect(
        posts,
        isNotEmpty,
        reason: 'SYNC_PROTOCOL §11.3: starting a DM must issue '
            'POST /v3.0/channels.',
      );
      expect(
        posts.first.body['kind'],
        'one_to_one',
        reason: 'SYNC_PROTOCOL §11.3: the server rejects any `kind` outside '
            '{one_to_one, group} with 400 validation_failed. The client sent '
            'kind="${posts.first.body['kind']}" and the mock answered '
            '${posts.first.status}.',
      );
    });

    // ---- 2b -------------------------------------------------------------
    test('2b. find peer by @username (keyed) → contact upserted → DM',
        () async {
      // No key supplied: the handle exists but is gated (§4.5/§7.6).
      AuthClientException? gated;
      try {
        await h.chat.findByUsername(keyedPeerUsername);
      } on AuthClientException catch (e) {
        gated = e;
      }
      expect(
        gated?.errorCode,
        'USERNAME_KEY_REQUIRED',
        reason: 'CONTRACT ADDITION (mock_server._handleGetUserByUsername): a '
            '*missing* key answers 404 USERNAME_KEY_REQUIRED so the picker '
            'knows to show its Key field. Got ${gated?.errorCode}.',
      );

      // Wrong key: indistinguishable from "no such handle" (§7.6).
      AuthClientException? wrong;
      try {
        await h.chat.findByUsername(keyedPeerUsername, key: '0000');
      } on AuthClientException catch (e) {
        wrong = e;
      }
      expect(
        wrong?.errorCode,
        'USER_NOT_FOUND',
        reason: 'AUTH_CONTRACT §7.6: a wrong key MUST NOT be reported '
            'differently from a nonexistent username.',
      );

      final found =
          await h.chat.findByUsername(keyedPeerUsername, key: keyedPeerKey);
      expect(found.userId, keyedPeerUserId);
      expect(found.username, keyedPeerUsername);
      expect(
        found.displayLabel,
        '@$keyedPeerUsername',
        reason: 'AUTH_CONTRACT §2.4: with no contact-book entry the label '
            'is the handle. Never a phone number.',
      );

      final cached = (await h.store.fetchContacts())
          .where((c) => c.userId == keyedPeerUserId)
          .toList();
      expect(
        cached,
        isNotEmpty,
        reason: 'AUTH_CONTRACT §7.6 + §2.2: the client caches the resolved '
            '(username → user_id) pair as a local contact row.',
      );

      keyedDmChannelId = await h.chat.startDirectMessage(
        localUserId: userIdA,
        peerUserId: keyedPeerUserId,
        peerName: found.displayLabel,
      );
      final local = await h.channelRow(keyedDmChannelId);
      expect(local?['kind'], 'one_to_one');
      await h.waitFor(() => h.channelPosts(keyedDmChannelId).isNotEmpty);
      expect(
        h.channelPosts(keyedDmChannelId).firstOrNull?.status,
        201,
        reason: 'SYNC_PROTOCOL §11.3: a username-initiated DM is an ordinary '
            'POST /v3.0/channels once the handle has been resolved.',
      );
    });

    // ---- 3 --------------------------------------------------------------
    test('3. send text → ACK_SUCCESS → message_state=sent, payload is proto',
        () async {
      // Step 2's bug leaves the channel unknown server-side (the create
      // was rejected). Reconcile out of band so this step tests its own
      // clause instead of re-failing on §6a.3 membership.
      h.mock.ensureChannel(
        channelId: dmChannelId,
        kind: 'one_to_one',
        ownerUserId: userIdA,
        members: [userIdA, peerUserId],
        name: 'Seed Peer',
      );

      final msg = await h.sendAndSettle(dmChannelId, 'hello from golden path');

      expect(
        msg?.state,
        isAcked,
        reason: 'SYNC_PROTOCOL §5.3 + §8.1: a WS_OP must be answered '
            'ACK_SUCCESS and the local row promoted pending→sending→sent. '
            'State is ${msg?.state}. ${await h.opDebug(dmChannelId)}',
      );

      final envs = h.mock.envelopes
          .where((e) => e.channelId == dmChannelId)
          .toList();
      expect(
        envs,
        isNotEmpty,
        reason: 'SYNC_PROTOCOL §5.2: the message must reach the server as a '
            'WS_OP envelope.',
      );
      expect(
        _decodesAsChatPayload(envs.last.payload),
        isTrue,
        reason: 'SYNC_PROTOCOL §6a.1 + docs/proto/v3-chat-payload.proto: '
            'Envelope.payload is a ChatPayload protobuf (or a 0x53-prefixed '
            'ServerEventPayload, §10.2). ChatService._encodeChatPayload ships '
            'JSON instead: ${_preview(envs.last.payload)}. Server answered '
            '"${envs.last.rejectReason}".',
      );
    });

    // ---- 4 --------------------------------------------------------------
    test('4. two more messages on the same channel → all ACK_SUCCESS',
        () async {
      final second = await h.sendAndSettle(dmChannelId, 'second message');
      final third = await h.sendAndSettle(dmChannelId, 'third message');

      final seqs = h.mock.envelopes
          .where((e) => e.channelId == dmChannelId)
          .map((e) => '${e.resourceSeq}:${e.rejectReason ?? 'ok'}')
          .join(', ');

      expect(
        [second?.state, third?.state],
        everyElement(isAcked),
        reason: 'SYNC_PROTOCOL §6 (resource_seq per (user_id, resource_id) '
            'starts at 1, increments by exactly 1, never resets) and §6a.3 '
            'step 5 (payload must be a ChatPayload proto) must both hold for '
            'consecutive sends on one channel. Observed rejects for this '
            'channel (seq:outcome): $seqs. ${await h.opDebug(dmChannelId)}. '
            'NOTE: every send here is already rejected on the §6a.3 payload '
            'clause (step 3), which keeps the rejected op rows in '
            'outbound_ops and so hides the §6 breach on this channel. The §6 '
            'breach shows up in step 6, where the group-create op WAS acked: '
            'ChatStore.applyAckSuccess deletes the acked row, ChatService '
            're-derives resource_seq from MAX(resource_seq) over '
            'outbound_ops, the counter falls back to 1 and the server answers '
            'out_of_order.',
      );
    });

    // ---- 5 --------------------------------------------------------------
    test('5. peer inbound → message, chat-list preview, op_id_seen', () async {
      final seen = <List<MessageRow>>[];
      final sub = h.chat.watchMessages(dmChannelId).listen(seen.add);
      addTearDown(sub.cancel);
      await _pump();

      final injected = h.mock.injectPeerMessage(
        channelId: dmChannelId,
        body: 'ping from the peer',
      );
      peerMessageId = injected.messageId;

      await h.waitForAsync(() async =>
          (await h.store.fetchMessage(injected.messageId)) != null);

      expect(
        seen.any((batch) =>
            batch.any((m) => m.messageId == injected.messageId)),
        isTrue,
        reason: 'SYNC_PROTOCOL §10.1: an inbound WS_PUSH must be projected '
            'into messages and surface on watchChannelMessages.',
      );

      final list = await h.store.fetchChannelList();
      final entry =
          list.where((e) => e.channelId == dmChannelId).firstOrNull;
      expect(
        entry?.lastMessagePreview,
        'ping from the peer',
        reason: 'SPIKE_A_SCHEMA §13.1: the chat-list preview must follow the '
            'newest message. Got "${entry?.lastMessagePreview}".',
      );

      expect(
        await h.store.hasSeenOpId(dmChannelId, injected.opId),
        isTrue,
        reason: 'SYNC_PROTOCOL §7.2: the receiver records the applied op_id '
            'in the channel op_id_seen set so a re-fanout is dropped.',
      );
    });

    // ---- 6 --------------------------------------------------------------
    test('6. group create → member added → group message ACK_SUCCESS',
        () async {
      groupChannelId = await h.chat.createGroup(
        name: 'Golden Group',
        creatorUserId: userIdA,
        memberUserIds: [peerUserId],
      );
      await h.waitFor(() => h.channelPosts(groupChannelId).isNotEmpty);
      final post = h.channelPosts(groupChannelId).firstOrNull;
      expect(
        post?.status,
        201,
        reason: 'SYNC_PROTOCOL §11.3: POST /v3.0/channels with kind="group" '
            'and resource_seq=1 must be accepted. Got ${post?.status} '
            '(${post?.body}).',
      );

      // §10.2 ChannelCreated fanout: a channel somebody else created.
      peerCreatedChannelId = 'peer-created-${DateTime.now().millisecondsSinceEpoch}';
      h.mock.ensureChannel(
        channelId: peerCreatedChannelId,
        kind: 'group',
        ownerUserId: peerUserId,
        members: [peerUserId, userIdA],
        name: 'Peer Group',
        announce: true,
      );
      await h.waitForAsync(
          () async => (await h.channelRow(peerCreatedChannelId)) != null);
      expect(
        await h.channelRow(peerCreatedChannelId),
        isNotNull,
        reason: 'SYNC_PROTOCOL §10.2: a ChannelCreated server event '
            '(payload[0]==0x53) must materialize the channel locally.',
      );

      // §10.2 ChannelMemberAdded fanout.
      extraMemberId = h.mock.state.getOrCreateUser('+15550199999').userId;
      h.mock.addChannelMember(groupChannelId, extraMemberId);
      await h.waitForAsync(() async => (await h.store
              .fetchChannelMembers(groupChannelId))
          .any((m) => m.userId == extraMemberId));
      final members = await h.store.fetchChannelMembers(groupChannelId);
      expect(
        members.map((m) => m.userId),
        contains(extraMemberId),
        reason: 'SYNC_PROTOCOL §10.2: a ChannelMemberAdded server event must '
            'be applied to channel_members. Have '
            '${members.map((m) => m.userId).toList()}.',
      );

      final groupMsg = await h.sendAndSettle(groupChannelId, 'group hello');
      final seqs = h.mock.envelopes
          .where((e) => e.channelId == groupChannelId)
          .map((e) => '${e.resourceSeq}:${e.rejectReason ?? 'ok'}')
          .join(', ');
      expect(
        groupMsg?.state,
        isAcked,
        reason: 'SYNC_PROTOCOL §6 + §6a.3: the group-create REST op consumed '
            'resource_seq=1 on this channel and its outbound row was deleted '
            'on ACK_SUCCESS, so ChatService re-derives resource_seq=1 for the '
            'first group message and the server rejects it. '
            'Envelopes (seq:outcome): $seqs. ${await h.opDebug(groupChannelId)}',
      );
    });

    // ---- 7 --------------------------------------------------------------
    test('7. leave group → local tombstone + DELETE /v3.0/channels/{id}',
        () async {
      await h.chat.leaveGroup(groupChannelId);

      expect(
        await h.channelRow(groupChannelId),
        isNull,
        reason: 'SYNC_PROTOCOL §11.3 + chat_service.leaveGroup: leaving a '
            'group drops the local channel row (cascading members/messages) '
            'before the server confirms.',
      );

      await h.waitFor(() => h.mock.requests.any((r) =>
          r.method == 'DELETE' && r.path == '/v3.0/channels/$groupChannelId'));
      final del = h.mock.requests
          .where((r) =>
              r.method == 'DELETE' &&
              r.path == '/v3.0/channels/$groupChannelId')
          .toList();
      expect(
        del,
        isNotEmpty,
        reason: 'SYNC_PROTOCOL §11.3: group leave must issue '
            'DELETE /v3.0/channels/$groupChannelId. Requests seen: '
            '${h.mock.requests.map((r) => '${r.method} ${r.path}').toList()}.',
      );
    });

    // ---- 7b -------------------------------------------------------------
    test('7b. react on the peer message → REACTION_ADD reaches the peer; '
        'a peer reaction lands locally', () async {
      h.peerInbox(); // drop anything queued by earlier steps
      await h.chat.reactToMessage(
        channelId: dmChannelId,
        messageId: peerMessageId,
        userId: userIdA,
        emoji: '\u{1F44D}',
        add: true,
      );
      await h.waitForAsync(() async =>
          (await h.reactionsOf(peerMessageId)).isNotEmpty);
      expect(
        await h.reactionsOf(peerMessageId),
        contains('$userIdA:\u{1F44D}'),
        reason: 'SPIKE_A_SCHEMA §6: a local reaction writes the reactions '
            'row optimistically, same as the inbound path does for a peer.',
      );

      await h.waitFor(() => h.mock.envelopes.any((e) =>
          e.channelId == dmChannelId &&
          _payloadType(e.payload) ==
              pb.ChatPayloadType.TYPE_REACTION_ADD));
      final sent = h.mock.envelopes.lastWhere((e) =>
          _payloadType(e.payload) == pb.ChatPayloadType.TYPE_REACTION_ADD);
      expect(
        sent.rejectReason,
        isNull,
        reason: 'SYNC_PROTOCOL §6a: REACTION_ADD is an ordinary opaque '
            'ChatPayload — the server relays and ACKs it exactly like a '
            'create. Got "${sent.rejectReason}".',
      );
      await h.waitFor(() => h.peerSaw(pb.ChatPayloadType.TYPE_REACTION_ADD,
          messageId: peerMessageId));
      expect(
        h.peerSaw(pb.ChatPayloadType.TYPE_REACTION_ADD,
            messageId: peerMessageId),
        isTrue,
        reason: 'SYNC_PROTOCOL §10.1: the reaction must be fanned out to '
            'the other channel member.',
      );

      // …and the reverse direction.
      h.mock.injectPeerReaction(
        channelId: dmChannelId,
        messageId: peerMessageId,
        emoji: '\u{2764}\u{FE0F}',
      );
      await h.waitForAsync(() async =>
          (await h.reactionsOf(peerMessageId)).length > 1);
      expect(
        await h.reactionsOf(peerMessageId),
        contains('$peerUserId:\u{2764}\u{FE0F}'),
        reason: 'SPIKE_A_SCHEMA §5.4: an inbound TYPE_REACTION_ADD is '
            'applied to the reactions table.',
      );

      // Toggling our own reaction off removes the row and sends REMOVE.
      await h.chat.reactToMessage(
        channelId: dmChannelId,
        messageId: peerMessageId,
        userId: userIdA,
        emoji: '\u{1F44D}',
        add: false,
      );
      await h.waitForAsync(() async => !(await h.reactionsOf(peerMessageId))
          .contains('$userIdA:\u{1F44D}'));
      expect(
        await h.reactionsOf(peerMessageId),
        isNot(contains('$userIdA:\u{1F44D}')),
        reason: 'Toggling an existing own-reaction is a REACTION_REMOVE, '
            'not a second add.',
      );
    });

    // ---- 7c -------------------------------------------------------------
    test('7c. edit own message → MESSAGE_UPDATE reaches the peer, row is '
        'marked edited', () async {
      h.peerInbox();
      final original = await h.sendAndSettle(dmChannelId, 'draft text');
      expect(original?.state, isAcked);

      await h.chat.editMessage(
        channelId: dmChannelId,
        messageId: original!.messageId,
        newBody: 'corrected text',
      );
      await h.waitForAsync(() async =>
          (await h.store.fetchMessage(original.messageId))?.body ==
          'corrected text');

      final edited = await h.store.fetchMessage(original.messageId);
      expect(edited?.body, 'corrected text');
      expect(
        edited?.isEdited,
        isTrue,
        reason: 'docs/proto/v3-chat-payload.proto TYPE_MESSAGE_UPDATE: the '
            'edit is marked so every client can render the "edited" label.',
      );
      expect(
        edited?.deliverySequence,
        original.deliverySequence,
        reason: "An edit must not restamp its target's delivery_sequence — "
            'that would move the message in the channel ordering.',
      );

      await h.waitFor(() => h.peerSaw(
            pb.ChatPayloadType.TYPE_MESSAGE_UPDATE,
            messageId: original.messageId,
          ));
      expect(
        h.peerSaw(pb.ChatPayloadType.TYPE_MESSAGE_UPDATE,
            messageId: original.messageId, body: 'corrected text'),
        isTrue,
        reason: 'SYNC_PROTOCOL §6a: the peer receives the UPDATE verbatim '
            'and applies it because we are the author (§6a.3).',
      );

      // Inbound edit of the peer's own message (§6a.3 authorship holds).
      h.mock.injectPeerEdit(
        channelId: dmChannelId,
        messageId: peerMessageId,
        body: 'ping from the peer (fixed)',
      );
      await h.waitForAsync(() async =>
          (await h.store.fetchMessage(peerMessageId))?.body ==
          'ping from the peer (fixed)');
      expect(
        (await h.store.fetchMessage(peerMessageId))?.isEdited,
        isTrue,
        reason: 'SPIKE_A_SCHEMA §5.4: an inbound update from the author is '
            'applied and flagged.',
      );
    });

    // ---- 7d -------------------------------------------------------------
    test('7d. delete own: undo inside the window sends nothing; letting it '
        'elapse sends MESSAGE_DELETE', () async {
      h.peerInbox();
      final undone = await h.sendAndSettle(dmChannelId, 'deleted then undone');
      final opsBefore = await h.opCount();

      await h.chat.deleteMessage(messageId: undone!.messageId);
      expect(
        (await h.store.fetchMessage(undone.messageId))?.tombstoned,
        isTrue,
        reason: 'V3_ARCHITECTURE decision 11: delete commits locally as a '
            'tombstone immediately.',
      );
      await h.chat.undoDelete(undone.messageId);
      final restored = await h.store.fetchMessage(undone.messageId);
      expect(restored?.tombstoned, isFalse);
      expect(restored?.body, 'deleted then undone');
      expect(
        await h.opCount(),
        opsBefore,
        reason: 'Decision 11: an Undo inside the 5s window must enqueue no '
            'outbound op at all.',
      );

      // Now the same thing, committed.
      final gone = await h.sendAndSettle(dmChannelId, 'deleted for real');
      await h.chat.deleteMessage(
        messageId: gone!.messageId,
        undoWindow: Duration.zero,
      );
      final committed = await h.chat.commitDelete(
        channelId: dmChannelId,
        messageId: gone.messageId,
      );
      expect(committed, isTrue);
      await h.waitFor(() => h.peerSaw(pb.ChatPayloadType.TYPE_MESSAGE_DELETE,
          messageId: gone.messageId));
      expect(
        h.peerSaw(pb.ChatPayloadType.TYPE_MESSAGE_DELETE,
            messageId: gone.messageId),
        isTrue,
        reason: 'Decision 11: once the window elapses the tombstone is '
            'queued for sync and the peer tombstones its copy too.',
      );
      // The ACK clears the body — the deleted content does not linger.
      await h.waitForAsync(() async =>
          (await h.store.fetchMessage(gone.messageId))?.body == null);
      expect((await h.store.fetchMessage(gone.messageId))?.tombstoned, isTrue);

      // Inbound delete of the peer's own message.
      h.mock.injectPeerDelete(
        channelId: dmChannelId,
        messageId: peerMessageId,
      );
      await h.waitForAsync(() async =>
          (await h.store.fetchMessage(peerMessageId))?.tombstoned == true);
      expect(
        (await h.store.fetchMessage(peerMessageId))?.body,
        isNull,
        reason: 'SPIKE_A_SCHEMA §5.4: an inbound delete tombstones the row '
            'and drops its content.',
      );
    });

    // ---- 7e -------------------------------------------------------------
    test('7e. forced permanent reject → failure surfaces on watchFailures, '
        'manualRetry re-sends and the message lands', () async {
      h.peerInbox();
      h.mock.rejectNextChatOps = 1;

      final failures = <List<OutboundOpRow>>[];
      final sub = h.chat.watchFailures().listen(failures.add);
      addTearDown(sub.cancel);

      final doomed = await h.sendAndSettle(dmChannelId, 'rejected once');
      expect(
        doomed?.state,
        MessageState.rejected,
        reason: 'SPIKE_B_SYNC.md §8: an ACK_PERMANENT rolls the optimistic '
            'projection back to `rejected` so the bubble can offer Retry.',
      );

      await h.waitFor(() => failures.isNotEmpty && failures.last.isNotEmpty);
      final failed = failures.last
          .where((o) => o.targetMessageId == doomed!.messageId)
          .toList();
      expect(
        failed,
        isNotEmpty,
        reason: 'SPIKE_B_SYNC.md §10: the terminal op must surface on '
            'watchFailures so the UI can attach a Retry to that bubble.',
      );
      expect(failed.single.status, OpStatus.rejected);

      await h.chat.retryFailedOp(failed.single.opId);
      await h.waitForAsync(() async {
        final m = await h.store.fetchMessage(doomed!.messageId);
        return m != null &&
            m.state != MessageState.pending &&
            m.state != MessageState.sending &&
            m.state != MessageState.rejected;
      });
      expect(
        (await h.store.fetchMessage(doomed!.messageId))?.state,
        isAcked,
        reason: 'SPIKE_B_SYNC.md §10: manualRetry clones the failed op under '
            'a fresh op_id and the message completes. '
            '${await h.opDebug(dmChannelId)}',
      );
      await h.waitFor(() => h.peerSaw(pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
          body: 'rejected once'));
      expect(
        h.peerInboxSeen
            .where((p) => p.body == 'rejected once')
            .length,
        1,
        reason: 'SPIKE_B_SYNC.md §10: the rejected op never reached the '
            'peer, and the retry reaches it exactly once.',
      );
    });

    // ---- 7f -------------------------------------------------------------
    test('7f. read receipt + typing ride the ChatPayload schema; a '
        'client-authored 0x53 is refused (decision 56)', () async {
      h.peerInbox();

      // Step 7d tombstoned the only peer message, so seed a live one —
      // markRead's marker is the newest NON-tombstoned peer message.
      final unread = h.mock.injectPeerMessage(
        channelId: dmChannelId,
        body: 'read this',
      );
      await h.waitForAsync(
          () async => await h.store.fetchMessage(unread.messageId) != null);

      // Outbound receipt: a normal WS op naming the newest peer message.
      await h.chat.markRead(dmChannelId);
      await h.waitFor(() => h.peerSaw(pb.ChatPayloadType.TYPE_READ_RECEIPT,
          messageId: unread.messageId));
      expect(
        h.peerSaw(pb.ChatPayloadType.TYPE_READ_RECEIPT,
            messageId: unread.messageId),
        isTrue,
        reason: 'Decision 56: markRead enqueues a '
            'ChatPayload{TYPE_READ_RECEIPT} naming the read-up-to message, '
            'and the server fans it to the channel like any other op.',
      );
      expect(
        h.mock.envelopes.where((e) =>
            e.rejectReason != null && e.rejectReason != 'forced_reject'),
        isEmpty,
        reason: 'Decision 56: the receipt rides the normal op path, so it '
            'passes §6a.3 step 5 and consumes a resource_seq like any '
            'other op.',
      );

      // Inbound receipt is read-UP-TO: both of these flip, not just the
      // one the marker names.
      final older = await h.sendAndSettle(dmChannelId, 'read me 1');
      final newer = await h.sendAndSettle(dmChannelId, 'read me 2');
      h.mock.injectPeerReadReceipt(
        channelId: dmChannelId,
        messageId: newer!.messageId,
      );
      await h.waitForAsync(() async =>
          (await h.store.fetchMessage(older!.messageId))?.state ==
          MessageState.read);
      expect(
        [
          (await h.store.fetchMessage(older!.messageId))?.state,
          (await h.store.fetchMessage(newer.messageId))?.state,
        ],
        everyElement(MessageState.read),
        reason: 'v3-chat-payload.proto: message_id on a TYPE_READ_RECEIPT '
            'is a read-up-to marker, and the §6a.3 authorship gate limits '
            'the flip to the local user\'s own rows.',
      );

      // Outbound typing: an ephemeral ChatPayload, never a 0x53 forgery.
      h.chat.notifyTyping(channelId: dmChannelId, isTyping: true);
      await h.waitFor(() => h.mock.ephemeralEnvelopes.isNotEmpty);
      final typed = pb.ChatPayload.fromBuffer(
          h.mock.ephemeralEnvelopes.last.payload);
      expect(
        [typed.type, typed.isTyping],
        [pb.ChatPayloadType.TYPE_TYPING, true],
        reason: 'Decision 56: typing is a ChatPayload on an '
            'ephemeral=true envelope, not a client-authored Typing event.',
      );

      // Inbound typing reaches the UI side-channel.
      final typings = <TypingEvent>[];
      final typingSub = h.chat.typingEvents.listen(typings.add);
      addTearDown(typingSub.cancel);
      await _pump();
      h.mock.injectPeerTyping(channelId: dmChannelId, isTyping: true);
      await h.waitFor(() =>
          typings.any((t) => t.channelId == dmChannelId && t.isTyping));
      expect(
        typings.map((t) => '${t.userId}:${t.isTyping}'),
        contains('$peerUserId:true'),
        reason: 'InboundReceiver must decode a ChatPayload{TYPE_TYPING} on '
            'an ephemeral envelope onto the typing side-channel.',
      );

      // And the forged server event the gateway refuses (§10.2).
      final forgedOpId = Uuid7Gen(userIdBits: Uuid7Gen.parseUserIdHex(userIdA))
          .next(nowMs: DateTime.now().millisecondsSinceEpoch);
      h.ws.sendEphemeral(
        opId: forgedOpId,
        channelId: dmChannelId,
        payload: Uint8List.fromList([
          0x53,
          ...pb.ServerEventPayload(
            version: 1,
            type: pb.ServerEventType.TYPING,
            typing: pb.Typing(isTyping: true),
          ).writeToBuffer(),
        ]),
      );
      await h.waitFor(() => h.mock.envelopes.any((e) => e.opId == forgedOpId));
      expect(
        h.mock.envelopes
            .firstWhere((e) => e.opId == forgedOpId)
            .rejectReason,
        'validation_failed',
        reason: 'SYNC_PROTOCOL §10.2 / decision 56: server events are '
            'server-authored. A client payload starting 0x53 is refused.',
      );
    });

    // ---- 8 --------------------------------------------------------------
    test('8. logout wipes the local store', () async {
      await h.authService.logout();
      await _pump();

      final counts = await h.counts();
      expect(
        counts,
        {'channels': 0, 'messages': 0, 'contacts': 0},
        reason: 'AUTH_CONTRACT §8: logout destroys the local account state — '
            'the on-device store must hold no channels, messages or contacts '
            'for the signed-out account. AuthService.logout only clears '
            'secure storage (lib/services/auth_service.dart), the ChatStore '
            'is left intact. Got $counts.',
      );
    });

    // ---- 9 --------------------------------------------------------------
    test('9. login as a different phone → store still empty, new user_id',
        () async {
      await h.login(phoneB);
      final userIdB = h.authService.currentUserId ?? '';

      expect(
        userIdB,
        isNot(userIdA),
        reason: 'AUTH_CONTRACT §2: a different phone maps to a different '
            'user_id.',
      );
      final counts = await h.counts();
      expect(
        counts,
        {'channels': 0, 'messages': 0, 'contacts': 0},
        reason: 'AUTH_CONTRACT §8: a second account must never see the first '
            "account's data. The store still holds $counts from $userIdA.",
      );
    });

    // ---- 10 -------------------------------------------------------------
    test('10. send an image attachment → upload op ACKs → MESSAGE_CREATE '
        'carries the fileId → peer receives it and can resolve a download',
        () async {
      // No platform channel for path_provider under `flutter test`.
      AssetCache.dirProvider =
          () async => Directory('${h.tmpDir.path}/assets');
      await h.authService.setUsername(usernameB);
      final userId = h.authService.currentUserId!;
      await h.chat.discoverContacts(
        normalizedPhones: const [peerPhone],
        contactBookNamesByPhone: const {peerPhone: 'Seed Peer'},
      );
      peerUserId = h.mock.seedPeer.userId;
      attachmentChannelId = await h.chat.startDirectMessage(
        localUserId: userId,
        peerUserId: peerUserId,
        peerName: 'Seed Peer',
      );
      await h.waitFor(() => h.channelPosts(attachmentChannelId).isNotEmpty);

      final picked = File('${h.tmpDir.path}/holiday.png')
        ..writeAsBytesSync(onePixelPng);
      attachmentMessageId = await h.chat.sendAttachment(
        channelId: attachmentChannelId,
        authorUserId: userId,
        path: picked.path,
        width: 1,
        height: 1,
      );

      // One op at first — the upload. The MESSAGE_CREATE cannot exist
      // until media-ms has minted a fileId.
      await h.waitForAsync(() async {
        final m = await h.store.fetchMessage(attachmentMessageId);
        return m != null &&
            m.state != MessageState.pending &&
            m.state != MessageState.sending;
      });
      final row = await h.store.fetchMessage(attachmentMessageId);
      expect(
        row?.state,
        isAcked,
        reason: 'V3_RELEASE_PLAN §4.2: presign → PUT → status → '
            'MESSAGE_CREATE, all through the outbound queue. '
            '${await h.opDebug(attachmentChannelId)}',
      );

      final stored =
          pb.ChatPayload.fromBuffer(row!.attachments!).attachments.single;
      expect(
        stored.url,
        isNot(picked.path),
        reason: 'Once the upload ACKs the local path is replaced by the '
            'media-ms fileId — that is what the peer can resolve.',
      );
      expect(stored.mimeType, 'image/png');
      expect(stored.sizeBytes.toInt(), onePixelPng.length);
      expect(
        h.mock.assets.containsKey(stored.url),
        isTrue,
        reason: 'The fileId in the message must be one media-ms actually '
            'issued (decision 36).',
      );

      // The peer's copy carries the same fileId.
      await h.waitFor(() => h.peerSaw(
            pb.ChatPayloadType.TYPE_MESSAGE_CREATE,
            messageId: attachmentMessageId,
          ));
      final seen = h.peerInboxSeen
          .where((p) => p.messageId == attachmentMessageId)
          .single;
      expect(
        seen.attachments.single.url,
        stored.url,
        reason: 'SYNC_PROTOCOL §6a.1: the recipient gets the same '
            'Attachment the sender stored.',
      );

      // …and resolving it yields the bytes that went up. The seed peer
      // has no client in this harness, so we exercise the same
      // authenticated presign-download the peer would.
      final assetClient = AssetClient(
        baseUrl: h.mock.apiUrl,
        auth: h.authClient,
      );
      final url = await assetClient.downloadUrl(seen.attachments.single.url);
      expect(url, startsWith('http'));
      expect(
        await assetClient.download(url),
        onePixelPng,
        reason: 'The presigned GET returns exactly the bytes the presigned '
            'PUT accepted.',
      );
      assetClient.dispose();
    });

    // ---- 11 -------------------------------------------------------------
    test('11. set profile photo → PATCH /v3.0/users/me → ProfileEdited '
        'fanout carries the avatarUrl', () async {
      final picked = File('${h.tmpDir.path}/me.png')
        ..writeAsBytesSync(onePixelPng);
      final edits = <pb.ProfileEdited>[];

      await h.chat.setOwnAvatar(picked.path);
      await h.waitFor(() {
        edits.addAll(_peerProfileEdits(h));
        return edits.any((e) => e.avatarUrl.isNotEmpty);
      });

      final patch = h.mock.requests
          .where((r) =>
              r.method == 'PATCH' &&
              r.path == '/v3.0/users/me' &&
              r.body.containsKey('avatarUrl'))
          .lastOrNull;
      expect(
        patch,
        isNotNull,
        reason: 'V3_RELEASE_PLAN §4.2 / AUTH_CONTRACT §4.5: the photo is '
            'set by PATCH /v3.0/users/me {avatarUrl}, enqueued as an '
            'ordinary REST op once the upload ACKs.',
      );
      final fileId = patch!.body['avatarUrl'] as String;
      expect(
        fileId,
        isNot(picked.path),
        reason: 'The server is told the fileId, never a path on our disk.',
      );
      expect(h.mock.assets.containsKey(fileId), isTrue);
      expect(
        await h.chat.ownAvatarUrl(),
        anyOf(isNull, fileId),
        reason: 'The local pointer follows the upload (null only where '
            'shared_preferences has no platform channel).',
      );
      expect(
        edits.map((e) => e.avatarUrl),
        contains(fileId),
        reason: 'SYNC_PROTOCOL §10.2: every user sharing a channel with the '
            'editor gets a ProfileEdited carrying the new avatarUrl.',
      );
    });

    // ---- 12 -------------------------------------------------------------
    test('12. push: the ntfy endpoint reaches POST /v3.0/push/topic and '
        'round-trips out of storage', () async {
      // AUTH_CONTRACT §2.4: push/topic sits behind the USERNAME_REQUIRED
      // gate, so the handle comes first — same order the app uses
      // (main.dart registers off usernameChange).
      await h.authService.setUsername('golden_bob');

      final storage = _InMemoryStorage();
      final distributor = _FakeDistributor();
      final push = PushService(
        authClient: h.authClient,
        unifiedPush: distributor,
        storage: storage,
        notifyWake: () async {},
        requestPermission: () async {},
      );
      await push.start();

      const endpoint = 'https://ntfy.example/u/goldenpath32chars';
      await distributor.emitEndpoint(endpoint);
      // The distributor callback is fire-and-forget (`void Function`),
      // so the POST it kicks off settles on its own schedule.
      await h.waitFor(() => push.state.value == PushState.registered);

      final posts = h.mock.requests
          .where((r) => r.method == 'POST' && r.path == '/v3.0/push/topic')
          .toList();
      expect(
        posts.map((r) => r.body['topicUrl']),
        [endpoint],
        reason: 'AUTH_CONTRACT §5.1: the endpoint the distributor hands the '
            'client is posted verbatim as topicUrl.',
      );
      expect(posts.single.status, 200);
      expect(push.state.value, PushState.registered);

      // Survives a restart: a fresh service on the same storage finds
      // the endpoint and does not re-post it.
      final restarted = PushService(
        authClient: h.authClient,
        unifiedPush: _FakeDistributor(),
        storage: storage,
        notifyWake: () async {},
        requestPermission: () async {},
      );
      await restarted.start();
      expect(restarted.endpoint, endpoint);
      expect(restarted.state.value, PushState.registered);
      expect(
        h.mock.requests
            .where((r) => r.path == '/v3.0/push/topic')
            .length,
        1,
        reason: 'the stored endpoint is already registered for this user',
      );

      // AUTH_CONTRACT §5.1: null deregisters, and the mock validates it
      // the way notification-ms does.
      await push.deregister();
      final last = h.mock.requests
          .lastWhere((r) => r.path == '/v3.0/push/topic');
      expect(last.body['topicUrl'], isNull);
      expect(last.status, 200);

      push.dispose();
      restarted.dispose();
    });
  });
}

/// Server-authored §10.2 events queued for the seed peer. Drains, like
/// [_Harness.peerInbox], and keeps only the profile edits.
List<pb.ProfileEdited> _peerProfileEdits(_Harness h) {
  final out = <pb.ProfileEdited>[];
  for (final frame in h.mock.state.drainUndelivered(peerUserId)) {
    try {
      final env = pb.WsEnvelope.fromBuffer(frame);
      if (env.type != pb.WsType.WS_PUSH) continue;
      final payload = env.push.payload;
      if (payload.isEmpty || payload[0] != 0x53) continue;
      final sep = pb.ServerEventPayload.fromBuffer(payload.sublist(1));
      if (sep.type == pb.ServerEventType.PROFILE_EDITED) {
        out.add(sep.profileEdited);
      }
    } catch (_) {
      // Not a server event — not our business here.
    }
  }
  return out;
}

/// The ntfy app, minus Android. `PushService` only ever asks it for the
/// distributor list and a registration; the endpoint arrives on the
/// callback, which the test fires by hand.
class _FakeDistributor implements UnifiedPushApi {
  void Function(String)? _onNewEndpoint;

  @override
  Future<void> initialize({
    required void Function(String endpointUrl) onNewEndpoint,
    required void Function() onUnregistered,
    required void Function() onMessage,
    required void Function(String reason) onRegistrationFailed,
  }) async {
    _onNewEndpoint = onNewEndpoint;
  }

  @override
  Future<List<String>> getDistributors() async => [kNtfyDistributorPackage];

  @override
  Future<void> saveDistributor(String distributor) async {}

  @override
  Future<void> register() async {}

  @override
  Future<void> unregister() async {}

  Future<void> emitEndpoint(String url) async {
    _onNewEndpoint!(url);
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Harness — the lib/main.dart initializeApp() wiring, minus the widgets.
// ---------------------------------------------------------------------------

class _Harness {
  final MockServer mock;
  final Directory tmpDir;
  final ChatStore store;
  final AuthClient authClient;
  final AuthService authService;
  final WsTransport ws;
  final RestTransport rest;
  final SyncScheduler scheduler;
  final ChatService chat;
  InboundReceiver? inbound;
  late final StreamSubscription<TransportState> _wsStateSub;

  _Harness._({
    required this.mock,
    required this.tmpDir,
    required this.store,
    required this.authClient,
    required this.authService,
    required this.ws,
    required this.rest,
    required this.scheduler,
    required this.chat,
  });

  static Future<_Harness> boot() async {
    final mock = await MockServer.start(); // strict: true, seed peer on
    final tmpDir = await Directory.systemTemp.createTemp('vartalap_golden');
    // Real file path, not inMemoryDatabasePath — we want the WAL pragmas
    // in ChatStore.open to be exercised.
    final store = await ChatStore.open(path: '${tmpDir.path}/vartalap_v3.db');

    final authClient = AuthClient(baseUrl: mock.apiUrl);
    final authService =
        AuthService(client: authClient, storage: _InMemoryStorage());
    await authService.init();

    final ws = WsTransport(endpoint: mock.wsUrl, auth: authClient);
    final rest = RestTransport(baseUrl: mock.apiUrl, auth: authClient);

    final scheduler = SyncScheduler(
      store: store,
      wsTransport: ws,
      restTransport: rest,
      backoff: const FixedBackoff(Duration(milliseconds: 50)),
      clock: Clock.system,
    );
    await scheduler.start();
    await ws.start(); // no accesskey yet → stays disconnected

    final chat = ChatService(
      store: store,
      scheduler: scheduler,
      authClient: authClient,
      wsTransport: ws,
      uuidGen: Uuid7Gen(userIdBits: 0),
      clock: Clock.system,
    );

    final h = _Harness._(
      mock: mock,
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
    h._wsStateSub = ws.state.listen((s) {
      if (s == TransportState.connected) unawaited(h.pullPendingSync());
    });
    return h;
  }

  Future<void> shutdown() async {
    await _wsStateSub.cancel();
    await inbound?.stop();
    await scheduler.stop();
    await ws.dispose();
    await rest.dispose();
    await authService.dispose();
    await store.close();
    await mock.stop();
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
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

  /// AUTH_CONTRACT §3.1/§3.2 plus the post-login wiring `App.initState`
  /// runs off authStateChange (reseed op_id bits, rebuild the receiver,
  /// connect the WS, pull the queue).
  Future<void> login(String phone) async {
    await authService.sendOtp(phone);
    await authService.verifyOtp(phone, mock.sendOtpCodeFor(phone));
    final userId = authService.currentUserId!;
    chat.reseedForUser(userId);
    await rebuildInboundReceiverForUser(userId);
    await ws.start();
    await waitFor(() => ws.currentState == TransportState.connected);
    await pullPendingSync();
    await _pump();
  }

  // ---- queries ---------------------------------------------------------

  Future<Map<String, Object?>?> channelRow(String channelId) async {
    final rows = await store.db.query(
      'channels',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
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

  /// Everything the mock has queued for the seed peer since the last
  /// call, decoded to ChatPayloads. The peer has no client in this
  /// harness, so its fanout lands on the undelivered queue — which is
  /// exactly the "did the other side get it" question.
  final List<pb.ChatPayload> peerInboxSeen = [];

  /// Drain first, then look: the undelivered queue only fills as the
  /// server processes ops, so a poll that doesn't drain never sees them.
  bool peerSaw(
    pb.ChatPayloadType type, {
    String? messageId,
    String? body,
  }) {
    peerInbox();
    return peerInboxSeen.any((p) =>
        p.type == type &&
        (messageId == null || p.messageId == messageId) &&
        (body == null || p.body == body));
  }

  List<pb.ChatPayload> peerInbox() {
    final out = <pb.ChatPayload>[];
    for (final frame in mock.state.drainUndelivered(peerUserId)) {
      try {
        final env = pb.WsEnvelope.fromBuffer(frame);
        if (env.type != pb.WsType.WS_PUSH) continue;
        final payload = env.push.payload;
        if (payload.isEmpty || payload[0] == 0x53) continue;
        out.add(pb.ChatPayload.fromBuffer(payload));
      } catch (_) {
        // Not a chat payload — not our business here.
      }
    }
    peerInboxSeen.addAll(out);
    return out;
  }

  /// `user_id:emoji` for every reaction on [messageId].
  Future<List<String>> reactionsOf(String messageId) async {
    final rows = await store.db.query(
      'reactions',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return rows
        .map((r) => '${r['user_id']}:${r['emoji']}')
        .toList();
  }

  Future<int> opCount() async {
    final r = await store.db.rawQuery('SELECT COUNT(*) c FROM outbound_ops');
    return (r.single['c'] as int?) ?? 0;
  }

  List<RecordedRequest> channelPosts(String channelId) => mock.requests
      .where((r) =>
          r.method == 'POST' &&
          r.path == '/v3.0/channels' &&
          r.body['channel_id'] == channelId)
      .toList();

  /// Dump the outbound queue for a resource — the detail that turns a
  /// bare "expected sent, got rejected" into a named contract breach.
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
    return 'outbound_ops[$resourceId]: ${dump.isEmpty ? '<empty>' : dump}';
  }

  /// Send [body] and wait until the optimistic row leaves
  /// pending/sending (ACK or reject). Sequential by design: the
  /// scheduler is per-resource serial and a permanent reject cascades
  /// onto every later-sequenced op on the same resource.
  Future<MessageRow?> sendAndSettle(String channelId, String body) async {
    await chat.sendMessage(
      channelId: channelId,
      body: body,
      authorUserId: authService.currentUserId!,
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

  /// Poll [cond] until true or [timeout]. Never throws — the caller's
  /// `expect` produces the failure message, so the spec reference stays
  /// attached to the assertion.
  Future<void> waitFor(bool Function() cond,
      {Duration timeout = budget}) async {
    final sw = Stopwatch()..start();
    while (!cond() && sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> waitForAsync(Future<bool> Function() cond,
      {Duration timeout = budget}) async {
    final sw = Stopwatch()..start();
    while (!(await cond()) && sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 50));

/// The ChatPayload type of an envelope payload, or null when the bytes
/// are a §10.2 server event / not a ChatPayload at all.
pb.ChatPayloadType? _payloadType(List<int> payload) {
  if (payload.isEmpty || payload[0] == 0x53) return null;
  try {
    return pb.ChatPayload.fromBuffer(payload).type;
  } catch (_) {
    return null;
  }
}

bool _decodesAsChatPayload(List<int> payload) {
  if (payload.isEmpty) return false;
  if (payload[0] == 0x53) return true; // §10.2 server event
  try {
    return pb.ChatPayload.fromBuffer(payload).type !=
        pb.ChatPayloadType.TYPE_UNSPECIFIED;
  } catch (_) {
    return false;
  }
}

String _preview(List<int> payload) {
  try {
    return '"${utf8.decode(payload)}"';
  } catch (_) {
    return '${payload.length} opaque bytes';
  }
}

/// flutter_secure_storage has no platform channel under `flutter test`;
/// same in-memory stand-in the existing auth_service_test uses.
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
