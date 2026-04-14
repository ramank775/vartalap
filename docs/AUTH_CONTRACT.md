# Vartalap v3 — Auth Contract

> **Mirror.** This file is a copy of the canonical version owned by
> the chat-server repo. The authoritative location when chat-server
> catches up to v3 is `chat-server/docs/AUTH_CONTRACT.md`. Keep this
> copy in sync manually during the v3 design phase; once chat-server
> adopts it, this mirror becomes a reference pointer.

**Status:** v1.0 (2026-04-14)
**Scope:** Wire contract between the Vartalap v3 mobile client and the
chat-server services that own identity, sessions, push topics, contact
discovery, and account lifecycle.
**Branch:** `feat/v3-foundation` (client) / `master` (chat-server)
**Supersedes:** v0.1 Draft (Firebase-compat draft, deleted in this
revision).

This is a **contract spec**, not an implementation guide. A server
engineer implements `profile-ms`, `notification-ms`, and the
`connection-gateway` bits from this doc alone. A client engineer
implements the auth, push-registration, and contact-lookup paths from
this doc alone. Gaps are bugs in this doc; file issues against it,
do not improvise.

---

## 1. Scope and non-goals

### 1.1 In scope

- Phone-OTP signup, login, and session management.
- Identity model: `user_id` (canonical), `username` (discovery
  handle), `phone` (login handle).
- Session credentials: `accesskey` and `refreshToken`, their TTLs,
  rotation semantics, and revocation.
- Push topic registration (ntfy-direct, per `V3_ARCHITECTURE.md`
  decision 6).
- WebSocket authentication (subprotocol-based, pre-upgrade
  validation).
- Contact discovery via SHA-256 hashed phone lookup, with quotas.
- Logout and account deletion, including the **phone-rebind** flow
  (§9).
- Rate limits and the structured error envelope (§11).
- The pluggable `SmsSender` interface so SMS gateway choice stays a
  deployment-time decision.

### 1.2 Non-goals

- **No Firebase.** v3 is greenfield; there is no `/v1.0/login`
  compatibility path, no Firebase ID token decoding, no `firebase-admin`
  dependency. The decision is locked in `V3_ARCHITECTURE.md`
  decision 1.
- **No multi-device login.** v3.0 is single-device per user (see
  `V3_ARCHITECTURE.md` "out of scope"). The token model reserves
  `deviceId` but does not enforce >1 active session yet.
- **No passwords, email, OAuth, SSO.** Phone + OTP is the only auth
  factor.
- **No iOS APNs.** Android-first launch.
- **No PSI (private-set-intersection) contact discovery.** Hashed
  phone lookup with rate limits is v3.0; PSI is deferred to v4.
- **No E2E encryption.** Server reads message bodies for fanout;
  E2E is a v4 conversation.
- **No legacy migration.** v3 ships as a destructive-reset relaunch.
  This contract is the only auth surface; the v0.1 Firebase migration
  table, the v0.1 Firebase-compat test cases, and the v0.1 open
  questions list are all dropped.

### 1.3 Versioning

This contract is v1.0. The URL prefix `/v3.0/` is intentional: nginx
on the chat-server gateway already strips version prefixes and
routes by them; changing to unversioned routes is a gateway-and-all-
handlers rewrite that gains nothing. Breaking changes to wire shape
bump the URL prefix (`/v4.0/auth/...`); additive changes (new fields
clients must tolerate, new optional headers) keep `/v3.0/` and bump
this document's version (`v1.1`, `v1.2`, ...).

Clients MUST tolerate unknown fields in server responses (forward
compat). Servers MUST reject unknown fields in client requests as
`validation_failed` (strict ingress, forgiving egress).

---

## 2. Identity model

This section is the heart of the contract. **Read this before any
other section.** The three identifier types and their roles do not
change anywhere else in this document.

### 2.1 The three identifiers

| Identifier | Role | Mutable? | Wire shape | Authority |
|---|---|---|---|---|
| `user_id` | **Canonical user identity.** Every reference to a user — message author, group member, ACK target, fanout recipient, event payload — uses `user_id`. Also the 36-bit UUIDv7 partition (see `SPIKE_B_SYNC.md` §4). | **Immutable.** | 9 lowercase hex chars, e.g., `"a3f2e8c5d"`. | Server-assigned at signup. |
| `username` | **Optional discovery handle.** Human-readable, used as a secondary display name (after contact-book name; see §2.4). Returned by contact lookup. Used **only** to find a user before any reference is created — once the client has the `user_id`, all subsequent operations reference the id, never the username. May be `null`. | **Optional and mutable.** Can be set, changed, or cleared at any time. | 3-32 ASCII chars, `[a-zA-Z0-9_]`, case-sensitive. May be absent (null). | NOT picked at OTP verify. Set/changed/cleared exclusively via `PATCH /v3.0/users/me` (§4.5). |
| `phone` | **Login handle.** Used during OTP send/verify. Used as a contact-discovery key (hashed). Never appears in op payloads, ACKs, or fanout frames. | **Rebindable** via §9 phone-rebind flow. | E.164, e.g., `"+919876543210"`. | User-supplied at OTP send; verified by SMS receipt. |

### 2.2 Why this split

Three independent concerns, three independent identifiers:

1. **Identity is a server-assigned opaque token** (`user_id`).
   Nothing the user types is the identity. This means:
   - Username changes never break references. A `users` table row is
     `(user_id, username, …)`; renaming is `UPDATE users SET
     username=:new WHERE user_id=:p`. Zero downstream rewrites.
   - Phone rebinds never break references. The phone column moves;
     `user_id` is unchanged.
   - An attacker scraping the contact-discovery surface gets at most
     "username X is associated with phone hash Y *right now*" — they
     do not get a stable identity, because the username can change.
2. **Discovery is a separate concern from identity.** Only the
   contact-lookup endpoint resolves `username` (or hashed phone) to
   `user_id`. After lookup, the client caches the
   `(username, user_id)` mapping locally. All subsequent ops
   reference `user_id`.
3. **Login is a separate concern from identity.** `phone` is a
   challenge-response credential, not an identifier. OTP proves the
   user controls the phone, which proves they control the
   `user_id` bound to that phone.

This is the Telegram-style model with one explicit refinement:
Telegram uses a numeric internal account ID plus a `username`;
Vartalap v3 makes the canonical identifier (`user_id`) a 9-char hex
value specifically because that value is **also** the UUIDv7 partition
(see `SPIKE_B_SYNC.md` §4). One token does both jobs: identity AND
event partitioning.

### 2.3 `user_id` shape and assignment

- **36 bits**, encoded on the wire as **9 lowercase hex characters**
  (e.g., `"a3f2e8c5d"`).
- **Server-assigned at signup** (first successful OTP verify on a
  phone with no existing account).
- **Generation:** server picks a random 36-bit value, checks the
  `users` table for collision, retries on collision. With 36 bits
  and an expected upper bound of ~10^7 users, the per-signup
  collision probability is ~10^-4; retry-on-collision is the
  appropriate strategy. Server MUST loop with a hard cap of 10
  retries before failing the signup with `INTERNAL_ERROR` (operator
  alarm: 36 bits is exhausted).
- **Returned on every login and refresh** in the response body
  (field `user_id`).
- **Embedded in every UUIDv7** the client generates (see
  `SPIKE_B_SYNC.md` §4). The client stores `user_id` in
  `flutter_secure_storage` alongside the access tokens; the
  outbound-op generator reads it once at startup and uses it for the
  lifetime of the install.

### 2.4 `username` shape and lifecycle

- **3-32 ASCII characters**, regex `^[a-zA-Z0-9_]{3,32}$`.
  Case-sensitive (`Alice` and `alice` are distinct).
- **Optional.** A user record can exist without a username
  indefinitely. Sign-up does NOT require picking one (see §3.2).
  Users without a username can still send and receive messages —
  identity is `user_id`, not `username`. They simply cannot be
  discovered by username (only by phone hash, see §7).
- **Globally unique when present.** Server enforces with a unique
  partial index on `users.username` where `username IS NOT NULL`.
- **Set or changed via `PATCH /v3.0/users/me`** (§4.5). This is the
  only path that writes `username`. Server validates shape and
  uniqueness; rejects with `USERNAME_TAKEN` or `INVALID_USERNAME`
  on failure.
- **Mutable at any time** via the same PATCH endpoint, subject to
  the §10.6 rate limit. The change is a single UPDATE on
  `users.username` — references are by `user_id`, so nothing
  downstream needs touching.
- **Removable.** PATCH with `{"username": null}` clears the
  username. After clearing, the prior name becomes available for
  anyone to claim (it does NOT enter the tombstone table — only
  account deletion does that). The 1-change-per-90-days limit
  applies to clears the same as it does to renames.
- **Tombstoned on account deletion** *if a username was set at
  the time of deletion* (`tombstones.username`); permanently
  reserved. If the deleted account had no username, only `user_id`
  is tombstoned. Rationale: prevents impersonation of past users
  who had an established handle.

**Display-name resolution rule (client UX).** When the client needs
to render a user's name (chat header, message author, group member
list, fanout sender), it MUST resolve in this order:

1. **Contact-book name.** If the local contact book has an entry
   matching the user's `phone` (resolved via the cached
   `(phone_hash → user_id)` mapping from §7), display the
   contact-book name. This is the primary identifier — the user
   has chosen what to call this person.
2. **Username**, if one is set on the user record. Display as
   `@username` (the leading `@` is a UI convention to disambiguate
   from arbitrary display strings).
3. **Phone number** in E.164 format, if the client has it from the
   contact book or from a prior interaction AND it has not already
   been used as the contact-book key in step 1.
4. **Empty / placeholder.** If none of the above resolve (a user
   the local client has no information about — e.g., a new group
   member with no contact entry and no username), display empty
   or a neutral placeholder ("Unknown member" is acceptable; the
   exact string is a UI decision, not a contract decision).

The username is intentionally NOT the primary identifier even when
present — contact-book names are user-chosen and trump any
server-side handle. This rule is what makes the username optional
in v3.0: a user without a username is indistinguishable from one
who has hidden it, because the contact-book name takes precedence
for everyone who knows them.

### 2.5 `phone` shape and role

- **E.164 format**, regex `^\+\d{8,15}$`. Server normalizes (strips
  whitespace, no other transforms — clients MUST send canonical
  E.164).
- **Bound to exactly one `user_id` at any time.** A phone may be
  rebound (§9) but has at most one owner at any moment.
- **Hashed for contact discovery.** SHA-256 of the canonical E.164
  string. See §7.
- **Never appears on the sync wire.** The only endpoints that take
  `phone` in plaintext are §3 (OTP send/verify), §7 (contact lookup,
  hashed), and §9 (phone rebind, OTP-on-new).

### 2.6 The `x-user` header semantics changed in v3

In v2, the `x-user` HTTP header on every authenticated request
carried the user's **phone number**. In v3, `x-user` carries the
**`user_id`** — 9 lowercase hex chars.

This is a **breaking change** from v2. v3 is a clean break (no
parallel-run window, see `V3_ARCHITECTURE.md` decision 1). Every
v3 client and every v3 server route MUST use `user_id` for
`x-user`. Any v2 client hitting a v3 endpoint will fail
authentication; this is intentional and surfaced via the
destructive-reset consent screen on first launch
(`V3_ARCHITECTURE.md` release model).

For new endpoints introduced in v3, the canonical authentication
header is `Authorization: Bearer <accesskey>` (see §4). The
`x-user` / `x-accesskey` pair is preserved on legacy v2-compatible
routes (chat-related routes that v3 inherits from chat-server's
existing handlers), but those routes also accept Bearer auth and
SHOULD be migrated to Bearer-only over time.

### 2.7 Wire example

Three identifiers in a typical signup response:

```json
{
  "status": true,
  "user_id": "a3f2e8c5d",
  "username": "alice_k",
  "phone": "+919876543210",
  "accesskey": "d4f5a1c9-1234-abcd-5678-ef01234abcde",
  "refreshToken": "rt_8f7a6b5c4d3e2f1a0987654321fedcba",
  "accesskeyExpiresAt": 1747267200000,
  "refreshTokenExpiresAt": 1752451200000,
  "isNew": true
}
```

Of these:
- `user_id` is the identity. Use it everywhere.
- `username` is the display handle. Show it in UI.
- `phone` is echoed for client convenience (so the client can
  display "logged in as +91…"); it is not used in any subsequent
  request body except OTP and contact discovery.
- `accesskey` is the bearer credential.
- `refreshToken` rotates the accesskey before expiry.

---

## 3. Authentication endpoints

All endpoints under `/v3.0/auth/` are unauthenticated (the client
does not have an accesskey yet) and accept/return `application/json`
with `Content-Type: application/json; charset=utf-8`.

### 3.1 `POST /v3.0/auth/otp/send`

Request OTP for a phone number. Used for both signup (phone has no
account) and login (phone has an account).

**Request body:**
```json
{
  "phone": "+919876543210",
  "deviceId": "01f0a3b4-7c2d-7000-8abc-def012345678"
}
```

| Field | Type | Required | Constraint |
|---|---|---|---|
| `phone` | string | yes | E.164 format. Server rejects non-E.164 with `INVALID_PHONE_FORMAT`. |
| `deviceId` | string | yes | Client-generated UUIDv7 stable for the lifetime of the install. Persisted in `flutter_secure_storage`. Used to bind sessions to a device. |

**Success response `200 OK`:**
```json
{
  "sessionId": "01f0a3b4-7c2d-7000-8abc-def012345678",
  "resendAfterSec": 30,
  "expiresInSec": 600,
  "isExistingAccount": true
}
```

| Field | Type | Meaning |
|---|---|---|
| `sessionId` | string (UUIDv7) | Opaque token identifying this OTP attempt. Client sends back in `/verify`. |
| `resendAfterSec` | integer | Seconds the client MUST wait before calling `/send` or `/resend` again for this phone. Default 30. |
| `expiresInSec` | integer | OTP code lifetime from now. Default 600 (10 min). |
| `isExistingAccount` | boolean | `true` if the phone is bound to a `user_id`. Used by client to skip username-pick UI on `/verify`. **Not authoritative** — server still validates on `/verify`. |

**Idempotency.** Two `/send` for the same `phone` within
`resendAfterSec` MUST return the same `sessionId` and MUST NOT mint
a second OTP code or send a second SMS. Defuses double-tap UX and
prevents SMS-gateway double-billing.

**Information-leak constraint.** `isExistingAccount` is the only
existence signal; it is necessary for client UX (show username-pick
field on signup, hide on login). It is rate-limited at the same
budget as `/send` itself (§10), so an attacker cannot enumerate a
phonebook via `isExistingAccount` faster than via OTP-spamming.

**Errors:** see §11.

### 3.2 `POST /v3.0/auth/otp/verify`

Verify the OTP code. On success, either logs in (existing account)
or signs up (new account, no username, no push topic — those are
set later via separate endpoints).

**The verify flow is intentionally minimal.** It proves the user
controls the phone and returns a session credential. It does NOT:
- pick a username (use `PATCH /v3.0/users/me`, §4.5),
- register a push topic (use `POST /v3.0/push/topic`, §5.1),
- fetch contacts (use `POST /v3.0/contacts/lookup`, §7.2).

This decoupling lets the client present each follow-up step
independently. A user can skip username-pick at signup and set one
later — or never. They can defer push-topic registration until ntfy
subscription completes (which can be slow on first install).

**Request body:**
```json
{
  "sessionId": "01f0a3b4-7c2d-7000-8abc-def012345678",
  "code": "123456",
  "deviceId": "01f0a3b4-7c2d-7000-8abc-def012345678"
}
```

| Field | Type | Required | Constraint |
|---|---|---|---|
| `sessionId` | string | yes | From `/send`. Server rejects unknown, expired, or already-consumed sessions. |
| `code` | string | yes | 6 digits, `^\d{6}$`. |
| `deviceId` | string | yes | Same value sent in `/send`. Server validates equality. |

Server MUST reject any unknown fields (including legacy `username`
or `notificationToken` from older clients) as `validation_failed`.

**Success response `200 OK`:**
```json
{
  "status": true,
  "user_id": "a3f2e8c5d",
  "username": null,
  "phone": "+919876543210",
  "accesskey": "d4f5a1c9-1234-abcd-5678-ef01234abcde",
  "refreshToken": "rt_8f7a6b5c4d3e2f1a0987654321fedcba",
  "accesskeyExpiresAt": 1747267200000,
  "refreshTokenExpiresAt": 1752451200000,
  "isNew": true
}
```

| Field | Type | Meaning |
|---|---|---|
| `user_id` | string (9 hex) | Canonical identity. **Client MUST store this in `flutter_secure_storage` and use for all subsequent op generation.** |
| `username` | string \| null | The user's currently-set username. `null` if unset (always `null` for a fresh signup, may be `null` for an existing user who has not picked one or has cleared it). |
| `phone` | string (E.164) | Echo. |
| `accesskey` | string | Bearer credential. 30-day TTL (see §4.1). |
| `refreshToken` | string | Rotation credential. 90-day TTL (see §4.2). Single-use — every refresh issues a new one and invalidates the old. |
| `accesskeyExpiresAt` | integer (ms epoch) | Absolute expiry. Client uses to schedule proactive refresh at T < 48h. |
| `refreshTokenExpiresAt` | integer (ms epoch) | Absolute expiry. After this, full re-login (OTP) is required. |
| `isNew` | boolean | `true` if this verify created the account, `false` if it logged into an existing account. Client MAY use this to decide whether to surface the optional username-pick UI on first launch. |

**One-shot semantics.** A successful verify marks the `sessionId`
consumed. Re-verify on the same session returns
`410 SESSION_CONSUMED`. There is no "retry verify with different
parameters" path — the verify request body has no
collision-prone fields anymore.

**Errors:** see §11.

### 3.3 `POST /v3.0/auth/otp/resend`

Convenience endpoint: re-send the OTP code for an existing session
without re-supplying the phone number.

**Request body:**
```json
{ "sessionId": "01f0a3b4-7c2d-7000-8abc-def012345678" }
```

**Success response `200 OK`:** identical shape to `/send`.

**Behavior.** Server looks up the phone bound to the session,
applies §3.1 idempotency: if `< resendAfterSec` since last send,
returns the same response without re-sending SMS. Otherwise mints a
new code (replaces the prior code on the session — the prior code
becomes invalid immediately) and sends SMS.

**Distinct from `/send`** in that it does not allocate a new
session — the OTP attempt count from §6 carries forward. A user can
resend up to `expiresInSec / resendAfterSec` times on the same
session before they must call `/send` again.

---

## 4. Session management

### 4.1 `accesskey`

- **Format:** UUID v4 string (opaque to the client; the format is
  server's choice, the client MUST treat it as an opaque token).
- **TTL:** **30 days** from issuance. Server enforces; client uses
  `accesskeyExpiresAt` for proactive refresh scheduling.
- **Bound to:** `(user_id, deviceId)`. A given `deviceId` has
  at most one valid accesskey at a time (issuing a new one
  invalidates the prior).
- **Carried as:** `Authorization: Bearer <accesskey>` on REST,
  `Sec-WebSocket-Protocol: accesskey.<accesskey>` on WS (see §6).
- **Storage on client:** `flutter_secure_storage` under key
  `accessToken`.
- **Server storage:** `accesskeys` table, indexed on
  `(user_id, deviceId)` and on `accesskey` (lookup by token).
- **Proactive refresh:** client MUST refresh when `< 48 hours`
  remain on the accesskey TTL. Refresh on foreground transition,
  scheduler startup, and a daily timer.

### 4.2 `refreshToken`

- **Format:** opaque server-defined string, prefix `rt_` for type
  identification in logs and storage debugging.
- **TTL:** **90 days** from issuance.
- **Bound to:** `(user_id, deviceId)`. Single-use rotation.
- **Carried as:** request body field on `/v3.0/auth/session/refresh`.
- **Storage on client:** `flutter_secure_storage` under key
  `refreshToken`.
- **Server storage:** `refresh_tokens` table; on use, the old token
  is deleted and the new one inserted in the same transaction.
- **No proactive refresh of the refresh token itself** — the
  refresh-token rotation happens automatically on every
  `/session/refresh` call (every accesskey refresh issues a new
  refreshToken alongside).

### 4.3 `POST /v3.0/auth/session/refresh`

Exchange a valid `refreshToken` for a new `accesskey` and a new
`refreshToken`.

**Request body:**
```json
{
  "refreshToken": "rt_8f7a6b5c4d3e2f1a0987654321fedcba",
  "deviceId": "01f0a3b4-7c2d-7000-8abc-def012345678"
}
```

| Field | Type | Required | Constraint |
|---|---|---|---|
| `refreshToken` | string | yes | The current refresh token. |
| `deviceId` | string | yes | Must match the `deviceId` the refresh token was issued to. Server rejects mismatch with `INVALID_REFRESH_TOKEN`. |

**Success response `200 OK`:**
```json
{
  "user_id": "a3f2e8c5d",
  "accesskey": "new-accesskey-uuid",
  "refreshToken": "rt_new-token-string",
  "accesskeyExpiresAt": 1747267200000,
  "refreshTokenExpiresAt": 1752451200000
}
```

The response includes `user_id` for completeness (so a client
that lost local state can re-bootstrap), but does NOT include
`username` or `phone` — refresh is a session operation, not a
profile fetch. To get the profile, call `GET /v3.0/users/me` (§4.4)
with the new accesskey.

**Single-use rotation.** The server MUST atomically:
1. Validate the refresh token exists, is not expired, matches
   `deviceId`.
2. Insert the new accesskey and refresh token into their respective
   tables.
3. Delete the old refresh token.
4. Invalidate the prior accesskey for `(user_id, deviceId)`.

If step 4 happens before step 2 commits and step 2 fails, the
client is locked out — so the operations MUST run in a single DB
transaction (or equivalent atomic primitive).

**Replay rejection.** A refresh token presented twice MUST return
`401 INVALID_REFRESH_TOKEN`. Server MAY additionally revoke all
sessions for `(user_id, deviceId)` on a replay, on the
hypothesis that the second presenter is an attacker with a stolen
copy. (This is a deferred hardening: v3.0 does the simple reject.)

**Errors:** see §11.

### 4.4 `GET /v3.0/users/me`

Fetch the authenticated user's profile.

**Headers:** `Authorization: Bearer <accesskey>`

**Success response `200 OK`:**
```json
{
  "user_id": "a3f2e8c5d",
  "username": "alice_k",
  "phone": "+919876543210",
  "displayName": "Alice K.",
  "avatarUrl": "https://media.vartalap/…/avatar.jpg",
  "statusText": "Off the grid",
  "createdAt": 1744675200000
}
```

`username` MAY be `null` if the user has not set one. `displayName`,
`avatarUrl`, `statusText` MAY be `null` if unset. `user_id`,
`phone`, `createdAt` are always present.

### 4.5 `PATCH /v3.0/users/me`

Update the authenticated user's profile, including the optional
username.

**Headers:** `Authorization: Bearer <accesskey>`
**Request body** (all fields optional; absent key = unchanged;
explicit `null` = clear):
```json
{
  "username": "alice_new",
  "displayName": "Alice K.",
  "avatarUrl": "https://media.vartalap/…/new-avatar.jpg",
  "statusText": "Back online"
}
```

**This is the only endpoint that writes `username`.** Username is
not picked at signup (see §3.2); users set it later via this
endpoint, or never. A user without a username is a normal user —
they just can't be discovered by username (only by phone hash).

**Username write semantics.**
- **Set or change.** Server validates new username against
  `^[a-zA-Z0-9_]{3,32}$`. Reject with `INVALID_USERNAME` on shape
  failure.
- **Uniqueness.** Server validates against the partial index on
  `users.username WHERE username IS NOT NULL` AND the
  `tombstones.username` table. Reject with `USERNAME_TAKEN` on
  either collision.
- **Clear.** PATCH with `{"username": null}` removes the username
  from the user record. The released name becomes available for
  anyone to claim (it does NOT enter the tombstone table — only
  account deletion does that, §8).
- **Race.** Two users PATCH-ing the same username concurrently:
  whoever the DB serializes first wins; the loser receives
  `409 USERNAME_TAKEN` and may retry with a different name. There
  is no reservation, no two-phase claim.
- **No downstream cascade on either set or clear.** Group
  memberships, message authorship, ACK targets, fanout recipients
  are all keyed by `user_id`, which is unchanged. Other clients
  that have cached `(username, user_id)` pairs will resolve to
  the prior name until they refresh contacts; per the §2.4
  display-resolution rule, the contact-book name takes precedence
  for users who are in the recipient's contact book regardless.

**Success response `200 OK`:** the updated profile (same shape as
§4.4). `username` field reflects the new value (or `null` if
cleared).

**Username-change rate limit.** 1 change per 90 days per user
(see §10.6). Counts set, change, and clear operations toward the
budget — once a user writes `users.username` (in either direction),
the next write is allowed only after 90 days. The first-ever set
IS exempt: a user who has never had a username can pick one
without consuming a slot, but renaming it later (or clearing it)
starts the 90-day clock.

**Other fields.** `displayName`, `avatarUrl`, `statusText` are
free-form. `null` clears them. They are NOT subject to the
username rate limit; they share the §10.6 "other profile fields"
budget (50/hour).

### 4.6 `POST /v3.0/auth/session/revoke`

Revoke the current accesskey (logout).

**Headers:** `Authorization: Bearer <accesskey>`
**Request body:**
```json
{
  "refreshToken": "rt_8f7a6b5c4d3e2f1a0987654321fedcba"
}
```

The client supplies the refresh token alongside, so server can
revoke both in one call. If the client has lost the refresh token,
it MAY omit the field; server revokes the accesskey only.

**Success response `200 OK`:**
```json
{ "status": true }
```

**Server side-effects:**
1. Delete the accesskey row.
2. Delete the refresh-token row (if supplied).
3. Deregister the ntfy push topic for `(user_id, deviceId)` —
   see §5.
4. Drop any active WS connections for this `(user_id, deviceId)`
   with WS close code **4002** (session revoked, see §6.4).

**Idempotent.** Revoking an already-revoked accesskey returns 200;
the operation is a no-op when nothing exists to delete.

---

## 5. Push topic registration

Per `V3_ARCHITECTURE.md` decision 6: ntfy-direct, with the ntfy
Android app as the pinned distributor. The server publishes wake
notifications to the user's registered ntfy topic when an
undelivered message accumulates for an offline user (see
`SYNC_PROTOCOL.md` §12).

### 5.1 `POST /v3.0/push/topic`

Register or replace the ntfy topic for the authenticated session.

**Headers:** `Authorization: Bearer <accesskey>`
**Request body:**
```json
{
  "topicUrl": "https://ntfy.vartalap/u/abc123xyz"
}
```

| Field | Type | Required | Constraint |
|---|---|---|---|
| `topicUrl` | string \| null | yes | Full HTTPS URL of the ntfy topic the client subscribed to. `null` or `""` deregisters. Server validates HTTPS scheme and a basic URL shape; on invalid, rejects with `INVALID_TOPIC_URL`. |

**Success response `200 OK`:**
```json
{ "status": true }
```

**Server storage.** `notification-ms` owns a table keyed by
`(user_id, deviceId)`. A registration replaces any prior URL
for the same key — at most one topic per `(user_id, deviceId)`.
The server MUST publish wake notifications only to the most
recently registered URL.

**Why `(user_id, deviceId)` and not just `user_id`.** v3.0
is single-device per user, but the data model already supports
multi-device (one topic per device); v3.1 will switch on multiple
active sessions without a schema migration.

**Topic URL ownership.** The server does not validate that the
client actually subscribed to the topic on the ntfy server. The
client picks a topic URL random enough that it is not guessable
(suggested: `https://<ntfy-host>/u/<random-32-char-base32>`); if a
client registers a topic it doesn't own, it just doesn't get its
own notifications. There is no third-party harm.

### 5.2 Implicit deregistration

The server MUST deregister the ntfy topic in three cases:
1. `POST /v3.0/auth/session/revoke` (logout).
2. Account deletion (§8).
3. Phone rebind (§9) — old session's topic stays registered until
   the rebind completes; on completion, the old session is revoked
   and its topic deregistered.

Phone rebind keeping the same `user_id` means **no topic
migration is required** — the new session on the new phone
registers its own topic, the old one is dropped.

---

## 6. WebSocket authentication

The chat-server's `connection-gateway` accepts WS connections at
`wss://<host>/wss`. Authentication happens **before** the WS upgrade
completes, on the HTTP upgrade request itself.

### 6.1 Subprotocol-based auth

The client MUST pass the accesskey in the
`Sec-WebSocket-Protocol` header, prefixed with `accesskey.`:

```
GET /wss HTTP/1.1
Host: chat.vartalap
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: <client-generated>
Sec-WebSocket-Version: 13
Sec-WebSocket-Protocol: accesskey.d4f5a1c9-1234-abcd-5678-ef01234abcde
```

Why the subprotocol header and not a query string or cookie:
- Query strings appear in nginx access logs; accesskeys would leak.
- Cookies require setting up cookie scope correctly for a non-
  browser client; subprotocol is universally supported by WS
  libraries on every platform.
- The `Sec-WebSocket-Protocol` header is the WS-native signaling
  channel and is consumed by the server pre-upgrade; it does not
  appear in subsequent frame logs.

### 6.2 Pre-upgrade validation

**Server MUST:**
1. Parse the `Sec-WebSocket-Protocol` header. If absent, malformed,
   or doesn't start with `accesskey.`, reject the upgrade with
   HTTP `401 Unauthorized` and the standard error envelope (§11):
   ```json
   {"error": {"code": "MISSING_ACCESSKEY", "message": "WebSocket subprotocol must carry accesskey"}}
   ```
2. Validate the accesskey against the `accesskeys` table. On
   invalid, expired, or revoked: reject with HTTP `401`:
   ```json
   {"error": {"code": "INVALID_ACCESSKEY", "message": "accesskey is not valid"}}
   ```
3. On success: complete the WS upgrade and echo the subprotocol back:
   ```
   HTTP/1.1 101 Switching Protocols
   Upgrade: websocket
   Connection: Upgrade
   Sec-WebSocket-Accept: <computed>
   Sec-WebSocket-Protocol: accesskey.<same-uuid>
   ```
4. Associate the connection with `(user_id, deviceId)`
   server-side. All op frames on this connection are authenticated
   as that `user_id`. Op frames MUST NOT carry a `user_id`
   field — the server derives it from the connection identity.

**Why pre-upgrade validation.** A WS connection that only validates
auth post-upgrade has a window where the connection counts toward
limits and consumes resources before being closed. Pre-upgrade
validation makes invalid-token traffic indistinguishable from a
malformed HTTP request — same handling, same metrics.

### 6.3 Mid-connection accesskey expiry

If the server detects an expired accesskey during op processing
(e.g., scheduled liveness check, or a downstream
`verifyAccessKey` returning invalid):

1. Server MUST emit a `reauth_required` WS frame:
   ```json
   { "type": "reauth_required" }
   ```
2. Server MUST close the connection with WebSocket close code
   **4001** ("accesskey expired, reauth required") and close
   reason `"accesskey_expired"`.
3. Any ops already accepted before expiry detection MUST stand —
   no rollback. Per-op ACKs for in-flight ops MAY be `auth_failure`
   for ops processed after the expiry detection window (see
   `SYNC_PROTOCOL.md` §15.4).

### 6.4 Mid-connection revocation

If the server revokes the accesskey while the connection is open
(e.g., `/session/revoke` was called from another client, or admin
intervention):

1. Server MUST emit a `reauth_required` frame.
2. Server MUST close with WebSocket close code **4002** ("session
   revoked") and close reason `"session_revoked"`.
3. The client SHOULD distinguish 4001 from 4002 — 4001 means
   "refresh and reconnect"; 4002 means "you are logged out, return
   to login screen."

### 6.5 Reserved WS close codes

| Code | Meaning | Client action |
|---|---|---|
| 1000 | Normal closure | Reconnect if app is foreground |
| 1001 | Going away (server restart) | Reconnect with backoff |
| 1006 | Abnormal closure (network) | Reconnect with backoff |
| 1008 | Policy violation | Log error; reconnect with backoff (likely client bug) |
| 1011 | Server internal error | Reconnect with backoff |
| 4001 | Accesskey expired | Refresh accesskey via §4.3, then reconnect |
| 4002 | Session revoked | Clear local credentials, return to login |
| 4003 | Phone rebind invalidation (see §9.4) | Refresh accesskey via §4.3, then reconnect with new credentials |

Codes 4000-4999 are reserved for application-defined meanings.
Server MUST NOT use codes outside the 4001-4003 range without
adding them to this table.

---

## 7. Contact discovery

Resolve a phone number (the user's contact-book entry) to a Vartalap
account. Used when the user opens "New chat" and selects a contact.

### 7.1 Privacy posture

The server does not learn plaintext phone numbers it doesn't already
know about. The client hashes phone numbers with SHA-256 before
sending; the server matches against pre-hashed phone columns in the
`users` table.

This is a **soft privacy guarantee** — the hash space is small
enough (~10^10 possible E.164 numbers) that brute-force reversal is
trivial. The actual goal is:
- **Prevent casual log/breach exposure** of the user's contact list.
- **Prevent enumeration via discovery endpoint** by rate limit (§7.4).
- **Provide a bridge** to a stronger PSI scheme in v4 without
  breaking the discovery API shape.

PSI (private-set-intersection) is the proper fix. It is **deferred
to v4**. Do not redesign the v3.0 API on the assumption that it will
become PSI; the wire shape will likely change when PSI lands, and
that's fine.

### 7.2 `POST /v3.0/contacts/lookup`

Look up a batch of phone hashes.

**Headers:** `Authorization: Bearer <accesskey>`
**Request body:**
```json
{
  "phoneHashes": [
    "5a8f2c1d…sha256_hex",
    "3b7e4a9c…sha256_hex"
  ]
}
```

| Field | Type | Required | Constraint |
|---|---|---|---|
| `phoneHashes` | array of strings | yes | SHA-256 hex (lowercase, 64 chars). 1-100 entries. Server rejects > 100 with `BATCH_TOO_LARGE`. |

**Hashing input.** The client MUST hash the canonical E.164
representation: leading `+`, country code, subscriber number, no
spaces, no formatting. Example:
```
SHA256("+919876543210") =
"5a8f2c1d3e4b6a7c9d8e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1"
```
Server MUST hash its `users.phone` column the same way (lowercase
hex, canonical E.164 string).

**Success response `200 OK`:**
```json
{
  "matches": [
    {
      "phoneHash": "5a8f2c1d…sha256_hex",
      "username": "alice_k",
      "user_id": "a3f2e8c5d"
    },
    {
      "phoneHash": "3b7e4a9c…sha256_hex",
      "username": null,
      "user_id": "b1c2d3e4f"
    }
  ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `matches` | array | One entry per phone hash that resolved to a registered user. **Order is not preserved**; client matches by `phoneHash`. **Hashes that did not match are absent from the response** (negative results are not reported, only positive). |
| `matches[].phoneHash` | string | Echo of the input hash. |
| `matches[].username` | string \| null | The user's current username, or `null` if they have not set one. Per §2.4 the username is optional; a `null` here is a normal state, not an error. |
| `matches[].user_id` | string | Canonical identity. **Client MUST cache this and use for all subsequent ops referencing the user.** |

**The username can change OR appear/disappear.** A subsequent
contact lookup of the same hash MAY return a different `username`
(rename), `null` (cleared), or a string where there was previously
`null` (set for the first time) — all for the same `user_id`. The
client MUST treat `user_id` as the identity, NOT `username` —
caching contacts as `(phoneHash → user_id)` is correct; caching as
`(phoneHash → username)` is a bug.

**Display.** Per §2.4 the client renders the contact-book name for
this contact, regardless of whether `username` is null. The
`username` field is informational (e.g., to show in a profile-
detail view) — it is not the primary display name.

### 7.3 What is NOT returned

- `phone`: the server does not echo plaintext phone (the client
  already has it).
- `displayName`, `avatarUrl`: profile data is fetched separately
  via §7.5 `GET /v3.0/users/<user_id>` once the client has the
  prefix. Keeps the contact-discovery surface narrow and the
  response small.

### 7.4 Quotas

| Scope | Limit | Window | Purpose |
|---|---|---|---|
| Per user | 500 hashes/day | rolling 24h, summed across all `phoneHashes` array entries | Prevents a single account from enumerating the user-base. |
| Per request | 100 hashes | per request | Caps response size and per-request CPU. |
| Per IP | 5,000 hashes/day | rolling 24h | Defense against multi-account scripting. |

On breach: HTTP `429 RATE_LIMITED` with `retryAfterSec` (§11).

**The 500/day per-user budget** is the user-facing constraint. A
typical user with a 500-contact phonebook consumes the daily budget
in one full sync; subsequent syncs hit the cache. The client MUST
implement local caching: a `(phoneHash → user_id \| null)` table
with a TTL of 7 days. Negative results (`null`) are cached for 24h
to avoid re-querying every app launch.

### 7.5 `GET /v3.0/users/<user_id>`

Fetch a user's public profile by prefix.

**Headers:** `Authorization: Bearer <accesskey>`

**Success response `200 OK`:**
```json
{
  "user_id": "a3f2e8c5d",
  "username": "alice_k",
  "displayName": "Alice K.",
  "avatarUrl": "https://media.vartalap/…/avatar.jpg",
  "statusText": "Off the grid"
}
```

`username`, `displayName`, `avatarUrl`, `statusText` MAY be `null`.
A user with no profile data set returns a record with `user_id`
populated and everything else `null` — that is a valid response,
not an error.

**No phone returned.** Once the requesting user has the
`user_id`, they have already done discovery (or were sent the
id in a fanout); the phone is irrelevant to subsequent
operations. The server MUST NOT include `phone` in this response.

**Privacy.** This endpoint is authenticated but does not gate by
"are these users in each other's contacts." Adding such gating is
deferred (it requires the client to share its contact graph with
the server, which conflicts with the privacy posture in §7.1).
v3.0 ships with the simple "any authenticated user can fetch any
public profile by prefix" rule.

**Errors:** `404 USER_NOT_FOUND` if the prefix is unrecognized or
belongs to a deleted account (the prefix tombstone is checked, see
§8.3).

---

## 8. Logout and account deletion

### 8.1 Logout vs delete

Two different operations with different semantics:

| Operation | Endpoint | Effect |
|---|---|---|
| Logout | `POST /v3.0/auth/session/revoke` (§4.6) | Revokes credentials on this device. `user_id`, `username`, history, contacts, group memberships all preserved. User can log in again on the same or a different device. |
| Account delete | `POST /v3.0/users/me/delete` (§8.2) | Permanently removes the account. `username` and `user_id` are tombstoned; `phone` is released (becomes available for a new signup with a new account). |

### 8.2 `POST /v3.0/users/me/delete`

Permanently delete the authenticated user's account.

**Headers:** `Authorization: Bearer <accesskey>`
**Request body:**
```json
{
  "confirmation": "DELETE alice_k"
}
```

| Field | Type | Required | Constraint |
|---|---|---|---|
| `confirmation` | string | yes | Literal string `"DELETE "` followed by the user's current `username` if one is set, OR the user's `phone` (E.164, including the leading `+`) if no username is set. Server validates exact match. Reject with `INVALID_CONFIRMATION` otherwise. |

The confirmation string is intentionally human-typed and
case-sensitive. The client UI MUST present it as a typed-input
field, not a pre-filled or one-tap button. This is the
account-recovery boundary: there is no recovery for an accidentally
deleted account.

The username/phone fallback exists because username is optional
(see §2.4); a user without a username still needs a meaningful
confirmation string to type. The client knows which to use by
checking its own profile (`username` field of the cached
`/users/me` response).

Examples:
- User with `username: "alice_k"` types: `DELETE alice_k`
- User with `username: null`, `phone: "+919876543210"` types:
  `DELETE +919876543210`

**Success response `200 OK`:**
```json
{ "status": true }
```

**Server side-effects, in order, in a single transaction:**
1. Insert `(user_id, username, deleted_at)` into the
   `tombstones` table. `user_id` is permanently reserved (never
   reassigned to a new user). `username` is permanently reserved
   only if the user had one set at the time of deletion; if the
   account had no username, the tombstone row's `username` column
   is `NULL` and no name is reserved.
2. Delete the row from `users`. (This releases `phone` — the
   `users.phone` unique constraint no longer applies, so a fresh
   signup on the same number creates a new account with a new
   `user_id` and no username until the new user picks one.)
3. Delete all `accesskeys` and `refresh_tokens` for this
   `user_id`.
4. Delete all `notification_topics` for this `user_id`.
5. Remove the user from all group memberships (channel-ms cascade).
6. Schedule async cleanup of message authorship records, undelivered
   queue entries, and dedup window entries (these may exceed
   transaction time on a heavy account; safe to do best-effort
   post-commit).
7. Drop any active WS connections with code **4002** (treated as
   session revoked, since the credentials no longer resolve).

**What persists about a deleted user:**
- Past message authorship in other users' local stores. The
  chat-server is a relay; it does not store history. Recipients
  who already received the user's messages keep them.
- The `(user_id, username)` tombstone, forever.

**What is permanently gone:**
- The user's own local data (cleared by the client on confirm).
- The undelivered queue (best-effort cleanup, may briefly persist
  but is bounded by the 30-day TTL anyway, see `SYNC_PROTOCOL.md`
  §11.2).
- Any in-flight messages the user sent that have not yet been
  fanned out.

### 8.3 Tombstone semantics

`tombstones` table:
```
(user_id TEXT PRIMARY KEY, username TEXT UNIQUE, deleted_at TIMESTAMP)
```

- A `username` in `tombstones.username` cannot be picked at signup
  (§3.2) or via `PATCH /v3.0/users/me` (§4.5). Server validates
  against this table on every username write.
- A `user_id` in `tombstones.user_id` cannot be assigned
  at signup (§2.3). Server validates the random pick against
  both `users.user_id` and `tombstones.user_id`.
- `GET /v3.0/users/<user_id>` (§7.5) returns `404
  USER_NOT_FOUND` for tombstoned prefixes — clients with cached
  references to a deleted user observe the deletion as a "user no
  longer exists" UI state, not a username collision.

The reason both `username` and `user_id` are tombstoned: the
`username` tombstone prevents impersonation ("DeletedAlice" is
gone, no one new takes it). The `user_id` tombstone is a
defense-in-depth: even if `users.user_id` is ever rebuilt or
restored from backup with a hole, the tombstone prevents
re-assignment.

---

## 9. Phone rebind

When a user changes phone number, they MUST be able to keep their
account, history, contacts, and group memberships. Phone is a
login handle, not an identity (§2). The rebind flow proves
ownership of the new phone while authenticated on the old, then
swaps the bound phone column.

### 9.1 Flow overview

```
CLIENT (logged in, old accesskey)               SERVER
─────────────────────────────────               ──────
1. POST /v3.0/auth/phone/rebind/start
   { newPhone: "+919999988888" }                 →  validate new phone
                                                    not bound to another account
                                                 ←  { rebindSessionId, resendAfterSec, expiresInSec }
2. SMS arrives at +919999988888
3. POST /v3.0/auth/phone/rebind/verify
   { rebindSessionId, code }                     →  validate code
                                                    UPDATE users SET phone=:newPhone
                                                    WHERE user_id=:authenticated_prefix
                                                    invalidate sessions on old phone (none on new — same account)
                                                 ←  { user_id (echo), phone (new) }
```

**user_id is unchanged.** `username` is unchanged. All
references — message authorship, group memberships, contacts that
other users have cached — still resolve correctly.

### 9.2 `POST /v3.0/auth/phone/rebind/start`

**Headers:** `Authorization: Bearer <accesskey>`
**Request body:**
```json
{ "newPhone": "+919999988888" }
```

| Field | Type | Required | Constraint |
|---|---|---|---|
| `newPhone` | string | yes | E.164 format. Server rejects non-E.164 with `INVALID_PHONE_FORMAT`. Server rejects if `newPhone` equals the user's current `phone` with `SAME_PHONE`. Server rejects if `newPhone` is bound to another `user_id` with `PHONE_TAKEN`. |

**Success response `200 OK`:**
```json
{
  "rebindSessionId": "01f0a3b4-7c2d-7000-8abc-def012345678",
  "resendAfterSec": 30,
  "expiresInSec": 600
}
```

Same shape as `/auth/otp/send`, but the session is bound to the
authenticated `user_id` server-side (the new phone is
remembered against this rebind session).

**Server MUST send SMS** to `newPhone` with the OTP code. The
old phone receives nothing (the user already has the accesskey;
no need to re-prove ownership of the old number).

### 9.3 `POST /v3.0/auth/phone/rebind/verify`

**Headers:** `Authorization: Bearer <accesskey>`
**Request body:**
```json
{
  "rebindSessionId": "01f0a3b4-7c2d-7000-8abc-def012345678",
  "code": "123456"
}
```

**Success response `200 OK`:**
```json
{
  "user_id": "a3f2e8c5d",
  "username": "alice_k",
  "phone": "+919999988888"
}
```

**Server side-effects:**
1. Validate the OTP code, attempt count (§10), and that the
   `rebindSessionId` is bound to the authenticated `user_id`.
2. Race check: re-validate that `newPhone` is not now bound to
   another `user_id` (in case someone signed up on it between
   start and verify). On collision: reject with `PHONE_TAKEN`,
   the rebind is aborted.
3. `UPDATE users SET phone=:newPhone WHERE user_id=:p` in a
   transaction.
4. Mark `rebindSessionId` consumed.
5. Accesskey and refresh token are **unchanged** — the rebind
   does not invalidate the current session. The client continues
   with the same credentials.

**Phone-rebind does not affect contact discovery for OTHER users
of this prefix.** Other users' cached `(phoneHash → user_id)`
mappings now point to the wrong hash. The proper resync is:
those clients re-hash their contact list periodically (§7.4 cache
TTL is 7 days). For users actively chatting with the rebinder,
the new phone is invisible — they reference by `user_id`,
which is unchanged.

### 9.4 Active sessions on the OLD phone after rebind

`user_id` is the session subject, not `phone`. The accesskey
issued before the rebind continues to work after it. There is no
"session on the old phone" — there are sessions on `(user_id,
deviceId)` pairs, all of which keep working.

If the rebind is performed on Device A, and the user has a session
on Device B that was created when the phone was the old number:
- Device B's accesskey continues to resolve to the same
  `user_id`.
- Device B is unaffected by the rebind.
- Device B will only learn the phone changed on next `GET
  /v3.0/users/me` or fanout that includes phone (none — phone is
  not in fanout payloads).

### 9.5 Account recovery (lost phone)

If the user loses access to BOTH the old and new phones (lost
device, lost SIM, ported number to a non-Vartalap-aware carrier),
the rebind flow is unavailable. **Account recovery in v3.0 is
manual:** the user emails an out-of-band recovery address
(documented in the app's support screen and on the website), the
operator reviews, and manually executes the phone update or
account deletion.

This is a deferred design: a self-service recovery flow (e.g.,
email verification fallback, recovery codes generated at signup)
is a v3.1+ topic. v3.0 ships with the manual path, documented as a
known limitation.

---

## 10. Rate limits

All limits are **TUNABLE** via `profile-ms` CLI flags. Defaults
below.

### 10.1 OTP send limits

| Scope | Limit | Window | Flag |
|---|---|---|---|
| Per phone | 5 sends | rolling 1h | `--otp-rate-phone-hour` |
| Per phone | 15 sends | rolling 24h | `--otp-rate-phone-day` |
| Per IP | 20 sends | rolling 1h | `--otp-rate-ip-hour` |

Implementation: sliding-window counters in Redis, key
`otp:rate:phone:<phone>` and `otp:rate:ip:<ip>`. On in-memory
fallback (small deployments without Redis), limits apply per
`profile-ms` process — acceptable degradation for low-volume
deployments, documented as a horizontal-scaling gotcha.

On breach: HTTP `429 OTP_RATE_LIMITED` with `retryAfterSec`.

**Why three independent budgets.** Phone-hour and phone-day are
user-facing protections against SMS spam. IP-hour is an abuse
brake for an attacker cycling phone numbers from one host.

### 10.2 OTP verify limits

`/verify` is NOT rate-limited at the endpoint level. The
per-session attempt count (§10.3) is the right boundary: an attacker
trying to brute-force a 6-digit code needs to do it within the
session's `expiresInSec` (10 min default) and within the 5-attempt
cap, after which the session is locked and they need a fresh
`/send` (which IS rate-limited).

### 10.3 OTP attempt limit per session

5 wrong codes per session. On the 6th wrong submission:
- Server marks the session `locked`.
- Server returns HTTP `423 SESSION_LOCKED` with `retryAfterSec`
  set to remaining session lifetime.
- User must call `/send` to get a fresh session. The fresh `/send`
  counts toward the §10.1 phone limits.

### 10.4 Refresh-token limits

| Scope | Limit | Window |
|---|---|---|
| Per `(user_id, deviceId)` | 100 refreshes | rolling 1h |

A typical client refreshes at most once per session (proactively
when accesskey TTL drops below 48h). 100/hour is enormous headroom
that catches only pathological loops. On breach: HTTP `429
RATE_LIMITED`.

### 10.5 Contact discovery limits

See §7.4. (500 hashes/day/user, 100 per request, 5,000/day/IP.)

### 10.6 Profile update limits

| Scope | Limit | Window |
|---|---|---|
| Username changes per user | 1 | rolling 90 days (first-ever set is exempt; renames and clears consume the slot) |
| Other profile fields | 50 | rolling 1h |

Username churn is rate-limited because a username change is a
contact-cache invalidation event for everyone who has the old
name cached. Limiting to 5 per month is generous for legitimate
use and prevents harassment / impersonation games.

### 10.7 Phone-rebind limits

| Scope | Limit | Window |
|---|---|---|
| Per user_id | 3 rebinds | rolling 30 days |

Plus all the §10.1 OTP send limits apply to the rebind OTP.

### 10.8 Account-delete limits

No rate limit (it's a one-shot terminal operation), but the
confirmation string requirement (§8.2) is the human-friction brake.

### 10.9 Universal HTTP limits

Beyond the auth-specific limits above, nginx enforces:

| Scope | Limit |
|---|---|
| Request body size | 1 MiB |
| Concurrent connections per IP | 100 |
| Request rate per IP, all endpoints | 600/min |

These are not tunable per-endpoint; they catch shape-level abuse
that auth-specific limits don't see.

---

## 11. Error envelope and codes

### 11.1 Envelope shape

Every error response, on every endpoint, uses this shape:

```json
{
  "error": {
    "code": "OTP_RATE_LIMITED",
    "message": "Too many requests. Try again later.",
    "retryAfterSec": 1800,
    "scope": "phone"
  }
}
```

| Field | Type | Always present? | Meaning |
|---|---|---|---|
| `error.code` | string | yes | UPPER_SNAKE_CASE machine-readable code. Stable across versions. Client MUST handle unknown codes by surfacing `error.message` and treating as a generic retry-or-fail per HTTP status. |
| `error.message` | string | yes | Human-readable message in English. Suitable for logs and last-resort UI display. |
| `error.retryAfterSec` | integer | optional | Present on rate-limit and lock errors. Client MUST honor this minimum. |
| `error.scope` | string | optional | Disambiguates which limit was hit, for client UX. Values: `phone`, `ip`, `session`, `user`. |

`Content-Type: application/json; charset=utf-8` always.

### 11.2 Code reference

| HTTP | `code` | Endpoints | Meaning |
|---|---|---|---|
| 400 | `INVALID_PHONE_FORMAT` | OTP send, rebind start | `phone` not E.164 |
| 400 | `INVALID_USERNAME` | profile patch | `username` shape violation |
| 400 | `INVALID_CONFIRMATION` | account delete | confirmation string mismatch |
| 400 | `INVALID_TOPIC_URL` | push topic | URL shape violation |
| 400 | `MALFORMED_REQUEST` | all | missing/extra fields, malformed JSON |
| 400 | `BATCH_TOO_LARGE` | contact lookup | > 100 hashes |
| 400 | `validation_failed` | all | catch-all schema rejection (lowercase intentionally; aligns with `SYNC_PROTOCOL.md` §8.4) |
| 401 | `MISSING_ACCESSKEY` | all authenticated | no Bearer header / no subprotocol |
| 401 | `INVALID_ACCESSKEY` | all authenticated | accesskey doesn't resolve, expired, or revoked |
| 401 | `INVALID_REFRESH_TOKEN` | session refresh | refresh token doesn't resolve, expired, or `deviceId` mismatch |
| 401 | `INVALID_CODE` | OTP verify, rebind verify | wrong OTP code |
| 404 | `SESSION_NOT_FOUND` | OTP verify, resend, rebind | unknown `sessionId` / `rebindSessionId` |
| 404 | `USER_NOT_FOUND` | GET /v3.0/users/* | prefix unrecognized or tombstoned |
| 409 | `USERNAME_TAKEN` | profile patch | username collides with active user or tombstone |
| 409 | `PHONE_TAKEN` | rebind start, rebind verify | newPhone is bound to another user_id |
| 409 | `SAME_PHONE` | rebind start | newPhone equals current phone |
| 410 | `SESSION_EXPIRED` | OTP verify | `sessionId` past `expiresInSec` |
| 410 | `SESSION_CONSUMED` | OTP verify | session already verified successfully |
| 423 | `SESSION_LOCKED` | OTP verify | too many wrong codes (§10.3); resend required |
| 429 | `OTP_RATE_LIMITED` | OTP send | §10.1 limit hit; `retryAfterSec` present, `scope` set |
| 429 | `RATE_LIMITED` | all other | generic rate-limit code |
| 500 | `INTERNAL_ERROR` | all | server bug (operator alarm, e.g., user_id exhaustion §2.3) |
| 502 | `SMS_GATEWAY_ERROR` | OTP send, rebind start | downstream SMS gateway authoritatively refused (bad number, no credits) |
| 503 | `SMS_GATEWAY_UNAVAILABLE` | OTP send, rebind start | gateway unreachable; retry-eligible |

**Forward compat.** Servers MAY introduce new codes in this enum
without bumping the URL prefix. Clients MUST handle unknown codes
by:
- Reading `error.message` as fallback display text.
- Treating per HTTP status semantics (4xx = client request bad,
  5xx = server problem, retry).
- Logging the unknown code for debugging.

### 11.3 Intentional asymmetries

- `INVALID_CODE` is **401, not 400.** A wrong OTP code is an auth
  failure (the user failed to prove control of the phone), not a
  malformed-request error. Matters for UX: clients show wrong-code
  errors inline on the OTP-input field; show 400-class errors as
  form-validation messages.
- `SESSION_LOCKED` is **423, not 429.** 429 is rate-limiting
  (server pacing); 423 is locked-resource (session unusable until
  reset). Different client-side recovery — 429 means wait, 423
  means start over.
- `/verify` no longer takes a `username` field (see §3.2), so
  `USERNAME_TAKEN` is no longer reachable from the OTP path. It
  only arises on `PATCH /v3.0/users/me` (§4.5). Retrying the same
  PATCH with a different username is the recovery; the session
  is unaffected.

### 11.4 No information leaks

- `/send` MUST NOT distinguish "phone is registered" from "phone is
  unregistered" via HTTP status or error code. Both return 200 with
  `isExistingAccount` (which is itself rate-limited via §10.1).
- `/contacts/lookup` MUST NOT distinguish "no such user" from "user
  exists but has hidden their account" — there is no "hide account"
  feature in v3.0; if it lands later, it MUST be implemented as
  "absent from contact-lookup matches" (silent omission), not as
  an error code.

---

## 12. SmsSender interface

Preserved from v0.1 §8 unchanged. The pluggable interface keeps the
SMS gateway choice (Twilio vs sms-gate.app vs SMPP vs anything
else) deferred to deployment time.

```javascript
// services/profile-ms/auth-provider/sms-sender/sms-sender.js

class ISmsSender {
  /**
   * Send an SMS.
   * @param {{ phone: string, message: string, attemptId: string }} args
   * @returns {Promise<{ providerMessageId: string }>}
   * @throws {SmsGatewayError} on unrecoverable failure (bad number, no credits)
   * @throws {SmsGatewayUnavailableError} on transient failure (network, 5xx from gateway)
   */
  async send({ phone, message, attemptId }) {
    throw new Error('Not implemented');
  }

  async init() {}
  async dispose() {}
}
```

Implementations ship under `auth-provider/sms-sender/`:

- `twilio-sms-sender.js` (commercial, per-SMS cost)
- `sms-gate-app-sms-sender.js` (FOSS, old-phone-as-gateway via HTTP)
- `mock-sms-sender.js` (logs code to server stdout; used by dev and
  the integration-test stub)

Picked via `--otp-sms-sender=<code>` flag on `profile-ms`. Default
`mock` in dev config; production picks one based on the operator's
gateway choice.

**Message template:**
```
Your Vartalap code is 123456. Expires in 10 minutes. Do not share.
```

Keep under 160 chars so each OTP is a single SMS segment. English
only in v3.0; i18n is a v3.1+ topic that will require a per-user
language preference (currently absent — there's no locale on the
profile).

The `attemptId` field is the session's `sessionId` (or
`rebindSessionId`); the gateway implementation MAY use it for
gateway-side logging and dedup.

**Gateway error mapping.**
- `SmsGatewayError` → HTTP `502 SMS_GATEWAY_ERROR` (no retry; the
  number itself is bad or the account is out of credits).
- `SmsGatewayUnavailableError` → HTTP `503 SMS_GATEWAY_UNAVAILABLE`
  (retry-eligible; the gateway is temporarily unreachable).

The `/send` endpoint returns the appropriate HTTP code; the OTP
session is NOT created on either failure (so the user can retry
without a phantom session blocking them).

---

## 13. Integration points

This contract is implemented across three chat-server microservices
and consumed by one client package.

### 13.1 Server-side ownership

| Service | Owns | Endpoints |
|---|---|---|
| `profile-ms` | Identity, sessions, contacts, profile, account lifecycle | §3 (OTP), §4 (sessions, profile), §7 (contacts), §8 (delete), §9 (rebind) |
| `notification-ms` | Push topic registry | §5 |
| `connection-gateway` | WebSocket handshake and pre-upgrade auth | §6 |

`message-ms`, `channel-ms`, `delivery-manager` are not auth services
but they consume the auth output: they receive the `user_id`
from `connection-gateway` (for WS-bound ops) or from the
`Authorization: Bearer` header validation (for REST-bound ops; they
delegate validation to `profile-ms` via an existing
`verifyAccessKey` internal call).

### 13.2 Client-side consumption

The Vartalap mobile client (`packages/auth_client/`, to be
created) implements:
- OTP send/verify/resend HTTP calls.
- Session refresh on the proactive 48h schedule.
- Profile fetch and patch.
- Contact-discovery lookup with local cache.
- Push topic registration (called after ntfy app subscribes the
  client to a topic).
- WebSocket connect with subprotocol auth (delegated to the
  transport package).
- Account delete and phone-rebind UX.

The `user_id` is consumed by:
- `packages/spike_sync/` for UUIDv7 generation
  (`SPIKE_B_SYNC.md` §4).
- `packages/transport/` for the `x-user` legacy header on routes
  that still use it.
- All op payloads that reference users — author, recipient, group
  member, fanout target.

### 13.3 Bootstrap order

A fresh client install performs:

**Required, in order:**
1. `POST /v3.0/auth/otp/send` (collect phone)
2. `POST /v3.0/auth/otp/verify` (collect 6-digit code)

After step 2 the client has `user_id`, `accesskey`, `refreshToken`.
WS connection (§6) and sync (`SYNC_PROTOCOL.md`) become available
immediately. The user can send and receive messages.

**Optional follow-ups, any order, any time, can be deferred or
skipped:**

| Call | Purpose | Skip impact |
|---|---|---|
| `POST /v3.0/push/topic` | Register ntfy topic | User receives messages only when foreground (no wake-on-message). Recommended on first launch after ntfy app subscribe completes. |
| `PATCH /v3.0/users/me` (`username`) | Pick a username | User cannot be discovered by username; only by phone hash. Other users in their contact book see them by contact-book name regardless. |
| `PATCH /v3.0/users/me` (`displayName`, `avatarUrl`, `statusText`) | Profile metadata | Other users see fallback display per §2.4 resolution rule. |
| `POST /v3.0/contacts/lookup` | Find Vartalap-using contacts | The "new chat" picker has no contact suggestions; user can still start chats by phone if they know one. |

The client SHOULD prompt for username and push registration on
first launch after step 2, but MUST allow the user to skip both
and continue. There is no required state beyond
`(user_id, accesskey, refreshToken)`.

---

## 14. Security considerations

### 14.1 Token storage

- `accesskey`, `refreshToken`, `user_id`, `deviceId` MUST be
  stored in `flutter_secure_storage` (Android Keystore-backed).
- Plaintext SharedPreferences storage of any of these values is a
  v3 release blocker. Code review MUST flag this.

### 14.2 Transport

- All HTTP and WS traffic MUST be over TLS 1.2+.
- Server certificate pinning is **deferred to v3.1** — adds
  operational overhead (cert rotation breaks pinned clients
  unannounced); v3.0 relies on Android's system trust store.

### 14.3 Bearer token in WebSocket subprotocol

The `Sec-WebSocket-Protocol: accesskey.<token>` header carries the
accesskey in a place that:
- Does not appear in HTTP access logs (logged frame-level).
- Is consumed pre-upgrade so it does not appear in WS frame logs.
- Is sent over TLS.

Risk: a CDN or reverse proxy that logs request headers verbosely
would log the accesskey. Operators MUST scrub
`Sec-WebSocket-Protocol` from access-log formats. Documented as
operator obligation.

### 14.4 Phone-hash brute force

SHA-256 of an E.164 phone is trivially brute-forceable (~10^10
input space, modern hardware). The §7.4 quotas are the actual
defense; the hashing prevents casual log/breach exposure of the
contact list, not determined attack. PSI in v4 closes this gap.

### 14.5 OTP code handling

- 6 digits, generated uniformly from `000000`-`999999` using a
  cryptographic RNG (`crypto.randomInt` in Node, NOT
  `Math.random`). Leading zeros preserved (stored as string).
- Stored as bcrypt hash (cost 10), never plaintext.
- Background job purges sessions where `expiresAt < now - 1h`
  every 60 seconds.

### 14.6 SMS gateway sender ID

If the chosen gateway supports configurable sender ID, set it to
`Vartalap`. Reduces user confusion and SMS phishing risk (a code
arriving from a random shortcode is more likely to be ignored or
flagged). Operator concern — not enforced in code.

### 14.7 Username squatting

The 1-change-per-90-days limit (§10.6) prevents one user from
holding many usernames in rotation. Combined with the tombstone
permanence (§8.3), the surface for squatting and impersonation is
small but non-zero. v3.0 ships with this; v3.1 may add admin tools
to release a tombstoned name on operator review.

### 14.8 What v3.0 explicitly does NOT defend

- Sophisticated phone-number-takeover attacks (SIM swap,
  port-out fraud). Defense requires step-up verification (e.g.,
  passkey, security key) which is a v4+ feature.
- Coordinated mass-signup abuse. Hand-tuning rate limits and
  CAPTCHA on suspicious signup is a v3.1 operations concern.
- WebSocket DDoS. Connection-rate limiting is nginx's job and is
  not specified here.

---

## 15. Deferred to v3.1+

Acknowledged gaps. Client and server MUST NOT assume any of these
ship in v3.0.

- **Multi-device login.** v3.0 = one active session per user. The
  data model already supports `(user_id, deviceId)` keying;
  v3.1 enables multiple concurrent sessions, QR pairing, cross-
  device fanout.
- **Voice-call OTP fallback.** Some users can't receive SMS
  (landlines, VoIP). A `/send` option `{channel: "voice"}` with
  TTS code delivery is a v3.1 candidate.
- **Email OTP fallback.** Same shape, separate `SmsSender`-equivalent
  (`EmailSender`) implementation.
- **PSI contact discovery.** §7.1 covers the rationale.
- **Self-service account recovery.** Manual email recovery is the
  v3.0 fallback (§9.5).
- **Step-up authentication for sensitive ops.** Phone-rebind and
  account-delete currently require only the active accesskey;
  v3.1 may require fresh OTP for these.
- **Session pinning by IP / device fingerprint.** v3.0 trusts
  `(user_id, deviceId)` as the session boundary; v3.1 may add
  IP-change anomaly detection.
- **i18n for SMS templates and error messages.** English-only in
  v3.0 (§12).
- **TLS certificate pinning.** §14.2.
- **Stateless WS authentication via signed token (JWT).** v3.0
  validates the WS handshake by looking up the accesskey against
  `profile-ms` (Redis cache + DB fallback). A future option is to
  issue a short-lived signed token (JWT, HS256/EdDSA) at OTP verify
  and on session refresh, and have `connection-gateway` validate the
  signature locally with no per-connect REST/cache call. **Considered
  and rejected for v3.0** — the upside (cheaper WS handshake) does
  not pay off at v3.0's expected scale (single-region, single-device,
  ≤100k concurrent WS), and `connection-gateway` already needs Redis
  for pub/sub fanout (`SYNC_PROTOCOL.md` §16) so "truly stateless
  gateway" is not achievable anyway. Revisit when WS connect p99 is
  measurably dominated by accesskey lookup, or when multi-region
  deployment puts `profile-ms` far from the gateway. If pursued, the
  natural shape is: long-ish TTL (≈1h) JWT issued alongside accesskey,
  client sends as the `Sec-WebSocket-Protocol` subprotocol, gateway
  validates signature only, mid-connection revocation continues to
  use the existing close-code-4002 server-push path (§6.4).

---

## 16. Appendix: example flows

### 16.1 Signup (new user)

```
1. CLIENT: POST /v3.0/auth/otp/send
   { phone: "+919876543210", deviceId: "01f0a3b4-…" }
   ← 200 { sessionId: "01f0…", resendAfterSec: 30,
           expiresInSec: 600, isExistingAccount: false }

2. SMS arrives.

3. CLIENT: POST /v3.0/auth/otp/verify
   { sessionId: "01f0…", code: "123456",
     deviceId: "01f0a3b4-…" }
   ← 200 { status: true,
           user_id: "a3f2e8c5d",
           username: null,
           phone: "+919876543210",
           accesskey: "d4f5a1c9-…",
           refreshToken: "rt_8f7a…",
           accesskeyExpiresAt: 1747267200000,
           refreshTokenExpiresAt: 1752451200000,
           isNew: true }

4. CLIENT stores user_id, accesskey, refreshToken in
   flutter_secure_storage.
   At this point the user can already send and receive messages.

5. CLIENT opens WS (can happen in parallel with the optional
   follow-ups below):
   GET /wss
   Sec-WebSocket-Protocol: accesskey.d4f5a1c9-…
   ← 101 Switching Protocols
   ← Sec-WebSocket-Protocol: accesskey.d4f5a1c9-…

6. [Optional, prompted] CLIENT: PATCH /v3.0/users/me
   Authorization: Bearer d4f5a1c9-…
   { username: "alice_k", displayName: "Alice K." }
   ← 200 { user_id: "a3f2e8c5d", username: "alice_k",
           phone: "+919876543210", displayName: "Alice K.",
           avatarUrl: null, statusText: null,
           createdAt: 1744675200000 }
   USER MAY SKIP — username remains null, displayName remains null.

7. [Optional, prompted] CLIENT subscribes to ntfy topic locally,
   then registers it:
   POST /v3.0/push/topic
   Authorization: Bearer d4f5a1c9-…
   { topicUrl: "https://ntfy.vartalap/u/abc123xyz" }
   ← 200 { status: true }
   USER MAY SKIP — messages arrive only when app is foreground.

8. [Optional] CLIENT: POST /v3.0/contacts/lookup
   Authorization: Bearer d4f5a1c9-…
   { phoneHashes: ["sha256(+919999988888)", …] }
   ← 200 { matches: [ { phoneHash: "…", username: "bob_t",
                        user_id: "b1c2d3e4f" },
                      { phoneHash: "…", username: null,
                        user_id: "c2d3e4f5a" } ] }
   USER MAY SKIP — no auto-suggest in "new chat" picker.
```

### 16.2 Returning user

```
1. CLIENT: POST /v3.0/auth/otp/send
   { phone: "+919876543210", deviceId: "01f0a3b4-…" }
   ← 200 { sessionId: "01f0…", resendAfterSec: 30,
           expiresInSec: 600, isExistingAccount: true }

2. SMS arrives. (CLIENT MAY use isExistingAccount=true to skip the
   "welcome new user" UI on the OTP entry screen.)

3. CLIENT: POST /v3.0/auth/otp/verify
   { sessionId: "01f0…", code: "123456",
     deviceId: "01f0a3b4-…" }
   ← 200 { status: true,
           user_id: "a3f2e8c5d",
           username: "alice_k",
           phone: "+919876543210",
           accesskey: "new-accesskey",
           refreshToken: "rt_new",
           accesskeyExpiresAt: …,
           refreshTokenExpiresAt: …,
           isNew: false }
   (`username` reflects whatever the user has currently set, which
    may be null if they previously cleared it.)

4. CLIENT proceeds as in 16.1 from step 4. Steps 6-8 are still
   optional; CLIENT MAY re-register the push topic if it is a fresh
   install on a previously-used device.
```

### 16.3 Expired accesskey, proactive refresh

```
1. CLIENT detects accesskeyExpiresAt - now < 48h.

2. CLIENT: POST /v3.0/auth/session/refresh
   { refreshToken: "rt_8f7a…",
     deviceId: "01f0a3b4-…" }
   ← 200 { user_id: "a3f2e8c5d",
           accesskey: "fresh-accesskey",
           refreshToken: "rt_fresh",
           accesskeyExpiresAt: 1749859200000,
           refreshTokenExpiresAt: 1755043200000 }

3. CLIENT updates flutter_secure_storage with new tokens.

4. CLIENT continues using fresh accesskey on next requests.
   Old accesskey is invalid as of step 2; any in-flight WS
   connection using the old accesskey will hit reauth_required
   on the next op (§6.3) — client transparently reconnects.
```

### 16.4 Phone rebind

```
PRE-CONDITION: alice_k is logged in with phone=+919876543210,
               accesskey=d4f5a1c9-…, user_id=a3f2e8c5d.

1. CLIENT (alice taps "change phone" in settings):
   POST /v3.0/auth/phone/rebind/start
   Authorization: Bearer d4f5a1c9-…
   { newPhone: "+919999988888" }
   ← 200 { rebindSessionId: "01f1…", resendAfterSec: 30,
           expiresInSec: 600 }

2. SMS arrives at +919999988888.

3. CLIENT: POST /v3.0/auth/phone/rebind/verify
   Authorization: Bearer d4f5a1c9-…
   { rebindSessionId: "01f1…", code: "654321" }
   ← 200 { user_id: "a3f2e8c5d",
           username: "alice_k",
           phone: "+919999988888" }

4. CLIENT updates locally-cached phone display.
   accesskey, refreshToken, user_id UNCHANGED.
   All channel memberships, message authorship, contact entries
   for alice_k continue to work — they reference user_id.

5. Other users' contact caches still resolve sha256(+919876543210)
   to user_id=a3f2e8c5d for up to 7 days (§7.4 cache TTL),
   then re-hash and observe the new phone.
```

### 16.5 Account delete

```
PRE-CONDITION: alice_k is logged in (has set username "alice_k").

1. CLIENT (alice taps "delete account" in settings, types
   confirmation matching her current username):
   POST /v3.0/users/me/delete
   Authorization: Bearer d4f5a1c9-…
   { confirmation: "DELETE alice_k" }
   ← 200 { status: true }

2. CLIENT clears flutter_secure_storage and local store.
3. CLIENT returns user to OTP signup screen.

4. SERVER side-effects (in transaction):
   - INSERT INTO tombstones (user_id, username, deleted_at)
     VALUES ('a3f2e8c5d', 'alice_k', NOW())
   - DELETE FROM users WHERE user_id='a3f2e8c5d'
       (releases phone +919876543210)
   - DELETE FROM accesskeys, refresh_tokens, notification_topics
   - Drop active WS with code 4002.

5. The phone +919876543210 is now available for a fresh signup.
   A new signup creates a new user_id and no username
   (the new user picks one later if they want; cannot reuse
   'alice_k' — it's tombstoned forever).

6. Other users' contact caches that reference user_id=a3f2e8c5d
   will, on next GET /v3.0/users/a3f2e8c5d, receive 404
   USER_NOT_FOUND. Their UI shows the §2.4 fallback for an
   unresolvable identity (likely the contact-book name they have
   for this person, then phone, then a "deleted user" placeholder).
```

**Variant: deleting an account with no username.**
```
PRE-CONDITION: bob is logged in, never set a username
   (user_id=b1c2d3e4f, username=null, phone=+919876543211).

1. CLIENT prompts for confirmation. Because username is null, the
   client builds the confirmation string from phone:
   POST /v3.0/users/me/delete
   { confirmation: "DELETE +919876543211" }
   ← 200 { status: true }

4. SERVER tombstone: (user_id='b1c2d3e4f', username=NULL, …).
   No name is reserved (nothing to reserve).
```

---

