# V3 Server-side TODOs

Working list of things the **chat-server** (and adjacent backend services) need
to implement to fully back the v3.0 client. The client is shipping with safe
fallbacks where possible — items listed here either degrade gracefully today or
have stub implementations in `tools/mock_server.dart`.

Cross-referenced against `AUTH_CONTRACT.md`, `SYNC_PROTOCOL.md`, and the open
questions in `V3_ARCHITECTURE.md`.

---

## Auth & Profile

### Username uniqueness + rate limit (high priority)

`PATCH /v3.0/users/me` currently accepts whatever username the client sends.
Two real users can claim the same handle.

**Required:**
- Global, case-insensitive uniqueness on `users.username`. SQL: unique index
  on `LOWER(username)`. On collision, return `409 USERNAME_TAKEN`.
- 1-change-per-90-days rate limit per user_id. First-ever set is exempt
  (AUTH_CONTRACT §4.5). On violation, return `429 RATE_LIMITED` with
  `retry_after_seconds`.
- Reserved-word list: `admin`, `root`, `support`, `help`, `vartalap`, `system`,
  `null`, `undefined`, plus a curated profanity blocklist. Return
  `409 USERNAME_RESERVED`.
- `POST /v3.0/users/username/check` endpoint for pre-claim availability:
  - Body: `{username: string}`
  - Response 200: `{available: bool, reason?: "taken"|"reserved"|"rate_limited"|"validation_failed"}`
  - Rate-limited at the IP layer (e.g. 60 checks/min) so the live UI can't
    be used to enumerate the username space at scale.

**Client status (shipped):**
- Inline availability indicator in Profile screen → Username row.
  Debounced 400ms after last keystroke; spinner → green check / red X.
- Sync charset/length validator runs first (lower-case a-z, 0-9, . _, 3-30
  chars, must start with a letter, no double `..` or `__`).
- Save button disabled while `checking`, `unavailable`, or sync-invalid.
- Mock server stub does case-insensitive uniqueness check only — no
  rate-limiting, no reserved-word list. Replace before prod.

### WS reauth flow (shipped client, partial server)

Client now refreshes accesskey on `WS_REAUTH_REQUIRED` and `ACK_AUTH_FAILURE`
(see commit 40f8585). Server side AUTH_CONTRACT §6.3/4 is mostly correct, but:

- Verify `WS_REAUTH_REQUIRED` is emitted with reasonable lead time before
  the actual close. Today the client just races reconnect against refresh
  and converges; cleaner would be a 5-second window.

### Refresh token rotation (verify)

`AuthClient.refresh()` writes `result.refreshToken` back to in-memory state on
every refresh, and `AuthService` now persists it to secure storage. Server
should rotate the RT on every refresh (cycle detection on stolen tokens) — if
the server is currently issuing the same RT each time, change to rotate.

### Crash reporting (Sentry init)

`Settings → Crash reporting (Sentry)` toggle exists and writes a pref but no
SDK is initialized in `main.dart`. Decide whether to:
- (a) wire `sentry_flutter` and gate on the pref, OR
- (b) remove the toggle until it does something.

---

## Sync / Inbound

### `ChannelEdited` and `ChannelDeleted` projections (medium)

`InboundReceiver._handleServerEvent` now applies `ProfileEdited` and
`UsernameChanged` (commit c523f43), but `ChannelEdited` and `ChannelDeleted`
still fall through to a log line.

**Required:**
- `ChatStore.applyChannelEdit({channelId, name?, avatarUrl?})` — sparse
  update, same proto3-`optional` semantics as `applyProfileEdit`.
- `ChatStore.applyChannelDelete({channelId})` — tombstone the channel; same
  effect as `tombstoneChannel` but driven by server fanout.
- Wire from `InboundReceiver`. Same `op_id_seen` recording pattern.
- Mock server: emit on rename/delete REST endpoints (currently neither
  endpoint exists — `_handleEditChannel` / `_handleDeleteChannel` need to
  be added too).

### Push topic registration (blocks per-channel mute)

`AuthClient.registerPushTopic({topicUrl})` exists but `main.dart` never calls
it. The whole "ntfy direct" path is dormant.

**Required:**
- Decide ntfy server: self-hosted vs ntfy.sh. v3.0 wants self-hosted
  (V3_ARCHITECTURE decision 7-ish).
- Generate a per-device topic on first boot, register via
  `POST /v3.0/push/topic`, persist in secure storage.
- Server stores `(user_id, device_id) → topicUrl` and pushes to it on
  inbound message + while user is offline.
- Client subscribes to its topic via the ntfy Android app distributor.

Once this is in place, `V3_ARCHITECTURE` open question #13 (per-channel mute)
unblocks — the `Notifications` chat-info tile can wire to a `channel_settings`
table and gate push delivery server-side.

### Background drain (Workmanager)

V3_ARCHITECTURE "still standing TODOs" → background drain is unimplemented.
Today the client only pulls pending sync on app start, post-login, and WS
reconnect. If the app is backgrounded for >24h with the WS torn down by the
OS, queued frames pile up server-side.

**Required:**
- Workmanager periodic task (12h) → call `RestTransport.pullPendingSync`.
- Battery-aware: skip if device is in Doze and not charging.
- Coordinate with push topic so we don't double-deliver.

---

## Channels & Messaging

### Group leave: server-side `delete_channel` op

`chat_service.leaveGroup` and `chat_store.leaveGroupLocal` are local-only
today. Leaving on one device doesn't propagate. Other group members keep
seeing the user as a member; if the user re-logs they re-materialize the
channel.

**Required:**
- `OpKind.deleteChannel` outbound op (REST `DELETE /v3.0/channels/{id}`).
- Server treats this as a leave for non-owners, hard delete for owners (or
  reject hard delete and require ownership transfer first — design call).
- `ChannelMemberRemoved` fanout to remaining members.

### Attachments (blocks media viewer)

V3_ARCHITECTURE open question #14. `messages.attachments` BLOB column and the
`Attachment` proto exist; `chat_service.sendMessage` is text-only.

**Required:**
- `POST /v3.0/uploads/sign` — return a pre-signed S3-style URL the client
  can PUT directly to.
- Client wraps the resulting `Attachment{uri, mimeType, size, …}` into the
  outbound `ChatPayload`.
- Receiver-side: `InboundReceiver` already persists the bytes; UI needs
  thumbnail rendering, lightbox, link preview.
- Per-channel media query (`SELECT FROM messages WHERE channel_id = ? AND
  content_type LIKE 'image/%'`) for the chat-info "Media, links, and docs"
  tile.

---

## Performance & Connectivity

### `RestTransport.state` connectivity wiring

`packages/vartalap_transport/lib/src/rest_transport.dart:34` —
`connectivity_plus` integration. Today REST is hard-coded `connected`, so the
scheduler keeps trying to dispatch even on a dead network. Failures still
surface via the ACK stream (transient on IO error), but Flow A burns
attempts unnecessarily.

### Real-device gating on Realme X2 Pro

V3_ARCHITECTURE "still standing". Untested on real hardware. Schedule a pass
once attachments + push topic land — those are the most likely places for
device-specific quirks (file pickers, push registration).

---

## Tracking

| Item | Status | Blocks |
|------|--------|--------|
| Username uniqueness + rate limit | Mock stub only | Username UX correctness in prod |
| `ChannelEdited` / `ChannelDeleted` projections | Receiver drops | Live group rename/delete |
| Push topic registration | Unwired | Mute (#13), offline push |
| Background drain | Unwired | Long-offline UX |
| Group leave op | Local-only | Multi-device group sync |
| Attachments | Unwired | Media viewer (#14) |
| Sentry init | Toggle only | Production crash visibility |
| `RestTransport` connectivity | Hard-coded | Wasted attempts on dead network |
| Real-device gating | Untested | Launch readiness |

---

This doc is a living list. When an item ships:
1. Move it from the relevant section above to a "Done" log here (or just
   delete with the commit message making the change clear).
2. If it resolved a `V3_ARCHITECTURE.md` open question, strike that question
   through over there too.
