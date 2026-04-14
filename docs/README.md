# Vartalap v3 docs

Single source of truth for v3 architecture, spike decisions, and results.

## Index

| Doc | Purpose |
|---|---|
| [V3_ARCHITECTURE.md](./V3_ARCHITECTURE.md) | v3 locked decisions (11 entries), architecture shape, release model, open questions, roadmap |
| [SPIKE_A_LOCAL_STORE.md](./SPIKE_A_LOCAL_STORE.md) | Local store decision — single SQLite with projection tables + outbound queue (Option C). Winner, runner-up, rejects |
| [SPIKE_A_SCHEMA.md](./SPIKE_A_SCHEMA.md) | Concrete client-side SQLite schema. Tables (channels, messages, reactions, contacts, op_id_seen, outbound_ops, snapshots), `message_state` machine, inbound/outbound flows, §6a.4 enforcement queries, migration strategy |
| [SPIKE_A_RESULTS_emulator_2026-04-14.md](./SPIKE_A_RESULTS_emulator_2026-04-14.md) | Profile-build emulator benchmark numbers backing the Spike A decision |
| [SPIKE_B_SYNC.md](./SPIKE_B_SYNC.md) | Sync package design — replaces `packages/taskq/`. Three-flow scheduler, WS+REST transports, batching, retry/backoff/dead-letter |

## Reading order

For a new contributor:
1. `V3_ARCHITECTURE.md` — the committed decisions.
2. `SPIKE_A_LOCAL_STORE.md` — why event-sourced, why single SQLite.
3. `SPIKE_B_SYNC.md` — how outbound sync is structured on top.

Benchmark numbers (`SPIKE_A_RESULTS_*`) are reference material, not required reading.

## Related

- [AUTH_CONTRACT.md](./AUTH_CONTRACT.md) (mirror of chat-server's authoritative copy) — v1.0, v3-greenfield: identity model (`user_id` canonical, `username` discovery handle, `phone` login), session refresh/revocation, push topic registration, WS subprotocol auth, contact discovery (SHA-256 hashed), logout/account-delete/phone-rebind, rate limits, error envelope.
- [proto/v3-envelope.proto](./proto/v3-envelope.proto) (mirror) — server's wire schema: Envelope, Ack, WsEnvelope, AckOutcome, WsType.
- [proto/v3-chat-payload.proto](./proto/v3-chat-payload.proto) (mirror) — reference client-to-client payload schema: ChatPayload, ChatPayloadType, Attachment, ForwardSource. Server never imports.
