/// Vartalap v3 local store.
///
/// Shape per `docs/SPIKE_A_SCHEMA.md`: projection tables hold
/// authoritative state, `outbound_ops` holds unsynced local actions,
/// `op_id_seen` is recipient-side inbound dedup. WAL pragmas applied on
/// open.
///
/// Domain logic (optimistic send, tombstone+undo, projection updates on
/// inbound fanout) lives on [ChatStore] — callers use the typed methods,
/// not raw SQL.
library vartalap_store;

export 'src/chat_store.dart' show ChatStore;
export 'src/schema.dart' show schemaVersion;
export 'src/types.dart'
    show
        ChannelListEntry,
        ContactRow,
        MessageRow,
        MessageState,
        OpKind,
        OpStatus,
        OpTransport,
        OutboundOpRow;
