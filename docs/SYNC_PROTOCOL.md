# Vartalap v3 — Sync Protocol Specification

**Status:** v1.0 (2026-04-14)
**Branch:** `feat/v3-foundation`
**Scope:** wire protocol between v3 clients (`packages/spike_sync/`) and
chat-server (`profile-ms`, `message-ms`, `connection-gateway`,
`notification-ms`, `delivery-manager`).

This is a **protocol spec**, not an implementation guide. A server
engineer implements the chat-server side from this doc alone. A client
engineer implements the outbound/inbound path from this doc alone. The
two roles MUST NOT read each other's source to fill gaps in this doc —
gaps are bugs in the doc, filed as issues against it.

---

## 1. Purpose and scope

This document is the wire protocol between Vartalap v3 clients and
chat-server. The sync surface is split into two transports with
deliberately different jobs:

- **WebSocket** carries opaque chat-content payloads. The server
  validates routing (membership, sequencing, dedup, session) but
  **never parses the inner payload bytes**. Adding a new chat-content
  type does not require a server change.
- **REST** handles operations the server has to interpret because they
  mutate server-owned state: channel CRUD, membership changes, profile
  edits, push topic registration, contact discovery, auth.

Both transports share **one client-side outbound queue** (per
`SPIKE_B_SYNC.md`). The scheduler dispatches each queued op over the
right transport; offline queueing, retry, ordering, and dedup work
identically for both.

This doc does NOT prescribe internal structure on either side beyond
what the wire demands. RFC-style "MUST / SHOULD" applies where
behavior is mandated.

---

## 2. Terminology

- **envelope** — Unit of opaque chat-content delivery. One
  `Envelope` proto per user-intent action. Contains routing fields
  (server's concern) and a `payload` bytes blob (client's concern).
  See `proto/v3-envelope.proto`.
- **payload** — Opaque bytes inside an envelope. Server never parses.
  Suggested client-to-client schema in
  `proto/v3-chat-payload.proto`.
- **op_id** — UUIDv7 generated on the client at op-creation time.
  Stable across retries. The canonical dedup key for both WS
  envelopes and REST writes.
- **resource_id** — The entity an op operates on. For WS envelopes,
  always `channel_id`. For REST writes, the entity being mutated
  (channel id, user id).
- **resource_seq** — Monotonic per-`(user_id, resource_id)` sequence
  number tracked on the client. Increments once per op enqueued.
  Never reset.
- **outbound queue** — Client-side `outbound_ops` table (see
  `SPIKE_B_SYNC.md` §3). Persistent. Authoritative for "what still
  needs to be sent." Holds both WS envelopes AND mutating REST calls.
- **undelivered queue** — Server-side Redis FIFO per recipient
  `user_id`. Envelopes the server could not deliver because the
  recipient's WS connection is not currently open.
- **projection** — Client-side current-state view materialized from
  the event log (see `SPIKE_A_LOCAL_STORE.md`). Updated in the same
  transaction as event append.
- **tombstone** — A local-only projection marker that a resource has
  been deleted/edited, pending server confirmation. See §9.
- **server-stamped fields** — `sender_user_id`, `server_timestamp_ms`,
  `delivery_sequence` on the Envelope. Absent on client→server,
  populated by the server before fanout.

---

## 3. Identity binding

Recap from `AUTH_CONTRACT.md` §2 and
`V3_ARCHITECTURE.md` decision 7:

- **`user_id`** is the canonical user identifier. 36 bits, encoded as
  9 lowercase hex chars (e.g., `"a3f2e8c5d"`). Server-assigned at
  signup, immutable. **Every routing field on the wire references
  users by `user_id`** — not by username, not by phone.
- **`username`** is the optional discovery handle. Set/changed via
  `PATCH /v3.0/users/me` (AUTH_CONTRACT §4.5). Never appears as a
  wire identifier on the sync surface.
- **`phone`** is the login handle. Never appears on the sync wire.
- **`accesskey`** is the session credential issued by `POST
  /v3.0/auth/otp/verify`. Opaque UUID. Bearer.

**Every sync op MUST be authenticated.** Unauthenticated ops MUST be
rejected by the server before any side-effect (connection refused on
WS handshake, HTTP 401 on REST).

**UUIDv7 user_id binding.** Every `op_id` embeds the user's 36-bit
`user_id` per `SPIKE_B_SYNC.md` §4. The prefix is assigned by the
server at first OTP signup and returned on every `/verify` and
`/session/refresh` response (field `user_id`, see AUTH_CONTRACT §2.7,
§3.2, §4.3). The client MUST store it in `flutter_secure_storage`. The
server MUST validate on every inbound op:

```
op_id bits[62..26] == authenticated_session.user_id
```

Mismatch → `AckPermanentReject { reason: "prefix_mismatch" }`. Catches
tampering and accidental cross-user send-buffer bleed. (The reason
code retains the historical name `prefix_mismatch` even though the
field is now `user_id`; renaming would break wire-stable error code
contracts.)

---

## 4. The two-transport model

### 4.1 What goes where

| Operation | Transport | Why |
|---|---|---|
| Send / edit / delete / react / forward — chat content | WS | Opaque payload routing; server doesn't interpret |
| Create channel | REST `POST /v3.0/channels` | Server allocates channel-ms row, enrolls members |
| Add / remove channel members | REST `POST/DELETE /v3.0/channels/<id>/members` | Server updates channel-ms membership |
| Edit channel name / avatar | REST `PATCH /v3.0/channels/<id>` | Server updates channel-ms metadata |
| Edit own profile | REST `PATCH /v3.0/users/me` | Server validates uniqueness (username), updates profile-ms |
| Set push topic | REST `POST /v3.0/push/topic` | Server stores in notification-ms |
| OTP send / verify / refresh / revoke | REST `POST /v3.0/auth/...` | Server-managed session lifecycle |
| Contact discovery | REST `POST /v3.0/contacts/lookup` | Synchronous read |
| Get user profile | REST `GET /v3.0/users/<id>` | Synchronous read |
| Get own profile | REST `GET /v3.0/users/me` | Synchronous read |

### 4.2 Reads vs writes

**Writes** go through the client-side outbound queue regardless of
transport. The queue dispatches each op via the matching transport
adapter (WS for envelopes, REST for state mutations). Offline queueing,
retry, ordering, and dedup are uniform.

**Reads** (the `GET` and read-style `POST` endpoints — contact lookup,
profile fetch) do NOT go through the outbound queue. They block on the
network; they fail clearly when offline. The client surfaces a
loading or offline state to the user. Reads do not have offline
semantics — there is nothing to queue (no idempotent retry for "show
me a profile right now"; if you can't reach the server, you can't do
the lookup).

The outbound-queue-vs-direct split is documented per call site in §5
(WS) and §11 (REST writes).

### 4.3 REST writes still produce WS fanout

When a REST write mutates server-owned state that other users care
about (a new channel, a new member, a profile edit visible to channel
co-members), the server emits a synthetic `Envelope` to all affected
recipients on their active WS connections. This bridges the two
transports: a sender on REST, recipients on WS, no client-visible
seam. See §10.4.

### 4.4 Why this split

- **Server stays simple.** It does one thing per transport: routes
  opaque payloads on WS; interprets and validates server-state
  mutations on REST. Adding a new chat-content type does not touch
  the server. Adding a new channel-management feature does not touch
  the WS frame format.
- **Client stays uniform.** One outbound queue, one retry policy, one
  dedup window — across both transports. The scheduler doesn't know
  which transport a queued op will dispatch on until it picks one.
- **Offline-first survives.** Group creation, member adds, profile
  edits all queue locally and drain when online, same as chat
  payloads. The user never has to think "which features work
  offline."

---

## 5. WebSocket transport (chat-content payload routing)

### 5.1 Connection URL

```
wss://<host>/wss
```

Nginx strips the `/v3.0/` version prefix before routing to
`connection-gateway`. Clients use the URL as shown.

### 5.2 Handshake

Authentication happens **before WS upgrade**, on the HTTP upgrade
request. The client MUST pass the accesskey via the
`Sec-WebSocket-Protocol` header:

```
Sec-WebSocket-Protocol: accesskey.<accesskey-uuid>
```

**Server MUST:**
1. Parse the subprotocol header.
2. Validate the accesskey against `profile-ms`.
3. Reject the upgrade with HTTP `401 Unauthorized` if the accesskey
   is invalid, expired, or revoked. The response body MUST be the
   standard error envelope (§8):
   ```json
   {"error": {"code": "INVALID_ACCESSKEY", "message": "accesskey is not valid"}}
   ```
4. Only after successful validation, complete the WS upgrade and echo
   the subprotocol back in the response header.
5. Associate the connection with `(user_id, deviceId)` server-side.
   All envelopes on this connection are authenticated as that
   `user_id`. Envelopes MUST NOT carry `sender_user_id` from the
   client — server derives from connection identity and stamps it on
   fanout.

> **Hardening note.** The current chat-server WS handshake validates
> auth via `x-user` / `x-accesskey` headers plus an nginx subrequest.
> The new protocol replaces header-based WS auth with subprotocol-
> based auth so the handshake is complete in a single round trip and
> can be validated pre-upgrade without an nginx subrequest dance.

### 5.3 Frame format

Every WS frame carries a single `WsEnvelope` proto message
(`v3-envelope.proto`), serialized as protobuf binary. Frames are
binary WS frames (opcode 0x2), not text.

Frame body shape:

```
WsEnvelope {
  WsType type
  oneof body {
    EnvelopeBatch ops          // type=WS_OP, client→server
    AckBatch acks              // type=WS_ACK, server→client
    Envelope push              // type=WS_PUSH, server→client
    bool reauth_required       // type=WS_REAUTH_REQUIRED, server→client
    WsError error              // type=WS_ERROR, server→client
  }
}
```

Server MUST reject frames with unknown `WsType` by emitting a
`WS_ERROR` frame with `code=VALIDATION_FAILED` and closing the
connection with WS code 1002 (protocol error). Client MUST treat
unknown `WsType` on inbound as a protocol error and reconnect.

### 5.4 Op frames (client → server)

A `WsEnvelope` with `type=WS_OP` carries an `EnvelopeBatch` of
1-20 envelopes:

```
EnvelopeBatch {
  repeated Envelope envelopes
}

Envelope {
  string op_id              // UUIDv7
  string channel_id         // routing target
  uint64 resource_seq       // per-(user_id, channel_id) monotonic
  uint64 client_timestamp_ms
  bytes  payload            // opaque to server
  // sender_user_id, server_timestamp_ms, delivery_sequence absent on
  // client→server
}
```

**Max batch size: 20 envelopes per WS_OP frame.** Matches the
scheduler's `MAX_BATCH_SIZE` in `SPIKE_B_SYNC.md` §5a. Server MUST
reject frames with > 20 envelopes by emitting `AckPermanent {
reason: "validation_failed" }` for every envelope in the frame.

**Server MUST emit exactly one Ack per Envelope** in `envelopes`,
in any order. Client matches by `op_id`. Acks may arrive across
multiple `WS_ACK` frames.

### 5.5 Ack frames (server → client)

```
AckBatch { repeated Ack acks }

Ack {
  string op_id
  AckOutcome outcome         // SUCCESS | TRANSIENT | PERMANENT | AUTH_FAILURE
  string reason              // server-defined code (§8)
  uint64 retry_after_ms      // for TRANSIENT and rate_limited
  uint64 server_timestamp_ms // populated on SUCCESS
  uint64 delivery_sequence   // populated on SUCCESS
}
```

See §8 for the `reason` enumeration. Note: `reason` values are
limited to things the server can actually evaluate (membership,
sequencing, prefix, schema, rate, capacity). Chat-content reasons
(authorship, message existence) are NOT here — server doesn't
interpret payloads, so it cannot produce those.

### 5.6 Push frames (server → client)

A `WsEnvelope` with `type=WS_PUSH` carries a single `Envelope` with
all server-stamped fields populated. See §10.

### 5.7 Reauth-required frames (server → client)

A `WsEnvelope` with `type=WS_REAUTH_REQUIRED` and `body.reauth_required
= true`. Server MUST emit this immediately before closing the WS with
close code 4001 (accesskey expired) or 4002 (session revoked). See
§13.

### 5.8 Error frames (server → client)

Non-op-scoped protocol errors (malformed frame, unknown WsType):

```
WsError {
  string code      // UPPER_SNAKE_CASE, e.g. MALFORMED_FRAME
  string message   // human-readable
}
```

On protocol-level error the server MUST emit `WS_ERROR`, then MAY
close the connection with code 1002 (protocol error) or 1008 (policy
violation). Client reconnects per §13.

---

## 6. Ordering and serialization

Per-resource-serial-ACK-wait, per `SPIKE_B_SYNC.md` §5. Restated on
the wire:

**Client MUST:**
1. Assign monotonically increasing `resource_seq` values per
   `(authenticated_user_id, resource_id)`, starting at 1. Never reset,
   never skip, never reuse. For WS envelopes, `resource_id =
   channel_id`. For REST writes, `resource_id` is the targeted entity
   id (channel id, user id).
2. Dispatch at most one op per `resource_id` in flight at a time.
   Scheduler enforces via the §5 query (`SPIKE_B_SYNC.md`).
3. Dispatch ops on different `resource_id`s in parallel.

**Server MUST:**
1. Be stateless with respect to ordering. Do NOT buffer ops waiting
   for earlier ops. Do NOT sort incoming ops.
2. Track `max_seen_resource_seq` per `(user_id, resource_id)` for at
   least the lifetime of the dedup window (see §7). Storage: Redis
   hash keyed by `seq:<user_id>:<resource_id>`.
3. Validate on every op:
   - `incoming_resource_seq > max_seen_resource_seq` by exactly 1:
     accept, update max, process.
   - Strictly greater by more than 1 (skip): reject as
     `AckPermanent { reason: "out_of_order" }`. Client bug.
   - Equal or lower: dedup hit (op_id matches stored entry, return
     stored Ack) or client bug. See §7.

**Cross-resource ops: no coupling.** Different `resource_id`s are
independent.

**Cross-transport ordering: not coupled.** WS envelopes targeting
`channel_id=A` and a REST `add_members` targeting `channel_id=A`
both share `resource_id=A` and DO sequence against each other through
the same per-resource counter. The scheduler handles cross-transport
sequencing locally; the server enforces independently per
`(user_id, resource_id)` regardless of transport.

---

## 6a. Server's view of the payload

This section is the centerpiece of the v3 design. **Read it carefully.**

### 6a.1 Server's universe

The chat-server validates and acts on:

| What | Source of truth |
|---|---|
| Session identity (`user_id`) | profile-ms accesskey table |
| Channel membership | channel-ms |
| Per-`(user_id, channel_id)` `resource_seq` | message-ms Redis (`seq:<user_id>:<channel_id>`) |
| Op dedup | profile-ms or dedicated Redis (`dedup:<user_id>`) |
| Channel metadata (name, avatar, owner/admin roles) | channel-ms (REST writes only) |
| Profile (display name, avatar, status, username, phone) | profile-ms (REST writes only) |
| Push topic registrations | notification-ms (REST writes only) |
| Undelivered queue | delivery-manager Redis (`undelivered:<user_id>`) |

### 6a.2 What the server does NOT touch

The server has **NO knowledge of**:

- Message records, message bodies, message authorship.
- Message tombstones / deletion state.
- Per-message reaction state.
- Reply-to relationships.
- Forward-source provenance.
- Attachment metadata, sizes, integrity.
- Any other chat-content concept.

The `Envelope.payload` bytes are **opaque to the server**. The server
does not deserialize them, validate them, peek at them, log them
beyond byte-size, or evolve them. Adding a new chat-content type to
`v3-chat-payload.proto` does not touch the chat-server codebase.

### 6a.3 What the server validates per WS envelope

For every inbound `Envelope` on the WS wire, the server runs:

1. **Session.** Connection's authenticated `user_id` is non-null.
2. **Prefix.** `op_id` bits[62..26] == authenticated `user_id`. On
   mismatch: `AckPermanent { reason: "prefix_mismatch" }`.
3. **Membership.** Authenticated user is a member of `channel_id` in
   channel-ms. On non-member: `AckPermanent { reason: "forbidden" }`.
4. **Sequencing.** `resource_seq` strictly monotonic for `(user_id,
   channel_id)` per §6. On skip: `AckPermanent { reason:
   "out_of_order" }`. On retry within dedup window: return stored
   Ack.
5. **Schema.** `Envelope` proto deserializes successfully. On
   malformed: `AckPermanent { reason: "validation_failed" }`. Note:
   this is envelope-shape validation (op_id is a string, payload is
   bytes); the server does NOT validate the bytes inside `payload`.
6. **Rate.** Per-user / per-IP limits (§14). On breach: `AckPermanent
   { reason: "rate_limited", retry_after_ms: <ms> }`.
7. **Capacity.** Downstream availability (Redis fanout queue, etc.).
   On transient: `AckTransient { reason: "fanout_queue_full" |
   "downstream_timeout" | "storage_unavailable" }`.

That's the entire validation surface for chat-content envelopes. No
"forbidden" for editing someone else's message. No "gone" for editing
a deleted message. No "not_found" for reacting to a missing message.
The server does not know what those concepts mean on its wire.

### 6a.4 Recipient-side enforcement

Authorship, deletion state, message existence — these are enforced
at the **recipient** when it decodes the inbound `payload`. Each
client maintains a local event log (`SPIKE_A_LOCAL_STORE.md`) that
is the authoritative record of what that client has accepted.

When a recipient receives a `WS_PUSH` envelope, it:
1. Decodes `payload` per `v3-chat-payload.proto`.
2. Checks the inner `ChatPayloadType` against its local state:
   - `TYPE_MESSAGE_UPDATE` for `message_id=M`: apply only if local
     log shows M was authored by `Envelope.sender_user_id` AND M is
     not tombstoned. Otherwise silently drop.
   - `TYPE_MESSAGE_DELETE` for `message_id=M`: apply only if local
     log shows M was authored by `Envelope.sender_user_id`.
     Otherwise silently drop.
   - `TYPE_REACTION_ADD` / `TYPE_REACTION_REMOVE` for `message_id=M`:
     apply only if local log contains M (received or sent locally)
     and M is not tombstoned. Otherwise silently drop.
   - `TYPE_MESSAGE_CREATE`, `TYPE_MESSAGE_FORWARD`: apply
     unconditionally (the source-message metadata on FORWARD is not
     validated; recipients use it for UI only).
3. Records `op_id` in the channel's `op_id_seen` set so a re-fanout
   does not re-evaluate.

Silently dropped means: no error to the user, no signal back to the
server, no entry in any user-visible log. The recipient simply
ignores the payload. Per §6a.5, this is the only sane behavior given
the server's opacity.

### 6a.5 Implications for senders

A client that sends `TYPE_MESSAGE_DELETE` for a message it did not
author will:
- Receive `outcome: ACK_SUCCESS` from the server (server cannot
  detect the abuse — it didn't parse the payload).
- Have no effect on any other recipient's view (every recipient drops
  the inner payload locally per §6a.4).
- Have an effect on its OWN local view — the optimistic tombstone
  applied pre-send stays in the local store. There is no rollback
  signal because the server didn't reject.

For the legitimate-author case this is the intended behavior. For
the malicious-or-buggy case, the divergence is bounded: only the
buggy/malicious client sees the broken state, no one else does. The
protocol does not surface this to them — making it visible would
require the server to know the truth, which it doesn't.

### 6a.6 Why opaque payload is the right model

The alternative — server parses every payload, enforces chat-content
semantics — would force chat-server to become a chat-aware service.
That breaks decision 3 (`V3_ARCHITECTURE.md`: server is a relay, not
a store) and creates a painful coupling: every new client feature
needs a coordinated server release.

The opaque-payload model gives:
- **Server doesn't grow** as chat features grow. Adding pinned
  messages, polls, replies, ephemeral messages — none of those touch
  the chat-server codebase or proto.
- **Recipient-enforced authorization** moves the trust boundary to
  the side that has the data anyway (the recipient's local log).
- **Server cost stays bounded** to active-user-count scale, not
  message-count scale.

The cost: a malicious sender can send "delete" or "edit" payloads
they have no right to send, and they get success ACKs. Every other
recipient drops them. The malicious sender's local view diverges
from everyone else's. This is acceptable — it's the same outcome a
malicious user could achieve by patching their local client.

---

## 7. Idempotency and dedup

### 7.1 Server-side dedup window

Server MUST maintain a bounded dedup table per user, used for **both
WS envelopes and REST writes** that are queued through the outbound
queue (any op carrying an `op_id`):

- **Size:** 10,000 most recent op_ids per user.
- **TTL:** 7 days rolling (per-entry).
- **Storage:** Redis, key `dedup:<user_id>`. Suggested encoding: hash
  where field is `op_id` and value is the serialized outcome (ACK on
  WS, HTTP response on REST). FIFO eviction on overflow.

On an incoming op:
1. **`op_id` in dedup, marked applied:** return the stored outcome.
   No re-processing. No fanout.
2. **`op_id` in dedup, marked failed-permanent:** return the stored
   permanent reject. No re-processing.
3. **`op_id` not in dedup:** process normally. On completion, write
   the outcome.

Overflow: treat as case 3. Application-level idempotency MUST hold:
- Channel create with same client `channel_id` → 409 conflict on REST
  retry; idempotent error.
- Add members → set-union, adding existing members is a no-op.
- Profile patch → last-write-wins on the same fields.
- WS chat-content payloads → recipient-side dedup by `op_id` (§7.2)
  catches re-fanout.

### 7.2 Client-side receiver dedup

When a fanout `WS_PUSH` envelope arrives, the recipient client MUST
dedup before applying:

- Maintain `op_id_seen` per channel (see `SPIKE_A_LOCAL_STORE.md`).
- Bound: last 5,000 op_ids per channel, or last 30 days, whichever
  hits first.
- On push: if `op_id` is in the set, drop silently. If not, run the
  §6a.4 recipient-side enforcement gate, then either apply (record
  `op_id`) or drop (also record `op_id` so re-fanout does not
  re-evaluate).

This handles cases where the server fans out multiple times (e.g.,
undelivered-queue drain overlaps with new fanout during reconnect).

---

## 8. ACK shape and error taxonomy

### 8.1 AckOutcome (WS) and HTTP status (REST) parallel

The scheduler normalizes both into a single internal `AckOutcome`
enum (per the transport adapter design — `SPIKE_B_SYNC.md` §7).

| `AckOutcome` (WS proto) | HTTP status mapping (REST) | Meaning |
|---|---|---|
| `ACK_SUCCESS` | 2xx | Op applied. |
| `ACK_TRANSIENT` | 502, 503, 504 | Retry with backoff. |
| `ACK_PERMANENT` | 4xx (except 401) | Do not retry; surface error. |
| `ACK_AUTH_FAILURE` | 401 | Refresh accesskey, then retry. |

REST-specific: the body of a 4xx/5xx response uses the AUTH_CONTRACT
§11 envelope shape. The transport adapter parses `error.code` into
the same `reason` field exposed to the scheduler.

### 8.2 `reason` enumeration (server-defined)

These are the codes the server can produce. Both WS Ack frames and
REST error envelopes use the same code set where applicable.

| `reason` | Meaning | WS? | REST? | HTTP |
|---|---|---|---|---|
| `prefix_mismatch` | `op_id` user_id bits ≠ authenticated user. | ✓ | ✓ | 400 |
| `out_of_order` | `resource_seq` skipped. Client scheduler bug. | ✓ | ✓ | 400 |
| `forbidden` | User lacks server-verifiable permission. WS: not a member of `channel_id`. REST: lacks owner/admin role on a channel write, attempting to PATCH another user, etc. | ✓ | ✓ | 403 |
| `not_found` | Server-verifiable resource doesn't exist. REST: channel id unknown, user_id unknown. WS: channel_id unknown to channel-ms. | ✓ | ✓ | 404 |
| `gone` | Server-verifiable resource was deleted. REST: editing a deleted channel. | (rare) | ✓ | 410 |
| `resource_id_taken` | Client-supplied id collides. REST: create_channel with collision (~10⁻¹² with UUIDv7). | — | ✓ | 409 |
| `validation_failed` | Schema violation. WS: malformed Envelope or unknown WsType. REST: malformed JSON, missing required field. | ✓ | ✓ | 400 |
| `precondition_failed` | Server-side invariant. REST: group cap exceeded on add_members. | — | ✓ | 412 |
| `rate_limited` | Per-user or per-IP rate-limit hit (§14). | ✓ | ✓ | 429 |
| `server_busy` | Server overloaded. | ✓ | ✓ | 503 |
| `storage_unavailable` | Downstream DB/cache unavailable. | ✓ | ✓ | 503 |
| `downstream_timeout` | Internal microservice call timed out. | ✓ | ✓ | 504 |
| `fanout_queue_full` | Delivery-manager Redis queue saturated. | ✓ | — | — |

**Notably absent** from this list: anything about message authorship,
message existence, reaction state, forward sources. Per §6a, the
server does not interpret payloads, so it cannot evaluate those.
Recipient-side enforcement (§6a.4) handles them silently.

`rate_limited` carries `retry_after_ms`. Client rolls back the
optimistic projection if applied (same as permanent) but MAY
re-enqueue after the delay.

### 8.3 Auth failure

```
Ack { op_id: "...", outcome: ACK_AUTH_FAILURE }
```

(REST equivalent: HTTP 401 with `{"error": {"code":
"INVALID_ACCESSKEY", ...}}`.)

Accesskey is expired, revoked, or invalid. Client MUST:
1. Pause the scheduler (Flow A stops dispatching).
2. Trigger accesskey refresh per AUTH_CONTRACT.md §4.3.
3. On successful refresh, resume the scheduler. Paused ops become
   dispatchable on the next Flow A tick.
4. If refresh fails (e.g., refresh token revoked), log the user out
   locally.

### 8.4 Standard error envelope (REST)

For REST errors that aren't per-op responses (401 before batch
processing, 400 malformed JSON, 413 body too large), the server uses
the AUTH_CONTRACT §11.1 envelope:

```json
{
  "error": {
    "code": "INVALID_ACCESSKEY",
    "message": "accesskey is not valid",
    "retryAfterSec": 30
  }
}
```

`code` is UPPER_SNAKE_CASE. `retryAfterSec` is optional, present on
429 / 423.

---

## 9. Tombstones and undo

Per `V3_ARCHITECTURE.md` decision 11, five user-action kinds have a
5-second client-side undo window before they hit the wire:

- `delete_message` (sent as a `TYPE_MESSAGE_DELETE` chat payload)
- `edit_message` (sent as a `TYPE_MESSAGE_UPDATE` chat payload)
- `delete_chat` (local-only; never wired)
- `clear_chat_history` (local-only; never wired)
- `remove_member` (sent as REST `DELETE /v3.0/channels/<id>/members/<user>`)

**Client-side behavior:**
1. On user action, commit a tombstone to the local event log and
   update projections optimistically. Start a 5-second timer.
2. During the 5 seconds, show a toast with "Undo." If user taps undo,
   append a compensating event to the log, revert projection, do NOT
   enqueue a sync op.
3. After 5 seconds with no undo, enqueue the corresponding op in
   `outbound_ops` and let the scheduler dispatch it (WS for chat
   payloads, REST for member removal).

**Wire behavior:** once enqueued and dispatched, these ops are
first-class. Server has no concept of "undo" or "5-second delay."
`delete_chat` and `clear_chat_history` are local-only (server has no
message history; see V3_ARCHITECTURE decision 3) and never hit the
wire.

**Rollback on permanent reject.** For the REST `remove_member`, the
server CAN reject (`forbidden` if requester lost admin role
mid-flight, `not_found` if the channel was deleted between enqueue
and drain). On rejection, the client appends a compensating event
that reverts the tombstone and surfaces the failure
(SPIKE_B_SYNC.md §10).

**No rollback for recipient-dropped chat payloads.** Per §6a,
`TYPE_MESSAGE_UPDATE` / `TYPE_MESSAGE_DELETE` are not server-
verifiable. The server returns `ACK_SUCCESS` regardless. Recipients
silently drop unauthorized payloads. The sender's local optimistic
tombstone stays. For the legitimate-author case this is the intended
behavior; for the malicious-or-buggy case, see §6a.5.

**Implications for protocol:**
- Server MUST NOT expect a "commit" or "cancel" signal from the
  client; the wire arrival of the op IS the commit.
- Server MUST NOT treat any op as tentative. Ops are always final
  when received.

---

## 10. Inbound delivery (server → client)

When an op produces fanout (a chat-content envelope, a REST channel
mutation, a profile edit visible to channel co-members), the server
emits a `WS_PUSH` envelope to each affected recipient on their
active WS connection.

### 10.1 Chat-content fanout

A WS envelope from a sender, fanned out to other channel members.
The push frame is the **same Envelope** the sender sent, with
server-stamped fields populated:

```
WsEnvelope {
  type: WS_PUSH
  body.push: Envelope {
    op_id:                <sender's op_id>
    channel_id:           <sender's channel_id>
    resource_seq:         <sender's resource_seq>  // sender-scoped, opaque to recipient
    client_timestamp_ms:  <sender's value>
    payload:              <sender's opaque bytes>
    sender_user_id:       <server-stamped, authenticated sender's user_id>
    server_timestamp_ms:  <server-stamped>
    delivery_sequence:    <server-stamped, per-channel monotonic>
  }
}
```

The recipient resolves `sender_user_id` to a display name per
AUTH_CONTRACT §2.4 (contact-book name first, then `username` from a
cached `GET /v3.0/users/<sender_user_id>` lookup, then phone, then
empty placeholder).

The recipient MUST verify `op_id` user_id bits match
`sender_user_id` for tamper detection. On mismatch, drop silently
and log (this should be impossible — server stamps both — but
defends against compromised intermediaries).

### 10.2 REST-write fanout (the bridge)

When a REST write mutates server-owned state that other users care
about, the server emits a synthetic `WS_PUSH` envelope to all
affected members. The envelope's `payload` carries a server-defined
schema (NOT the same as `v3-chat-payload.proto`) signaling what
changed.

Rather than overload `Envelope.payload` with two different schemas,
v3.0 uses a separate **server-event payload**: the server-emitted
envelopes set a reserved `payload` shape clients distinguish by the
first byte (`0x53` for "server event") vs. client chat payloads
(any other first byte).

```
ServerEventPayload {
  uint32 version = 1;
  ServerEventType type = 2;
  oneof body {
    ChannelCreated channel_created = 10;
    ChannelMemberAdded member_added = 11;
    ChannelMemberRemoved member_removed = 12;
    ChannelEdited channel_edited = 13;
    ChannelDeleted channel_deleted = 14;
    ProfileEdited profile_edited = 15;
    UsernameChanged username_changed = 16;
  }
}

enum ServerEventType {
  SERVER_EVENT_UNSPECIFIED = 0;
  CHANNEL_CREATED = 1;
  CHANNEL_MEMBER_ADDED = 2;
  CHANNEL_MEMBER_REMOVED = 3;
  CHANNEL_EDITED = 4;
  CHANNEL_DELETED = 5;
  PROFILE_EDITED = 6;
  USERNAME_CHANGED = 7;
}
```

Each variant carries the changed fields:
- `ChannelCreated`: `channel_id`, `kind`, `name`, `members`, `creator`.
- `ChannelMemberAdded`: `channel_id`, `members[]`.
- `ChannelMemberRemoved`: `channel_id`, `member`.
- `ChannelEdited`: `channel_id`, `name?`, `avatar_url?`.
- `ChannelDeleted`: `channel_id`.
- `ProfileEdited`: `user_id`, `display_name?`, `avatar_url?`,
  `status_text?`.
- `UsernameChanged`: `user_id`, `new_username` (may be null).

The server treats these envelopes the same as chat-content envelopes
on the wire: same `Envelope` proto, same fanout rules, same
undelivered-queue behavior. The client distinguishes by inspecting
the first byte of `payload` and routing to the right decoder. Server-
event payloads bypass the §6a.4 recipient-side authorization (they
are server-authored and authoritative).

### 10.3 Fanout rules

**Server MUST:**
1. Compute the recipient set per op type:
   - WS chat-content envelopes: all channel members except sender.
   - REST `POST /v3.0/channels`: all `members` (creator included).
   - REST `add_members`: existing members + newly added.
   - REST `remove_member`: remaining members + the removed member
     (so the removed user's client knows to leave).
   - REST `edit_channel`: all channel members.
   - REST `PATCH /v3.0/users/me` with `displayName` / `avatarUrl` /
     `statusText`: all users sharing at least one channel with the
     editor. Scope: v3.0 only.
   - REST `PATCH /v3.0/users/me` with `username`: same scope as
     above. The new username may be null.
2. For each online recipient (active WS connection in connection-
   gateway), emit the push frame immediately.
3. For each offline recipient, enqueue the push frame in the
   undelivered queue (§11).
4. Senders MUST NOT receive fanout for their own ops on the same
   device. Cross-device fanout is deferred to v3.1.

### 10.4 Push frame ordering

Server MUST emit push frames in `delivery_sequence` order per
channel to a given recipient. Cross-channel ordering is not
guaranteed.

Recipients MAY observe out-of-order arrival across reconnects if a
drain of the undelivered queue interleaves with live fanout — `op_id`
dedup ensures correctness regardless.

### 10.5 Recipient client requirements

On receipt of a `WS_PUSH` envelope, the recipient client MUST:
1. Check `op_id` against the channel's `op_id_seen` set.
2. If seen: drop silently.
3. If new: inspect `payload[0]` to route:
   - `0x53`: decode as `ServerEventPayload`. Apply unconditionally
     (server-authored). Update local channel-ms-mirror, projections.
     Record `op_id` in `op_id_seen`.
   - Otherwise: decode as `ChatPayload`. Apply the §6a.4 recipient-
     side authorization gate. If the gate passes, apply to local
     event log and projections; if not, drop. Either way, record
     `op_id` in `op_id_seen`.
4. Server does not ACK its own push frames. No client-to-server
   acknowledgment is required at the protocol level — the
   undelivered queue is drained purely on WS connection
   establishment (§11.3).

---

## 11. REST writes (server-state mutations)

REST writes are the second arm of the sync surface. They share the
client-side outbound queue with WS envelopes and are dispatched
through a parallel transport adapter.

### 11.1 Endpoints

| Endpoint | Method | Effect | Fanout? |
|---|---|---|---|
| `/v3.0/channels` | POST | Create channel | yes (§10.2) |
| `/v3.0/channels/<id>` | PATCH | Edit channel name/avatar | yes |
| `/v3.0/channels/<id>` | DELETE | Delete channel (owner only) | yes |
| `/v3.0/channels/<id>/members` | POST | Add members | yes |
| `/v3.0/channels/<id>/members/<user_id>` | DELETE | Remove member | yes |
| `/v3.0/users/me` | PATCH | Edit own profile (incl username) | yes |
| `/v3.0/push/topic` | POST | Register/replace ntfy topic | no |

REST READS (no queue, no fanout): `/v3.0/users/me` GET,
`/v3.0/users/<id>` GET, `/v3.0/contacts/lookup` POST. Auth endpoints
(`/v3.0/auth/...`) are session-management, not in the queue.

### 11.2 Request shape

All REST writes carry these standard fields in the body:

```json
{
  "op_id": "01f00000-7000-8000-8abc-...",
  "resource_seq": 42,
  "client_timestamp_ms": 1744675200000,
  ... endpoint-specific fields ...
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op_id` | string (UUIDv7) | yes | Dedup key. Same enforcement as WS envelopes (§7.1, prefix bits per §3). |
| `resource_seq` | integer | yes | Per-`(user_id, resource_id)` monotonic. `resource_id` is the targeted entity id (path parameter). |
| `client_timestamp_ms` | integer | no | Advisory. |

Endpoint-specific fields are documented per endpoint in
AUTH_CONTRACT.md (auth, profile, push) and in this section (channel
ops below).

### 11.3 Channel CRUD endpoints

#### `POST /v3.0/channels`

Create a channel.

**Headers:** `Authorization: Bearer <accesskey>`
**Body:**
```json
{
  "op_id": "...",
  "resource_seq": 1,
  "channel_id": "01efabcd-7000-8000-8abc-...",
  "kind": "group",
  "name": "Weekend Trip",
  "avatar_url": null,
  "members": ["a0b1c2d3e", "b1c2d3e4f", "c2d3e4f5a"]
}
```

| Field | Constraint |
|---|---|
| `channel_id` | Client-generated UUIDv7. Must embed authenticated user's user_id bits per §3. |
| `kind` | `"one_to_one"` or `"group"`. For one_to_one, `members` must be exactly 2 (creator + peer). |
| `name` | Required for `group`, ignored for `one_to_one`. |
| `members` | List of `user_id` (9 hex chars). Creator MUST be included; server validates membership against the authenticated user. |

`resource_id` for sequencing is `channel_id`. `resource_seq` starts
at 1 (this is the first op on a fresh channel id).

**Success 201:**
```json
{
  "channel_id": "01efabcd-...",
  "created_at": 1744675200123
}
```

**Errors:** `forbidden` (authenticated user not in `members`),
`resource_id_taken` (collision),
`validation_failed`, `prefix_mismatch`, `out_of_order`,
`rate_limited`.

#### `POST /v3.0/channels/<channel_id>/members`

Add members.

**Body:**
```json
{
  "op_id": "...",
  "resource_seq": 7,
  "members": ["e4f5a6b7c", "f5a6b7c8d"]
}
```

`resource_id` for sequencing is `channel_id`.

**Success 200:**
```json
{ "member_count": 12 }
```

**Errors:** `forbidden` (not owner/admin), `precondition_failed`
(group cap exceeded), `not_found` (channel doesn't exist),
`validation_failed`, `out_of_order`, `rate_limited`.

#### `DELETE /v3.0/channels/<channel_id>/members/<user_id>`

Remove a member.

**Body:**
```json
{
  "op_id": "...",
  "resource_seq": 8
}
```

**Success 200:**
```json
{ "member_count": 11 }
```

**Errors:** `forbidden`, `not_found`, `out_of_order`, `rate_limited`.

#### `PATCH /v3.0/channels/<channel_id>`

Edit channel metadata.

**Body:**
```json
{
  "op_id": "...",
  "resource_seq": 9,
  "name": "Weekend Trip 2.0",
  "avatar_url": null
}
```

**Success 200:** echoes the updated channel.

**Errors:** `forbidden`, `not_found`, `gone`, `validation_failed`,
`out_of_order`, `rate_limited`.

#### `DELETE /v3.0/channels/<channel_id>`

Delete a channel (owner only).

**Body:**
```json
{
  "op_id": "...",
  "resource_seq": 10
}
```

**Success 204:** no body.

**Errors:** `forbidden`, `not_found`, `out_of_order`, `rate_limited`.

### 11.4 Profile, push, auth endpoints

See `AUTH_CONTRACT.md`. The wire shape there
is canonical; this doc adds the `op_id` and `resource_seq` fields to
the documented bodies for queue compatibility.

For `PATCH /v3.0/users/me`, `resource_id` is `user_id` (the
authenticated user's own).
For `POST /v3.0/push/topic`, `resource_id` is `user_id`.

### 11.5 REST batching

REST writes are NOT batched in v3.0 — one HTTP request per op. The
WS path uses `EnvelopeBatch` precisely because chat-content
throughput justifies it; REST writes are infrequent enough (channel
edits, member changes, profile updates) that per-request HTTP
overhead is acceptable. Revisit if telemetry shows otherwise.

### 11.6 Background drain

When the WS connection is unavailable (app backgrounded, network
flapping), the scheduler dispatches REST writes in the background
exactly the same way. There is no "REST batch" endpoint for
chat-content envelopes — chat content is WS-only — but REST writes
proceed independently of WS state.

---

## 12. Push notification path

Push is **independent of the sync wire**. ntfy-direct per
`V3_ARCHITECTURE.md` decision 6.

### 12.1 Wake notification

When the server enqueues an envelope into the undelivered queue for
a recipient AND the recipient has no active WS connection, the
server MUST publish a minimal wake notification to the recipient's
registered ntfy topic:

- Body: short, generic. Example: `"New activity"`. MUST NOT contain
  message content.
- Title: `"Vartalap"`.

Rationale: ntfy topics are not E2E encrypted at v3.0; the client
will reconnect WS and drain the undelivered queue, which carries the
full payload.

Coalescing: if multiple envelopes are enqueued in quick succession,
the server MAY debounce the ntfy publish (no more than one wake per
5 seconds per recipient).

### 12.2 Topic registration

`POST /v3.0/push/topic` per AUTH_CONTRACT §5. The topic is keyed by
`(user_id, deviceId)`.

### 12.3 Client reconnect flow

ntfy Android app receives the wake → fires intent → Vartalap process
wakes → reopens WS → drain protocol runs (§11.3 below, undelivered
queue). No client-initiated request to the ntfy topic other than
registration.

---

## 13. WebSocket re-authentication

Accesskeys have a TTL (AUTH_CONTRACT §4.1: 30 days). The client
proactively refreshes at < 48 hours per AUTH_CONTRACT §4.1.

### 13.1 Mid-connection expiry

If the server detects an expired accesskey during op processing:
1. Server MUST emit `WS_REAUTH_REQUIRED`.
2. Server MUST close the connection with WS close code **4001**
   (`accesskey_expired`).
3. Ops already accepted before expiry MAY have been processed
   partially. Server MUST NOT roll back accepted ops.

### 13.2 Mid-connection revocation

If the accesskey is revoked while the connection is open
(`POST /v3.0/auth/session/revoke` from another client, or
operator action):
1. Server MUST emit `WS_REAUTH_REQUIRED`.
2. Server MUST close with WS close code **4002** (`session_revoked`).

### 13.3 Client response

On `WS_REAUTH_REQUIRED` or 4001/4002 close:
1. Scheduler pauses (Flow A stops dispatching).
2. Client triggers accesskey refresh per AUTH_CONTRACT §4.3 (4001)
   or returns user to login (4002).
3. On 4001 success, reconnect WS with new accesskey per §5.2; on
   4002, clear local credentials.
4. After WS reconnect, the undelivered-queue drain runs (§11.3 of
   the undelivered queue section below — TODO unify numbering),
   then scheduler resumes.

In-flight ops with no ACK at disconnect are handled by Flow C
timeout sweep (`SPIKE_B_SYNC.md` §5). Dedup by `op_id` (§7) ensures
the server-processed ops are not duplicated on retry.

### 13.4 Proactive refresh

Per AUTH_CONTRACT §4.1: refresh when < 48 hours remain. Refresh on
foreground transition, scheduler startup, daily timer. Refresh MUST
NOT force a WS reconnect — current connection keeps its old
accesskey until expiry; new accesskey is used on next reconnect.

---

## 14. Rate limits

### 14.1 WS sync envelope limits

Enforced server-side per user, across all WS connections:

| Scope | Limit | Window |
|---|---|---|
| Per-user sustained | 30 envelopes/sec | rolling 1s |
| Per-user burst | 100 envelopes/sec | rolling 10s |
| Per-IP sustained | 100 envelopes/sec | rolling 1s |

### 14.2 REST write limits

Enforced server-side per user, per endpoint family:

| Endpoint family | Limit | Window |
|---|---|---|
| Channel writes (create/edit/delete/members) | 60/min | rolling 60s |
| Profile writes (`PATCH /users/me` non-username) | 50/hour | per AUTH_CONTRACT §10.6 |
| Username changes | 1/90 days | per AUTH_CONTRACT §10.6 |
| Push topic registration | 20/hour | rolling 60min |

### 14.3 Read limits (informational)

GET endpoints have looser limits, documented in AUTH_CONTRACT
(contact lookup §7.4). Reads do not go through the outbound queue.

### 14.4 Enforcement

On breach: `AckPermanent { reason: "rate_limited", retry_after_ms:
<ms> }` (WS) or HTTP 429 with the same envelope (REST). Client
honors `retry_after_ms` via the scheduler's backoff
(`SPIKE_B_SYNC.md` §6). Client MUST NOT treat `rate_limited` as
terminal — the op re-enters the dispatchable pool after the delay.

---

## 15. Failure recovery scenarios

Each describes a realistic failure; what the client does; what the
server does; what guarantees hold.

### 15.1 Client restart with `in_flight` ops

Scenario: app killed after dispatch, before ACK / HTTP response.
- Client: on restart, `outbound_ops` rows with `status = in_flight`
  and old `dispatched_at` are picked up by Flow C timeout sweep
  (`SPIKE_B_SYNC.md` §5), transitioned to `retrying`,
  re-dispatched. Transport adapter re-selects (WS if connected,
  REST otherwise).
- Server: retry arrives with same `op_id`. Dedup window (§7.1)
  returns the stored outcome OR processes normally if outside the
  window (in which case application-layer idempotency holds).
- No protocol action needed.

### 15.2 Server restart with pending ACKs / responses

Scenario: server killed before emitting ACKs / 2xx responses for
ops it accepted (or while they were queued downstream).
- Server: connection-gateway drops connections; Redis state
  persists (dedup, undelivered queue, seq tracking, channel-ms).
- Client: WS disconnect detected, Flow C times out in-flight ops,
  re-dispatches. REST in-flight ops time out per the HTTP client
  timeout, also re-dispatch.
- Server on retry: dedup hits where the op made it far enough
  pre-crash; otherwise re-processes with idempotency safety.

### 15.3 Network partition mid-batch

Scenario: WS send succeeded, some ACKs received, then connection
drops.
- Client: ACKed ops are deleted from `outbound_ops`; remaining stay
  `in_flight` until Flow C times them out.
- Server: no action needed.
- On reconnect: remaining ops re-dispatch. Dedup hits for any the
  server processed during the partition.

### 15.4 Accesskey expires mid-batch

Scenario: accesskey expires after some ops processed but before
others.
- Server: emits success / transient / permanent ACKs (or HTTP) for
  ops processed before expiry detection; emits `auth_failure` /
  HTTP 401 for ops after; sends `WS_REAUTH_REQUIRED` and closes
  (WS) or returns 401 (REST).
- Client: handles per-op outcomes normally; for `auth_failure`
  ops, pauses scheduler, refreshes accesskey, resumes, retries.
  Dedup handles any ops the server may have processed after
  emitting `auth_failure`.

### 15.5 User logs in on a different device (v3.1)

Out of scope for v3.0 (single-device). Documented as a known
limitation.

### 15.6 User clears local data / reinstalls

Scenario: user deletes app data or reinstalls.
- Client: local event log and `outbound_ops` are gone. User re-runs
  OTP, gets new accesskey. `user_id` is the same (per AUTH_CONTRACT
  §2; the prefix is bound to the account, not the install — re-OTP
  on the same phone resolves to the same `user_id`).
- Server: has no message history to replay. chat-server is a
  relay, not a store. Any undelivered frames in the Redis queue
  from before the reinstall MAY still be drained on the first WS
  connect. Frames acked and fanned out before the wipe are gone
  forever on this device.
- User impact: message history is lost. Warned on the v3 first-
  launch consent screen (V3_ARCHITECTURE release model).

### 15.7 Server rejects a REST write mid-cascade

Scenario: a REST `add_members` is rejected after the client already
queued WS chat-content envelopes for that channel.
- Server: returns `forbidden` (or `not_found`) on `add_members`.
  The WS envelopes the client already queued are unaffected at the
  server level (they target an existing channel; sender is still a
  member).
- Client: per-resource cascade in `SPIKE_B_SYNC.md` §8 applies
  ONLY when the failure is on the same `resource_id`. For
  `add_members(channel=A)` rejected, the cascade affects subsequent
  ops queued against `resource_id=A` — but a `send_message` to A is
  already targeting an existing channel, so it MAY succeed
  independently. Client cascade logic should differentiate:
  rejection of a structural channel op does not invalidate
  chat-content ops on the same channel unless the channel itself
  is gone.

### 15.8 Undelivered queue overflow

Scenario: recipient offline long enough that > 10,000 frames
accumulate.
- Server: drops oldest on overflow (§11.2 below — undelivered queue).
- Client: on reconnect, drains what remains. Does NOT know what
  was dropped. Timeline shows a gap.
- v3.0: known limitation. v3.1 plans a resync path.

### 15.9 Chat payload from a buggy / malicious sender

Scenario: a sender emits `TYPE_MESSAGE_DELETE` for a message they
did not author.
- Server: validates routing (sender is channel member, prefix
  matches, sequence in order, schema valid). Sends Ack success.
- Recipients: decode payload, run §6a.4 gate, drop silently.
- Sender: sees their own optimistic tombstone stay applied locally
  (no rollback signal). No effect on other recipients' views.
- Per §6a.5 this is the intended graceful degradation.

---

## 16. Server-side state and statelessness

The chat-server maintains the following state. Everything NOT in
this list is the client's problem.

| State | Service | Storage | TTL / Bound |
|---|---|---|---|
| User profile (incl. nullable username) | profile-ms | MongoDB (authDB) | forever (until account deletion) |
| Channel metadata | channel-ms | MongoDB | forever |
| Channel membership | channel-ms | MongoDB | forever |
| Active WS connections | connection-gateway | in-memory + Redis pubsub | connection lifetime |
| Undelivered queue | delivery-manager | Redis (`undelivered:<user_id>`) | 30 days rolling per user |
| Dedup window (WS + REST) | profile-ms (new) | Redis (`dedup:<user_id>`) | 10k entries per user, 7 days rolling |
| Resource seq tracking | message-ms | Redis (`seq:<user_id>:<resource_id>`) | aligned with dedup window |
| ntfy topic registrations | notification-ms (new) | MongoDB, keyed by `(user_id, deviceId)` | forever (until logout or replacement) |
| OTP sessions | profile-ms | MongoDB (authDB) | 1h post-expiry |
| Accesskey → user_id mapping | profile-ms | in-memory cache + MongoDB | accesskey lifetime |
| Refresh tokens | profile-ms | MongoDB | 90 days |
| Tombstones (deleted accounts) | profile-ms | MongoDB | forever (`(user_id, username?)` reserved) |

**NO message history. NO long-term event log. NO per-message
projection state. NO chat-payload interpretation.** The server is a
typed envelope router. This is load-bearing: it makes the client's
offline-first design work, makes server costs scale with active-user
count rather than message count, and makes new chat features
deployable without server changes.

**Compliance check for server engineers.** If implementing this
spec leads you to reach for "let me just parse the payload to
help recipients" or "let me just store the last N messages per
channel," stop and re-read V3_ARCHITECTURE.md decision 3 and §6a
of this doc. The chat-server is opaque to chat semantics. That is
the point.

---

## 17. Cross-references

- **`proto/v3-envelope.proto`** — server's wire
  schema. Canonical source for `Envelope`, `Ack`, `WsEnvelope`,
  `WsType`, `AckOutcome`.
- **`proto/v3-chat-payload.proto`** — reference
  client-to-client payload schema. NOT imported by the server.
- **`AUTH_CONTRACT.md`** — accesskey shape,
  OTP endpoints, profile/push/contacts/account-delete REST
  endpoints, error envelope shape, rate limits.
- **`docs/V3_ARCHITECTURE.md`** — load-bearing decisions (offline-
  first, per-resource ordering, ntfy push, auth contract, opaque-
  payload model, idempotency, tombstones).
- **`docs/SPIKE_B_SYNC.md`** — client scheduler architecture,
  `outbound_ops` table (now with transport discriminator), Flow
  A/B/C, batching, backoff, retry limits, dead-letter, transport
  adapters for WS and REST.
- **`docs/SPIKE_A_LOCAL_STORE.md`** — `events` table, projections,
  `op_id_seen` client-side dedup table.

---

## 18. Open items deferred to v3.1

- **Multi-device fanout.** v3.0 = one active device per user.
- **End-to-end encryption.** v3.0 server reads payload bytes for
  routing only (size, fanout target) but the bytes are still
  cleartext. E2E is a v4+ topic.
- **Full resync after long offline (> 30 days).** Currently no
  recovery path for lost fanout frames beyond the undelivered TTL.
- **Stateless WS authentication via signed token (JWT).** Considered
  and rejected for v3.0 (see AUTH_CONTRACT §15).
- **Presence, read receipts, typing indicators.** Deferred per
  V3_ARCHITECTURE out-of-scope.
- **Per-op priority / QoS hints.** All ops processed at the same
  priority.
- **Server-side payload introspection for moderation / spam.**
  Server does not parse payloads, so cannot moderate by content.
  v4+ topic — likely requires a separate moderation service that
  receives a copy of relevant payloads with explicit scope.
- **Unified WS transport via system-channel message bus.** v3.0
  has two transports (WS for chat content, REST for server-state
  mutations). A v3.1 evolution collapses to one WS transport: REST
  writes become envelopes targeting a reserved `channel_id =
  "system"`. Connection-gateway publishes these to a NATS/Kafka
  topic that a new system-consumer service drains, dispatching to
  channel-ms / profile-ms / notification-ms via the same internal
  APIs the REST endpoints use today. ACKs flow back via a reply
  topic; fanout for affected recipients reuses the existing
  delivery-manager path. Client benefits: single transport, single
  connection, single dispatch path, simpler scheduler. Server
  benefits: connection-gateway stays pure opaque routing;
  system-consumer scales and fails independently; NATS/Kafka
  provides natural backpressure. Open items for v3.1 design:
  `proto/v3-system-ops.proto` payload schema (the system consumer
  DOES parse these, unlike chat payloads); auth-refresh bootstrap
  (refresh still needs REST to exist pre-WS-handshake); coupling
  of background-drain reliability to WS availability. v3.0 ships
  the dual-transport model documented in this file; v3.1 migrates
  without breaking the wire (REST endpoints keep working during
  the transition).

---

## 19. Decisions locked in this doc

| # | Decision | Value | Rationale |
|---|---|---|---|
| 1 | Undelivered-queue TTL | 30 days | Vacation/device-replacement coverage; bounded storage. |
| 2 | Max undelivered queue per user | 10,000 frames | Heavy-use outlier; beyond that, user needs resync. |
| 3 | Server dedup window | 10,000 op_ids per user, 7 days rolling | A week of heavy use; idempotency handles overflow. |
| 4 | WS sync rate limit | 30 env/sec sustained, 100 env/sec burst per user | Drain bursts; abuse cap. |
| 5 | Proactive accesskey refresh | < 48 hours TTL remaining | Foreground refresh; avoids surprise reauth. |
| 6 | WS close codes | 4001 (expired), 4002 (revoked), 4003 (rebind invalidation, AUTH_CONTRACT §6.5) | Application-defined range. |
| 7 | Max WS batch | 20 envelopes per WS_OP frame | Matches `MAX_BATCH_SIZE` (`SPIKE_B_SYNC.md` §5a). |
| 8 | WS subprotocol auth | `accesskey.<uuid>` via `Sec-WebSocket-Protocol` | Pre-upgrade validation; one round trip. |
| 9 | Two-transport split | WS = opaque payload routing, REST = server-state mutations | Server stays simple; client offline-first; chat features evolve without server changes. |
| 10 | Single outbound queue across transports | `outbound_ops` includes WS envelopes AND mutating REST writes | Uniform retry, dedup, ordering; offline-first survives for both. |
| 11 | Reads not queued | GET / contact-lookup / auth endpoints block on network | Reads have no offline semantics; nothing to retry idempotently. |
| 12 | REST writes produce WS fanout | Server emits `ServerEventPayload` envelopes to affected members | Bridges the two transports; recipients see one stream regardless of sender's transport. |
| 13 | Server never parses chat payload | `Envelope.payload` is opaque bytes | Server stays simple; recipient enforces authorship/existence; new chat types add no server cost. |
| 14 | Recipient-enforced authorization | Chat-content authorship, message existence, reaction state checked client-side from local event log | Server has no state to enforce against; recipient's local log is authoritative. |
| 15 | First-byte payload discrimination | `payload[0] == 0x53` → `ServerEventPayload`; otherwise `ChatPayload` | Lets server-emitted envelopes share the same `Envelope` proto without needing a separate WsType. |
