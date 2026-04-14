# Vartalap v3 — Architecture Decisions

Status: **Working draft, 2026-04-14 (revision 2)**
Origin: captured from two `/plan-eng-review` sessions on branch
`feat/migration-api-path`, plus a third `/plan-eng-review` on branch
`feat/v3-foundation` that locked the decisions in this revision.
v3 is built on `feat/v3-foundation`, branched fresh off `master`.

This is a **decisions document**, not a full design spec. It records what we
committed to and what we explicitly deferred. The implementation plan and
detailed specs follow in separate docs once the spikes below are done.

Open protocol work (per Codex outside-voice P0): the minimum reliable delivery
protocol across client, server, local store, push, and failure recovery is not
written yet. That protocol — not store choice or package count — is the real
prerequisite for v3 implementation. Write it after the spikes, before scaffold.

---

## Context

**What v3 is.** A clean relaunch of Vartalap. No migration from v2 data or
code. The `feat/migration-api-path` branch accumulated half-finished attempts
and AI slop during a period of lost focus on degoogling; it will **not** be
the v3 release branch. v3 work starts on a fresh branch off `master`.

**What v3 is not.** An incremental upgrade of v2. A Firebase-compatible
release. A feature-expansion release. v3's scope is a coherent, intentional
relaunch built on explicit decisions — not inherited assumptions.

---

## The load-bearing decisions

### 1. Degoogle, literally
Zero Firebase, zero Google-specific dependencies ship in v3.

- `firebase_core`, `firebase_auth`, `firebase_messaging`, `firebase_performance`,
  `firebase_crashlytics`, `firebase_app_check` — removed from `pubspec.yaml`.
- `com.google.gms.google-services`, `com.google.firebase.firebase-perf`,
  `com.google.firebase.crashlytics` Gradle plugins — removed from
  `android/app/build.gradle.kts` and `android/settings.gradle.kts`.
- `android/app/google-services.json` — deleted.
- iOS `GeneratedPluginRegistrant.m` Firebase imports — regenerated clean via
  `flutter clean && pod install` after pubspec removal.
- Phone OTP is self-hosted via chat-server (see decision 7).
- Crash reporting: Sentry (self-hosted / opt-in, see decision 8).
- Push: decision deferred to v3-blocker spike (see decision 6).

Because v3 is a greenfield launch, **there is no parallel-run migration
window**. Firebase comes out in the same changeset that self-hosted auth goes
in. No coexistence, no dual-provider era, no `/v1.0/login` compat route.

**Degoogle regression gate (CI).** Two-layer enforcement:
1. Pre-merge: CI greps `pubspec.yaml` for `firebase_` and
   `android/app/build.gradle.kts` / `android/settings.gradle.kts` for
   `google-services` / `firebase-perf` / `firebase.crashlytics`. PR fails if
   any appear.
2. Release gate: CI extracts release APK `classes.dex`, greps for
   `com.google.firebase` / `com.google.gms` / `com.google.android.gms`
   package prefixes. Release fails if any present. Also inspects
   `AndroidManifest.xml` for Google metadata keys and the app's dependency
   graph (`./gradlew :app:dependencies`) for Google transitive deps pulled
   by third-party libraries. (Expanded per Codex P2 — grep alone is not
   enough for transitive catches.)

---

### 2. UI stays in the app
`lib/screens/`, `lib/widgets/`, `lib/config/`, `lib/theme/` are app-layer code.
Not a package. Not swappable. The old CLAUDE.md framing that "the UI layer
can be swapped" is retired.

Implication: stop building abstraction to support a UI swap that isn't going
to happen. The app layer owns presentation; the packages own everything else.

---

### 3. Offline-first, pragmatic scope
Every **user-owned action** completes locally without a network round-trip,
with immediate UI feedback. The sync layer pushes changes to the server
asynchronously. Network failure is never a UX failure for these actions.

**Server-gated queries** (actions that require server-side validation the
client can't do alone) are allowed to block on network and show a clear
loading/offline state. Examples: checking whether a phone number is a
registered Vartalap user before starting a new chat; admin-permission checks
for group operations on groups you don't own.

**The offline-support matrix** is canonical: any action not listed here is not
supported at v3 launch. Adding an action later requires adding a row with an
explicit yes/no before it ships.

| Action | Offline? | Notes |
|--------|----------|-------|
| Send message | yes | Queues, syncs when online. Client-generated msg id (UUIDv7). |
| Edit message | yes | Queues as tombstone + 5s undo window (see Destructive ops) |
| Delete message | yes | Queues as tombstone + 5s undo window |
| React to message | yes | Queues |
| Create group (user is owner) | yes | Queues. Client-generated group id (UUIDv7). Server validates, accepts or rejects — never reassigns. |
| Add member to group you own | yes | Queues; server validates on sync. Optimistic UI shows `pending`; rejection rolls back with user-visible error. |
| Edit own profile | yes | Queues |
| Start new chat with known contact | yes | If contact is already known locally |
| Start new chat with phone number | **no** | Requires server lookup for Vartalap-user check. Timeout: 8s, retry toast on failure. |
| Join group you don't own (via invite) | **no** | Requires server-side permission grant |
| Forward message | yes | Queues per target |
| Archive / mute / pin | yes | Local-only metadata |
| Clear chat history | yes | Local-only (server has no history) |
| Delete chat | yes | Local-only tombstone; server relay queue TTL handles in-flight |
| Export chat | yes | Built from local history; server has no message records |

---

### 4. Sync layer: causal ordering per-resource
The sync layer guarantees **causal order per resource within a single device**:
if action A and action B operate on the same resource (same channel, same
message, same profile) and A was enqueued before B, A reaches the server
before B.

Actions on independent resources do not block each other. A slow
group-avatar-upload does not block sending a message in a different channel.
(Per-user total order was rejected: one poisoned upload would stall every
outgoing op. Resource-scoped sequence numbers preserve causal correctness
without self-inflicted head-of-line blocking.)

**Sequence numbers are per-resource, per-device.** Each resource (channel id,
message id, profile id) maintains its own monotonic sequence counter on the
device. The sync layer attaches `{resourceId, seqNumber}` to each outgoing op.
Server processes ops per-resource in sequence order; independent resources
parallel.

**Cross-device concurrent edits are out of scope.** v3 launch is one active
device per user (see Out of scope). The per-field CRDT / LWW conversation
from prior drafts is removed. Reinstall is handled as first-launch destructive
reset with explicit user consent (see v3 release model).

---

### 5. Local store spike and sync package replacement

**Spike A (2 days): local store.** Compare all five candidates at usable
depth:
- `drift` (ORM over sqflite, `.watch()` reactive queries)
- `sqflite` + hand-written repositories (no ORM; simpler mental model)
- `isar` (NoSQL, native indexes, fast)
- `objectbox` (NoSQL, relations, performant)
- Event-sourced log (append-only events, materialized views — theoretically
  best correctness for a messenger, most implementation cost)

Evaluate against:
1. Reactive query support (watch list of chats, watch messages in a channel)
2. Schema evolution cost — migrations for v3+ features
3. Query perf on realistic chat data (**1k channels, 100k messages** —
   revised from 10k channels; 1k is realistic for a heavy user)
4. Flutter desktop/Linux support (web is explicitly out per CLAUDE.md)
5. Ecosystem maturity and long-term maintenance
6. Test ergonomics (can the store be swapped to in-memory for unit tests)
7. License compatibility with F-Droid build (no proprietary runtime deps)
8. Native binary burden (impact on APK size and F-Droid reproducibility)
9. Backup / export story (can the on-disk format be dumped and restored?)
10. Corruption recovery (what happens after a crash mid-write, mid-schema-migration)
11. Maintenance risk (single-maintainer packages are a red flag)

**Pass/fail gate.** The picked store must meet: reads p95 < 10ms for
10k-row chat list query, writes p95 < 50ms for a 100-message batch insert,
on mid-range Android (Snapdragon 6xx class, measured in profile build).

**Output:** 1-page decision doc with winner, runner-up, one-line reason per
reject.

**Spike B: sync package replacement.** `taskq`'s current execution core
silently marks exception-throwing tasks as completed
(`packages/taskq/lib/task_scheduler.dart:192`), and its test file contains
only `void main() {}`. Replace, do not harden. Spike B designs the
replacement:
1. Per-resource sequence number enforcement (see decision 4)
2. Retry with exponential backoff + jitter
3. Dead-letter queue for exhausted retries
4. Operation ID tracking for receiver-side dedup (see decision 10)
5. User-visible error surface on terminal failure

**Pass/fail gate.** Replacement must demonstrate an end-to-end test: an op
throws three times, is retried with backoff, is moved to dead-letter on
fourth attempt, and surfaces a user-visible error. No silent completion.

**Output:** sync-package design doc + skeleton with passing end-to-end test.

**Package count is not decided in this doc.** Whether domain and sync are
one package or two depends on Spike A output. If event-sourced log wins,
sync collapses into domain as a thin overlay on the event log. If drift /
sqflite / isar / objectbox wins, they stay separate. Final count: 2 or 3
packages, decided post-spike.

---

### 6. Push notifications — ntfy-direct for v3.0
**Decision: ntfy-direct, distributor-shaped.** Vartalap depends on the ntfy
Android app installed as the push distributor. ntfy maintains the persistent
connection; Vartalap is woken by intent on new-message arrival. First-run
onboarding: if ntfy app is not installed, prompt user to install (link to
F-Droid / ntfy direct APK). No Google FCM, no foreground service in Vartalap
itself, no user-facing distributor picker (ntfy is the pinned distributor).

This is effectively UnifiedPush with one pinned distributor, which is
simpler to ship than full UnifiedPush (no distributor-choice UI) while
remaining FOSS and Google-free.

**UnifiedPush (multi-distributor) is deferred to v3.1** when there is
evidence users want distributor choice.

**Push decision timing.** Push mechanism was previously listed as a
Phase 4 concern. It is moved earlier: the push mechanism decision must be
finalized before the auth flow is designed, because the first-run
onboarding flow (install-ntfy prompt, permission grant) is on the same
screen sequence as OTP verification.

**iOS push (APNs) is out of scope for v3 launch.** Android-only. iOS when
Android is stable (see Out of scope).

---

### 7. Auth contract already exists
Server-side OTP auth contract is drafted at
`../chat-server/docs/AUTH_CONTRACT.md` (v0.1 Draft). It defines:
- `POST /v3.0/auth/otp/send`
- `POST /v3.0/auth/otp/verify`
- Request/response shapes, error codes, token format, TTLs, rate limits
- Pluggable `SmsSender` interface so gateway choice (Twilio vs sms-gate.app
  vs SMPP) stays deferred

**Must be rewritten for v3 greenfield framing.** Drop §12 (migration
strategy) and any Firebase-compat text. **Keep the `/v3.0/` URL prefix** —
chat-server's nginx gateway already strips version prefixes and routes by
prefix; changing to unversioned routes is a gateway-and-all-handlers
rewrite. Promote from v0.1 Draft toward v1.0 once rewritten.

**Auth contract scope extension.** OTP send/verify is not the whole auth
surface. The rewritten contract must also specify:
- **Device registration:** ties a device-generated device id to the user's
  accesskey; used for push topic routing and session scoping
- **Session refresh / revocation:** accesskey rotation policy, server-side
  revocation on logout, behavior on server-side force-expire
- **Push topic registration:** endpoint the client calls post-OTP to tell
  the server "my ntfy topic is X, push to this on new messages"
- **WebSocket auth:** how WS connections are authenticated with the
  accesskey, what happens on accesskey expiry during a live WS connection
- **Logout / account deletion:** endpoints, server-side cleanup semantics,
  ntfy topic deregistration
- **Rate limit behavior:** user-visible error surfaces, backoff guidance,
  distinct codes for "too many attempts on this number" vs "too many from
  this IP"

SMS gateway pick is still a product decision. Server's
`SelfHostedOtpAuthProvider` builds against the `ISmsSender` interface with
a `MockSmsSender` for dev; real gateway slotted in at deployment.

**Identity model: username is the identifier, phone number is the login
handle (Telegram-style).**

- The **username** is the canonical, immutable (or user-changeable with
  careful collision semantics) identifier for a user across the system.
  All references in messages, groups, and contacts resolve to username, not
  phone number.
- The **phone number** is the login handle used during OTP. It is a lookup
  key into "which username owns this number right now," not the identity
  itself.
- Phone number **can change** (user moves to a new number) without losing
  identity, history, contacts, or group memberships. The OTP flow for the
  new number re-binds it to the existing username after verification.
- Contact discovery works by phone lookup → username. The lookup is gated
  and privacy-preserving: contact-discovery protocol (hashed phone lookup,
  bloom filter, or private-set-intersection) is an open design question
  for the `AUTH_CONTRACT.md` rewrite, but the identity model itself is
  settled here.
- This mirrors Telegram's identity model and addresses Codex P2's
  enumeration risk: an attacker scraping phone numbers gets at most "a
  username is associated with this phone right now," not a stable user
  handle or historical linkage.

**Implication for v3 spec work:** the `AUTH_CONTRACT.md` rewrite must
define username creation flow (at first OTP, server assigns or user picks),
username change semantics, and phone-rebind flow (OTP on new number while
signed in on old number, or via account-recovery path).

---

### 8. Crash reporting — opt-in, self-hosted-capable
Sentry via `sentry_flutter`. User opts in via a settings toggle, default OFF.
DSN is configured at build time but Sentry is **not initialized** until the
user flips the opt-in toggle. This resolves the Codex P2 contradiction
("DSN not compiled in" vs "official builds point to GlitchTip"): the DSN
is compiled in but inert until consent.

For official builds, the compiled-in DSN points to GlitchTip or self-hosted
Sentry infra — never the `sentry.io` SaaS unless the user explicitly
configures it (a user-editable DSN override in settings is allowed).

Rationale: a FOSS APK silently phoning home to a third-party SaaS is
degoogle-in-name-only. User consent is the rule. Default OFF, zero events
before consent, visible indicator when enabled.

### 9. v3 launch criterion
v3 ships when the **v2 golden path works on Android without Firebase, plus
opt-in Sentry.** Everything else is v3.1.

The v2 golden path is:
1. Fresh install → OTP signup → home screen
2. Send / receive 1:1 messages (online + offline)
3. Create group, add members, send / receive group messages
4. Push notification wakes app on new message
5. Crash does not corrupt local store; app recovers on restart
6. User can opt into Sentry from settings; opting in sends a test event
   that appears in the configured backend

A launch-gate smoke test script walks a real device through all six steps
on a release build. v3 ships only when the script is green.

**Explicitly deferred to v3.1 or later:**
- Multi-device login, QR device linking
- E2E encryption
- iOS
- Voice / video calls
- UnifiedPush multi-distributor
- Feature expansion beyond v2

### 10. Idempotency and operation IDs
Every write operation (send message, edit, delete, react, group op, profile
edit) carries a **client-generated operation ID** (UUIDv7, time-ordered).
Retries on unknown ACK state are safe because receivers dedup by op ID.

**Dedup lives at the receiver client, not the server.** The chat-server
remains a transient relay and undelivered-queue; it does not maintain a
per-user dedup window. Each receiver client maintains a seen-op-id set
(bounded, e.g., last N messages per channel) and drops duplicates it has
already applied. This keeps the server stateless beyond its existing
undelivered-queue, and places dedup where the state already lives (the
local store has the authoritative history).

**Client-generated resource IDs for all user-created resources.** Messages,
channels, groups all get UUIDv7s on the client. Server validates on sync
(rejects on collision, permission failure, schema violation) but never
reassigns. This eliminates the temp-id-to-real-id remap problem for
queued dependent ops: add-member-to-group can reference the group id
before the create-group ACK arrives, because the id is already final from
the moment of local creation.

### 11. Destructive operations: tombstones and undo
Delete and edit commit locally as **tombstones** with a 5-second Undo
window. During the 5 seconds, the op is reversible from a toast. After 5s
the tombstone is finalized and queued for sync.

On server rejection (permission denied, channel no longer exists, other),
the local tombstone is rolled back and the original state is restored.
The user is notified with a clear error toast.

This rule covers: delete message, edit message, delete chat, clear chat
history, remove member from group. It does not cover non-destructive ops
(send, react, forward).

---

## Architecture shape

```
┌─────────────────────────────────────────────────────┐
│  UI LAYER (app/lib/)                                 │
│  screens, widgets, providers, theme, config          │
│  platform glue: notification intents, file picker,   │
│    share targets, permission prompts                 │
│  reads from domain store; dispatches actions         │
└────────────────────┬────────────────────────────────┘
                     │ actions / reactive queries
                     ▼
┌─────────────────────────────────────────────────────┐
│  DOMAIN + OFFLINE CORE (package)                     │
│  local store (decision 5 spike A)                    │
│  repositories, entity-to-model mappers               │
│  immediate local commit on user action               │
│  client-generated UUIDv7 resource IDs                │
│  reactive streams for UI                             │
│  enqueues sync ops (per-resource sequence + op id)   │
└────────────────────┬────────────────────────────────┘
                     │ sync ops: {resourceId, seq, opId, payload}
                     ▼
┌─────────────────────────────────────────────────────┐
│  SYNC LAYER (package, decision 5 spike B)            │
│  per-resource causal-order enforcement               │
│  retry with exponential backoff + jitter             │
│  dead-letter queue on exhausted retries              │
│  idempotency: attaches client op id to every write   │
│  outgoing-sync scheduler (Workmanager: best effort)  │
│  inbound message dedup by op id at receiver          │
└────────────────────┬────────────────────────────────┘
                     │ classified requests / WS frames
                     ▼
┌─────────────────────────────────────────────────────┐
│  TRANSPORT PACKAGE                                   │
│  HTTP client (Dio), WebSocket                        │
│  executes requests, classifies errors:               │
│    transient net (retry hint) / HTTP 4xx (permanent) │
│    / HTTP 5xx (retry hint) / auth (refresh hint)     │
│  auth header injection                               │
│  WebSocket reconnection + session resumption         │
│  NO application-level retry, NO dedup (lives in sync)│
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
                 chat-server
                 (relay + transient undelivered-op queue,
                  not a message history store)

┌─────────────────────────────────────────────────────┐
│  PUSH PATH (independent of sync)                     │
│  chat-server → ntfy topic → ntfy Android app →       │
│    intent to Vartalap → app reads new messages via WS│
└─────────────────────────────────────────────────────┘
```

Four layers in the request path. Package count (2 or 3) depends on
Spike A outcome: domain and sync may collapse into one package if
event-sourced log wins. Transport is always its own package — it is the
clean network seam.

**Layer responsibility rule (Codex P2):**
- **Transport:** executes requests, classifies errors, manages WS
  connection lifecycle. No application-level retry. No dedup. No ordering.
- **Sync:** owns everything the word "retry" implies — backoff, ordering
  within resource, dedup via op ids, idempotency, dead-letter, user-visible
  error surface.
- **Workmanager is outgoing-only.** Android Doze/OEM restrictions make
  Workmanager unreliable for incoming real-time delivery. New-message
  arrival is delivered via push (ntfy) waking the app, which then pulls
  over WS. Workmanager wakes the app periodically to drain pending outgoing
  ops when the WS connection is not active.

**Package boundary rule.** The app imports from each package's public barrel.
No reaching into `package:*/src/...` from the app. The previous v2-era
violations (app reading `client.db.chatDao` directly, app importing
`repository/auth_repository.dart` from the package internals) do not recur
in v3.

---

## v3 release model
v3 ships as a **versionCode update to the existing Vartalap app ID**. On
first launch of the v3 build, the user sees a **destructive-reset consent
screen**:

> "Vartalap v3 is a clean relaunch. Your previous chats and login are not
> carried over. Continuing will clear local v2 data and require you to sign
> in again. Install or keep Vartalap v2 if you need your existing history."

If the user consents: local v2 data is wiped, OTP flow begins. If the user
cancels: the app shows the reset screen on every launch until consent.

This is honest about the data loss (v2 history does not come forward) and
avoids the complexity of publishing a separate app listing. Users who want
to keep v2 history can sideload the v2 APK and run both during the
transition.

**Per the degoogle decision:** the release signing key stays the same as v2
(required for Play Store update continuity).

---

## Performance targets

These are decisions, not aspirations. They constrain what can ship as v3.

- **Cold start → chat list visible: p95 < 1s** on mid-range Android
  (Snapdragon 6xx class, 4 GB RAM, release build, warm disk cache,
  1k channels / 100k messages in local store). "Cold start" includes
  process spawn, Flutter engine init, app init, first frame, DB open.
  Schema migrations are not included — migration time is a separate
  first-launch-after-update target.
- **Send-message local commit: p95 < 100ms** from send-button tap to UI
  reflecting the sent message (local DB write + reactive query fanout).
  Network not included — this is the offline-first local-commit path only.
- **Spike A benchmark dataset:** 1k channels, 100k messages, mid-range
  device, release build. Measurement harness: `flutter drive` on a real
  device, not the emulator. Numbers are invalid unless the harness is
  defined in the spike output.

Targets are measured, not promised. A CI perf regression job tracks both
numbers across commits and fails on >20% regression.

---

## Explicitly out of scope for v3 launch

- Multi-device login / device linking. One device per user. Cross-device
  CRDT / LWW conflict resolution is removed from scope (consequence of
  one-device rule).
- QR-pairing-based identity (Signal model). Phone-number login +
  username-based identity stays.
- Web platform. SQLite FFI limitation, unchanged from v2.
- iOS. Android-first launch; iOS when Android is stable.
- Voice / video calls.
- E2E encryption. Server is a transient relay with an undelivered-op queue,
  not a message history store. E2E is a v4 conversation.
- Rich media beyond what v2 supports.
- Settings that are currently fake UI (read receipts toggle, last seen,
  block list) — either implement or hide. No stubs.
- UnifiedPush multi-distributor. v3 pins ntfy as the single distributor.
- APK distribution pipeline for F-Droid reproducibility. Tracked but not a
  v3-launch blocker (v3.0 can ship on Play Store with GitHub Releases for
  sideload; F-Droid listing is a post-launch task).

---

## The implementation roadmap

Step numbers are the canonical reference (no "Phase N" shorthand).

1. **Spike A** — local store decision (2 days, 5 candidates against 11 criteria,
   perf gate at 1k channels / 100k messages)
2. **Spike B** — sync package replacement design (1-2 days; taskq is not a
   candidate, the question is only the replacement shape). Output includes
   a passing end-to-end test for the retry + dead-letter path.
3. **Sync protocol spec** — write the minimum reliable delivery protocol
   across client, server, local store, push, failure recovery. Covers
   per-resource sequence, op id dedup, receiver-side dedup, tombstones,
   undelivered-queue TTL, push-topic auth, WS reauth. This is the Codex
   P0 "real prerequisite" that must exist before scaffold.
4. **Rewrite `AUTH_CONTRACT.md` for v3 greenfield, promote to v1.0.**
   Includes device registration, session refresh/revocation, push topic
   registration, WS auth, logout/account deletion, rate-limit UX,
   contact-discovery privacy, username identity model.
5. **Degoogle proof build** — first implementation milestone is a clean
   build of the current app with Firebase / Google plugins / `google-services.json`
   removed. Produces a zero-Firebase APK before any v3 scaffold work.
   Validates the degoogle CI gate against a real artifact.
6. **Scaffold v3 packages** on `feat/v3-foundation`: domain + sync (or
   combined if Spike A says so) + transport + app skeleton. First commit
   is structurally complete but feature-empty.
7. **Server-side:** `SelfHostedOtpAuthProvider` + OTP / auth / push-topic
   routes matching the rewritten `AUTH_CONTRACT.md`.
8. **Client transport package:** HTTP + WS + auth injection + error
   classification.
9. **Client domain + sync packages:** local store impl, per-resource
   sequence scheduler, op id generation, receiver dedup, tombstone / undo.
10. **App UI:** first-launch destructive-reset consent → login flow → chat
    list → chat screen, against the new stack.
11. **Push integration:** ntfy-direct, ntfy-app-install onboarding prompt,
    push-topic registration, wake-on-message.
12. **Crash reporting:** `sentry_flutter` wired with compiled-in DSN, Sentry
    init gated on settings toggle, test event from settings.
13. **Launch-gate smoke test script** against the six golden-path steps on
    a real mid-range device. Green = ship.
14. **v3 beta → v3 launch.**

This is the target order. Spike outputs may rearrange — for example, if
Spike A picks event-sourced log, steps 6 and 9 merge.

---

## Artifacts to carry forward

Decisions, contract, and test plan files referenced by v3 implementation:

- `V3_ARCHITECTURE.md` (this file) — decisions, committed on
  `feat/v3-foundation`
- `../chat-server/docs/AUTH_CONTRACT.md` — server integration contract,
  needs rewrite per decision 7 (v3-greenfield framing, auth scope extension,
  username identity model, contact-discovery privacy)
- The most recent `/plan-eng-review` test plan under
  `~/.gstack/projects/ramank775-vartalap/` — refer to it by latest mtime,
  not a pinned filename (previous drafts pinned a branch-specific path
  that becomes stale on every new review)

`TODOS.md` on the old branch is mostly obsolete. Many entries flagged bugs
in code that won't ship in v3. Do not carry it forward; re-derive the TODO
list against the v3 architecture.

---

## Open questions to answer in the new session

Questions resolved in this revision are struck through; only genuinely
open questions remain.

1. Which local store wins Spike A?
2. What does the Spike B taskq-replacement design look like concretely?
3. ~~Push: UnifiedPush, ntfy, WS-only?~~ **Resolved: ntfy-direct, ntfy
   Android app as pinned distributor. UnifiedPush is v3.1.**
4. SMS gateway: Twilio (turnkey), sms-gate.app (most FOSS), something else?
5. ~~URL versioning for v3 server routes?~~ **Resolved: `/v3.0/auth/otp/*`.**
6. ~~Conflict-resolution policy for cross-device concurrent edits?~~
   **Removed: one device per user, cross-device CRDT / LWW is out of scope.**
7. ~~Is the app renamed, or a versionCode bump on the existing ID?~~
   **Resolved: versionCode bump on the existing app ID, destructive-reset
   consent on first launch.**
8. ~~What's the v3 launch criterion?~~ **Resolved: v2 golden path on Android
   without Firebase, plus opt-in Sentry. See decision 9.**
9. **Contact-discovery privacy protocol.** Hashed phone lookup, bloom
   filter, private-set-intersection, or rate-limited plain lookup? Resolve
   in the `AUTH_CONTRACT.md` rewrite.
10. **Username creation flow at first OTP.** Server-assigned from phone,
    user-picked at signup, or random-with-user-edit? Resolve in the
    `AUTH_CONTRACT.md` rewrite.
11. **Phone-rebind flow.** OTP on new number while signed in on old number,
    or via account-recovery path? Resolve in the `AUTH_CONTRACT.md` rewrite.
12. **Undelivered-queue TTL on chat-server.** How long does the server hold
    undelivered ops for an offline user? 7 days, 30 days, forever? Resolve
    in the sync protocol spec (step 3 of roadmap).

---

## How to use this document

- Start the next session by reading this file.
- Do not re-debate decisions 1–8 unless you have new information; they are
  committed.
- The questions at the bottom are the open front. Work those first.
- When a question is resolved, update this doc with the answer and commit.
- When the v3 implementation plan is written, reference this doc as the
  decisions it rests on.

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 1 | issues_found (outside-voice) | 22 findings (6 P0, 10 P1, 6 P2); 7 accepted into doc as new/revised decisions |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 3 | issues_open (PLAN) | 24 issues across 4 sections; 11 decisions locked/extended; 4 open questions remain (Spike A winner, Spike B design, SMS gateway, contact-discovery protocol) |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

- **CROSS-MODEL:** Codex outside-voice agreed with most review findings and added 7 P0/P1 misses: causal scope (per-resource not per-user), client UUIDs for all resources, idempotency via op ids, transport/sync layer responsibility split, Workmanager scope, server-wording precision, v3 release model. All 7 integrated into this revision of the doc.
- **UNRESOLVED:** 4 genuine open questions (Spike A winner, Spike B concrete design, SMS gateway pick, contact-discovery protocol).
- **VERDICT:** Eng Review locked decisions in, but status is `issues_open` because 4 unresolved items remain. None block starting implementation — Spike A + Spike B + sync-protocol-spec are the next concrete steps. Codex findings fully integrated.

