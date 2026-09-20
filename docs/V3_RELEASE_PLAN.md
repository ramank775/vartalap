# Vartalap v3.0 — Release Plan

Status: **proposed, 2026-09-20**. Supersedes the roadmap section of
`V3_ARCHITECTURE.md` (decisions there still stand). `V3_TODOS.md` remains
the server ledger; this doc is the ordered plan to a shippable 3.0.

Goal: **feature-complete v3.0**. Nothing in the shipped UI is a stub. Every
row in the feature matrix below is either working end-to-end against the
real chat-server, or absent from the UI.

---

## 1. Where things stand (review, 2026-09-20)

### Client (`vartalap`, branch `feat/v3-foundation`)

Keep it. Do not restart `lib/`.

- 38 commits, April 2026. `flutter analyze` clean on Flutter 3.41.9.
- Tests: app 28/29, store 11/11, transport 21/21, sync 16/17. Both
  failures are stale assertions, not logic bugs
  (`test/screens/settings_screen_test.dart:50`,
  `packages/vartalap_sync/test/inbound_receiver_test.dart:52`).
- Live app code is ~7.2k lines, Material 3, stream-driven, consistent.
  ~2.2k lines (24 files) are v2 leftovers with no importer.
- Packages (`vartalap_store`, `vartalap_sync`, `vartalap_transport`,
  `vartalap_proto`) are spec-traceable and hold the meaningful tests.
- Everything works only against `tools/mock_server.dart`. The mock is
  lenient; four contract-drift bugs are masked by it (§3.1 below).
- A rewrite would reproduce the same screens against the same package
  API. Cost of keeping: 2 sessions of purge and seam fixes.

### Server (`chat-server`, branch `release/v3.x`)

This is the critical path. It implements **none** of the v3 contract.

- `release/v3.x` = v2.8 + `rewrite /v3.0/(.*) /$1` in nginx + PUT
  profile/channel endpoints (Mar 2026).
- Still Firebase: `firebase-auth-provider.js`, `firebase-pn-service.js`,
  `firebase-admin` dep. `AUTH_PROVIDER=mock` is the only non-Firebase path.
- Wire proto is v2 `Message` (`proto/event-args.proto`), not `WsEnvelope`.
- No OTP, no refresh tokens, no `user_id`, no username, no push topic,
  no op_id dedup, no per-resource seq, no undelivered-queue TTL, no
  ServerEventPayload fanout, no `/sync/pending`.
- Zero automated tests in the repo.
- `AUTH_CONTRACT.md` claims to mirror a chat-server copy. No branch of
  chat-server contains it. The client `docs/` copy is the only one.

### Spec

`SYNC_PROTOCOL.md` and `AUTH_CONTRACT.md` are good enough to build a
server from, with three gaps to close first (§2.2).

---

## 2. Phase 0 — Clean the foundation (client, 2 sessions)

**Status: done 2026-09-20.** Purge, spec gaps, four seam bugs, stream
hoist, strict mock (`tools/mock_server.dart`, `MockServer.start()`) and
`test/golden_path_test.dart` (9/9). Analyze clean; app 37, store 11,
sync 17, transport 21 tests green. Not yet committed. Left as-is: the
canonical-copy move of the contracts into chat-server (do it when
Phase 1 starts), and `feat/migration-api-path` deletion (owner's call).

Exit gate: `flutter analyze` clean, all suites green, app boots against
the mock with no behaviour change.

### 2.1 Purge

- Delete the 24 unreachable files: all of `lib/models/`, dead widgets
  (`message.dart`, `message_input.dart`, `rich_message.dart`,
  `chat_preview.dart`, `contact.dart`, `contactPreviewItem.dart`,
  `keyboard.dart`, `loadingIndicator.dart`, `avator_letter.dart`,
  `profile_img.dart`, `notifier/`), dead utils (`chat_message_helper`,
  `dateTimeFormat`, `enum_helper`, `find`, `remote_message_helper`),
  `screens/contact_info/`, `services/crashlystics.dart`,
  `services/performance_metric.dart`, `test/widget_test.dart`.
- Drop unused deps: `sqflite`, `connectivity_plus` (until §4.6 wires it),
  `flutter_local_notifications`, `share_plus`, `bubble`,
  `emoji_picker_flutter`.
- `pubspec.yaml`: version `3.0.0+80`, remove "not yet wired" comment.
- Fix the two stale tests.
- Delete `feat/migration-api-path` (71 commits of abandoned work, per
  `V3_ARCHITECTURE.md`). Tag it first if you want the history.

### 2.2 Close the spec gaps (so the server has one source of truth)

- Specify `GET /v3.0/sync/pending` in `SYNC_PROTOCOL.md` (today it exists
  only in `rest_transport.dart:214` and the mock). Response
  `{frames: [base64 WsEnvelope]}`, drained on read, ordered by
  `delivery_sequence`.
- Resolve `SYNC_PROTOCOL.md:1100` "TODO unify numbering" (§11.2/§11.3
  collide).
- `MessageStateChanged` and `Typing` are in
  `v3-server-event-payload.proto` but §18 says presence/receipts are
  v3.1. They ship in 3.0 (the client already sends them). Update §18 and
  fix the misplaced doc comment on `message Typing`.
- Decide the channel-kind literal once: `one_to_one` (spec, proto, types,
  tests) not `dm` (client, store query). Fix the code, not the spec.
- Move `AUTH_CONTRACT.md`, `SYNC_PROTOCOL.md`, `docs/proto/*.proto` into
  `chat-server/docs/` and make the client copy a git submodule or a
  documented mirror with a checksum. One canonical copy.

### 2.3 Fix the four seam bugs the mock hides

1. **`resource_seq` restarts at 1.** `MAX(resource_seq)+1` over
   `outbound_ops` (`chat_service.dart:190,266,322,552`), but acked rows
   are deleted. A spec server returns `out_of_order` on the first send
   after any drain. Fix: `resource_seq` table `(resource_id, next_seq)`
   bumped inside the insert transaction; one `ChatStore.nextSeq()`
   replaces the four copies.
2. **Kind literal** `dm` vs `one_to_one` (`chat_service.dart:482`,
   `chat_store.dart:941`, `main.dart:372`).
3. **Logout leaves the DB.** `auth_service.dart:303` clears secure storage
   only. Next login on the device inherits the old account's chats. Fix:
   `store.wipe()` on `loggedIn=false` in `main.dart:251`.
4. **Outbound payload is JSON, inbound is protobuf**
   (`chat_service.dart:26-41` vs `inbound_receiver.dart:159`). Encode
   `ChatPayload` from `vartalap_proto` on the way out. Remove the mock's
   JSON special case (`mock_server.dart:1749-1810`).

### 2.4 Two performance fixes

- Streams are created inside `build()` (`chats.dart:65`, `chat.dart:350`,
  `new_chat.dart:590`); every `setState` re-runs the SQL. Hoist to
  `initState`. `chat.dart` also double-subscribes (`:99` and `:350`).
- Duplicate read-receipt op on chat open (`chat.dart:89` and `:114`).

---

## 3. Phase 1 — Server v3 (critical path, 14 sessions + 3 integration)

Exit gate: the client, with `tools/mock_server.dart` deleted, passes the
same golden path against a docker-compose chat-server.

Order matters: auth first (everything needs `user_id`), then the WS
gateway (everything needs the envelope), then the rest.

### 3.1 profile-ms → identity + auth (`AUTH_CONTRACT.md`)

- `users` collection: `user_id` (9-hex, server-assigned, immutable),
  `phone`, `username` with unique index on `LOWER(username)`,
  `displayName`, `avatarUrl`, `statusText`, `username_changed_at`,
  tombstone.
- `otp_sessions` (TTL index 600s, attempt counter, lock at 5),
  `sessions` keyed `(user_id, deviceId)`: accesskey (30d), refreshToken
  (90d, single-use, rotated in one transaction).
- Routes: `POST auth/otp/{send,verify,resend}`,
  `POST auth/session/{refresh,revoke}`, `GET|PATCH users/me`,
  `GET users/{id}`, `POST users/username/check`, `POST users/me/delete`,
  `POST auth/phone/rebind/{start,verify}`, `POST contacts/lookup`
  (SHA-256 phone hashes, 500/day/user), `POST push/topic`.
- Username required: `username: null` accounts get `403
  USERNAME_REQUIRED` on everything except `users/me`,
  `users/username/check`, `auth/*`. Add
  `GET /v3.0/users/by-username/{username}` (exact, case-insensitive,
  rate-limited; requires `?key=` when the user set a username key).
  `PATCH users/me` accepts `usernameKey` (4 digits, hashed).
  `POST channels` one_to_one carries `initiatedVia: phone|username` only
  to enforce the key. `phone` is never in any response except the
  owner's.
- `SmsSender` interface + `MockSmsSender` (sms-gate.app is the real
  one). Pick the
- `/auth` nginx subrequest validates `Authorization: Bearer` and
  `Sec-WebSocket-Protocol: accesskey.<uuid>`, sets `x-user: <user_id>`.
- Delete `firebase-auth-provider.js`, `firebase-admin`.

### 3.2 connection-gateway → `WsEnvelope` (`SYNC_PROTOCOL.md` §5-§10)

- Replace `proto/event-args.proto` framing with `v3-envelope.proto`.
  Binary frames only.
- Per frame: `WS_OP` → validate ≤20 envelopes, op_id prefix ==
  session `user_id`, `seq:<user>:<resource>` +1 in Redis
  (`out_of_order` otherwise), `dedup:<user>` (10k, 7d, stores outcome),
  membership check via channel-ms, stamp `sender_user_id`,
  `server_timestamp_ms`, `delivery_sequence`; publish; reply `WS_ACK`.
- `WS_REAUTH_REQUIRED` 5s before close `4001`; `4002` on revoke, `4003`
  on rebind.
- Rate limits: 30 env/s sustained, 100 burst per user.

### 3.3 message-delivery → fanout + undelivered queue (§10.3, §11)

- Fanout `WS_PUSH` to every member except the sender's own device.
- Undelivered queue per user: 30 days rolling, 10k frames, drop oldest.
  Redis list or Mongo capped collection; Kafka/NATS stays the bus.
- `GET /v3.0/sync/pending` drains it in `delivery_sequence` order.
- On enqueue for an offline user: ntfy wake (no content), debounced
  1 per 5s per recipient.

### 3.4 channel-ms → v3 routes + ServerEventPayload fanout

- Client-generated channel ids (UUIDv7); reject on collision, never
  reassign. Body carries `op_id`, `resource_seq`, `client_timestamp_ms`.
- `POST channels`, `PATCH|DELETE channels/{id}`,
  `POST channels/{id}/members`, `DELETE channels/{id}/members/{user}`.
  `DELETE channels/{id}` = leave for members, delete for owner.
- Emit `ChannelCreated`, `ChannelMemberAdded/Removed`, `ChannelEdited`,
  `ChannelDeleted` as `WS_PUSH` envelopes with `payload[0]==0x53` to
  affected members. `ProfileEdited` / `UsernameChanged` from profile-ms
  to every channel co-member.

### 3.5 notification-ms → ntfy

- Replace `firebase-pn-service.js` with an ntfy publisher (HTTP POST to
  `topicUrl`). Store `(user_id, deviceId) → topicUrl`.
- Self-hosted ntfy in `docker-compose.infra.yml`.

### 3.6 media-ms → `POST /v3.0/uploads/sign`

- Merge `feature/mino-support` (MinIO already scripted there).
- Presigned PUT + GET; `Attachment{uri, mimeType, size}` is the client's
  business.

### 3.7 Tests (the repo has none)

- Contract tests per route with supertest-style HTTP against a running
  service + in-memory Mongo.
- A WS conformance suite: port the scenarios `tools/mock_server.dart`
  already encodes (ack outcomes, dedup replay, out_of_order, reauth,
  0x53 routing). Run it against the real gateway in CI.
- After 3.7 lands, `tools/mock_server.dart` is deleted from the client.

---

## 4. Phase 2 — Client feature completion (11 sessions, parallel with Phase 1)

Each item lands as: store/sync change → screen → one widget or service
test → row updated in the matrix (§6).

### 4.1 Push (ntfy-direct)

- Generate per-device topic on first login, `registerPushTopic`,
  persist in secure storage, deregister on logout.
- Onboarding: if ntfy app is absent, prompt install (F-Droid link).
- Intent receiver: ntfy wake → `pullPendingSync` + WS reconnect.
- Tap notification → correct chat (`onGenerateRoute` `/chat/<id>` exists;
  fix the hardcoded `kind: 'dm'`).

### 4.2 Attachments

- Image + file pick (native picker), `uploads/sign`, PUT, wrap
  `Attachment` in `ChatPayload`. Store already has the BLOB column.
- Inbound: thumbnail, lightbox, file row. Cache to app dir.
- "Media, links and docs" tile in chat info: a `content_type LIKE
  'image/%'` query; replaces the "Coming soon" stub.
- Profile photo and group photo: same presigned PUT, then
  `PATCH users/me {avatarUrl}` / `PATCH channels/{id} {avatarUrl}`
  (both already in the contract, `ProfileEdited` / `ChannelEdited`
  fanout carries the change). Avatar widget shows the photo when set,
  else initials on a stable per-id colour; cache to app dir.

### 4.3 Edit / delete / react (outbound + UI)

Store and receiver already apply inbound `MESSAGE_UPDATE`,
`MESSAGE_DELETE`, `REACTION_ADD`. Missing: long-press menu, outbound
ops, the 5s undo toast (decision 11). Tombstone columns exist.

### 4.4 Failure surface

`watchFailures` and `manualRetry` have no caller. Dead-letter ops need a
red state on the bubble and a retry action. This is the Spike B gate.

### 4.5 Per-channel mute

`channel_settings(channel_id, muted_until_ms)`; four durations; gate
the ntfy wake server-side via `POST channels/{id}/settings` or a field on
`push/topic`. Replaces the "Notifications" stub.

### 4.6 Identity UX (username-first)

- "Choose your username" step after OTP verify, mandatory, reusing the
  Profile screen's availability check.
- Username key row on own profile (optional 4 digits).
- Display-name resolver: contact-book name → `@username`. Remove the
  phone fallback from every screen.
- New chat picker: search matches contact-book name, `@username` and
  saved phone numbers; "Find by @username" entry (with optional key
  field) for people not in your address book.
- Own profile: phone row marked private. QR row encodes the username
  (replaces the "coming soon" stub).

### 4.7 Plumbing

- `RestTransport.state` from `connectivity_plus` (`rest_transport.dart:34`).
- Sentry: wire `sentry_flutter`, init only after opt-in, test event
  button. (Decision 8; the toggle already exists.)
- Message pagination: `offset` is unused; page at 200.
- Phone entry: replace the `+91` hack with a country-code field.
- Remove the QR "coming soon"; ToS link points at the privacy URL.
- Consent screen Cancel is a no-op; make it exit.
- Background drain: **cut from 3.0**. Push wake + pull-on-foreground
  cover it; add Workmanager in 3.1 if telemetry shows queued frames.

---

## 5. Phase 3 — CI, device pass, release (4 sessions + your device time)

- CI (currently only issue templates): client `analyze` + `test` +
  `scripts/degoogle_gate.sh` on every PR; server `lint` + contract +
  conformance suites. Release job runs the APK `classes.dex` grep.
- Real-device pass on Realme X2 Pro, then one Snapdragon 6xx device.
- The 8-step smoke script from
  `~/.gstack/projects/ramank775-vartalap/raman-feat-v3-foundation-eng-review-test-plan-20260414-161909.md`
  run on a release build. Green = ship.
- Perf: cold start p95 < 1s and local send commit p95 < 100ms on the
  real device, with the 1k/100k seed.
- Release: same signing key, `versionCode` 80+, destructive-reset consent
  on upgrade, GitHub Release APK. F-Droid is post-launch.

---

## 6. Feature matrix (definition of "complete")

Product rules (owner, 2026-09-20), mocked up in
`docs/design/v3-ui-mockups.html`:

- **Local-first applies to every action.** Send, edit, delete, react,
  create group, add or remove member, leave group, mute, profile and
  photo edits all commit locally at once and sync when a connection
  exists. The UI never says an action "needs a connection". The single
  network-bound step is resolving a person you have never chatted with
  (phone-hash or `@username` lookup), which is a read.
- **Chats, Contacts, Groups are three separate things.** Chats lists
  only conversations with at least one message; a group or contact with
  no messages never appears there.
- **Delete chat ≠ leave group.** Delete chat is local-only: it removes
  the row from Chats and clears history. Membership is untouched and the
  group still shows under Groups. Leave group lives in group info and is
  a server op.
- **New chat** opens a picker with Contacts and Groups tabs; groups are
  listed like contacts.
- **Username is the public identity; phone is private.** Greenfield,
  so we skip WhatsApp's transitional "optional username" phase and ship
  its end state: username required, chosen at signup; phone used only
  for login, verification and address-book matching, never shown to
  another user. Optional 4-digit username key gates first contact by
  username. Display: contact-book name if you hold their number, else
  `@username`. Finding people: numbers already in your address book
  match via hashed lookup, as in WhatsApp; anyone else by exact
  `@username`. The server hands out a phone only to its owner.
- **3.1: Chats splits into Personal and Other** (the SMS-app pattern of
  separating personal numbers from sender-ID traffic). The 3.0 Chats
  screen is built so that split slots in without a redesign.


| Feature | Client today | Server today | 3.0 |
|---|---|---|---|
| OTP login, refresh, logout | done (mock) | none | ship |
| Username required at signup, username key, find by @username, phone private | partial | none | ship |
| Profile edit, availability check | done (mock) | none | ship |
| Contact discovery (hashed) | done (mock) | none | ship |
| 1:1 chat, offline queue, ACK states | done (mock) | none | ship |
| Groups: create, add, remove, leave, rename | done (mock) | none | ship |
| Typing, read receipts | done (mock) | none | ship |
| Push wake (ntfy) | unwired | none | ship |
| Attachments + media tile, profile and group photos | absent | presign exists (v1) | ship |
| Edit / delete / react + undo | inbound only | n/a (opaque) | ship |
| Dead-letter retry UI | absent | n/a | ship |
| Per-channel mute | stub | none | ship |
| Sentry opt-in | toggle only | n/a | ship |
| Chats / Contacts / Groups separation, delete chat ≠ leave group | partial | n/a | ship |
| Search in chat | done (local) | n/a | ship |
| Theme | done | n/a | ship |
| Personal / Other chat lists | absent | n/a | 3.1 |
| Background drain (Workmanager) | absent | n/a | 3.1 |
| Phone rebind, account delete | client lib only | none | 3.1 (hide UI) |
| Multi-device, E2E, iOS, calls, UnifiedPush | – | – | out |

---

## 7. Timeline (agentic)

Unit: one **session** = one Claude Code run of 2-4 hours wall clock,
including your review of the diff. Estimates include a first-integration
rework pass; the four seam bugs show the mock diverges from the spec in
places not yet found, so budget the integration sessions and expect to
use them.

| # | Work | Sessions | Needs you for |
|---|---|---|---|
| 0 | Purge, 4 seam bugs, spec gaps, stream hoist | 2 | decision 1 |
| 1.1 | profile-ms: OTP, sessions, users, username, contacts, push topic, nginx auth | 3 | SMS gateway account |
| 1.2 | gateway: WsEnvelope, subprotocol auth, seq/dedup, ACK, reauth | 3 | – |
| 1.3 | delivery, undelivered queue, `/sync/pending`, ntfy wake | 2 | ntfy instance |
| 1.4 | channel-ms v3 routes + ServerEventPayload fanout | 2 | decision 4 |
| 1.5 | notification-ms ntfy publisher | 1 | – |
| 1.6 | media presign + MinIO merge | 1 | – |
| 1.7 | contract tests + WS conformance suite | 2 | – |
| I | first client-vs-real-server integration, debug loop | 3 | docker infra running |
| 2.1 | push: topic, intent receiver, onboarding | 2 | real device |
| 2.2 | attachments: pick, upload, viewer, media tile | 3 | real device |
| 2.3 | edit / delete / react + 5s undo | 2 | – |
| 2.4 | dead-letter retry UI | 1 | – |
| 2.5 | per-channel mute | 1 | – |
| 2.6 | Sentry, pagination, connectivity, phone entry, UX holes | 2 | GlitchTip/Sentry DSN |
| 3 | CI + degoogle gate + server CI | 1 | – |
| 3 | device pass, smoke script, perf run, fixes | 2 | you on device, 2-3 evenings |
| 3 | release build, consent flow, GitHub Release | 1 | signing key, Play console |
| | **Total** | **34** | |

Critical path: 0 → 1.1 → 1.2 → I → 2.1 / 2.2 → device pass → release.
2.3-2.6 build against the mock in parallel with Phase 1 and get
re-verified during I.

| Mode | Throughput | Wall clock |
|---|---|---|
| Full-time, server + client in parallel worktrees | 2-3 sessions/day | 3-4 weeks |
| Part-time evenings + weekends | 5-7 sessions/week | 6-7 weeks |

Where the time actually goes, in order: integration debugging, your
verification on a real device (OTP, push, attachments), infra setup
(compose, ntfy, MinIO, SMS gateway signup), review loops. Writing the
code is the smallest share.

---

## 8. How testing happens

The existing unit tests are not the source of truth. They are cheap to
keep green but they proved nothing about the four seam bugs. The source
of truth is the **spec** (`SYNC_PROTOCOL.md`, `AUTH_CONTRACT.md`,
`docs/proto/`) made executable.

| Layer | What | When | Trust |
|---|---|---|---|
| L0 | `flutter analyze` | every change | static only |
| L1 | **Strict mock server.** `tools/mock_server.dart` rejects what the spec rejects: `out_of_order` seq, `prefix_mismatch`, batch > 20, non-protobuf `ChatPayload`, unknown channel kind, `SESSION_CONSUMED`, replayed refresh tokens. Startable in-process (`MockServer.start()`), `main()` stays a thin wrapper. | Phase 0 first | executable spec |
| L2 | **Headless golden path.** `test/golden_path_test.dart`: strict mock + real `ChatStore` (ffi, temp file) + real scheduler and transports + `AuthService`/`ChatService`, no widgets. Walks OTP → DM → send → ACK → inbound echo → group create → add member → leave → logout → second login sees an empty store. Seconds to run. | every change; **the Phase 0 exit gate** | end-to-end minus UI |
| L3 | **Emulator run.** `integration_test/` driving the real UI on an Android AVD (`Pixel_7` exists) against the mock on localhost. | phase gates | real UI, fake server |
| L4 | **Conformance suite vs real server.** The L1 scenarios re-run against docker-compose chat-server (plan §3.7). | Phase 1 exit | real everything |
| L5 | Real device, the 8-step smoke script, perf harness. | Phase 3 | ship gate |

Rules:
- A seam bug is fixed only when an L2 assertion goes red → green.
- Every Phase 2 feature adds one L2 scenario and, if it has native
  surface (push, picker), one L3 step.
- The old app unit tests stay, get fixed when stale, and are never the
  reason to call something done.

---

## 9. Decisions

Resolved 2026-09-20:
1. Keep `feat/v3-foundation`; no `lib/` restart.
2. SMS gateway: **sms-gate.app**.
3. ntfy: **self-hosted**.

Open:
4. Group delete by owner: hard delete or require ownership transfer.
