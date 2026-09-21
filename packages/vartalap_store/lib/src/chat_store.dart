import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema.dart';
import 'types.dart';

/// Growable page window for [ChatStore.watchChannelMessages].
///
/// "Load older" must not open a second live query — the chat screen
/// keeps exactly one subscription on one channel. Growing the LIMIT
/// and re-running the same query on the same subscription is the whole
/// mechanism; [grow] triggers a re-emit.
///
/// ponytail: LIMIT-growth rather than OFFSET paging. It re-reads the
/// rows already on screen, which is free at chat-history scale and
/// keeps one stream; switch to a keyset cursor if a channel ever holds
/// enough messages for the re-read to show up in a frame budget.
class MessageWindow {
  int limit;

  /// Set by [ChatStore.watchChannelMessages] while a stream is
  /// listening. Store-internal.
  void Function()? onGrow;

  MessageWindow({this.limit = 50});

  void grow([int by = 50]) {
    limit += by;
    onGrow?.call();
  }
}

/// v3 local store handle.
///
/// Thin wrapper over a single [Database]. Repositories hang off this to
/// perform cross-table transactions (the outbound optimistic-send path in
/// SPIKE_A_SCHEMA.md §5.3 touches `messages`, `channels`, and
/// `outbound_ops` in one BEGIN ... COMMIT block, so they must share a
/// connection).
class ChatStore {
  final Database db;

  /// Per-table change notification. Every mutating write in this class
  /// calls [_notify] for the affected tables; watchers filter by name.
  ///
  /// Hand-rolled over sqflite because (a) sqflite has no built-in
  /// `.watch()` and (b) `drift.watch()` was rejected on
  /// watch-amplification in Spike A. The contract here is deliberate:
  /// a write that touches a row in table T pokes T once; watchers
  /// re-query themselves. No row-level diffing, no attempt to filter
  /// "only emit if the watched rows changed" at the store layer —
  /// watchers handle that by applying `.distinct()` where it matters.
  final _changes = StreamController<Set<String>>.broadcast();

  ChatStore._(this.db);

  /// The store the process last opened, so code that can't be handed a
  /// [ChatStore] can still reach it — currently only `AuthService.logout`,
  /// which must [wipe] the account's data (AUTH_CONTRACT §8) and is
  /// constructed before the store exists.
  ///
  /// ponytail: a process-wide handle because the app (and each test
  /// harness) opens exactly one store. Thread the store through
  /// explicitly if a second concurrent store ever appears.
  static ChatStore? current;

  /// Emits the set of table names touched by the most recent write.
  /// Callers typically `stream.where((tables) => tables.contains('x'))`.
  Stream<Set<String>> get tableChanges => _changes.stream;

  void _notify(Set<String> tables) {
    if (!_changes.isClosed) _changes.add(tables);
  }

  /// Opens (or creates) a database at [path]. Pass `inMemoryDatabasePath`
  /// for tests.
  static Future<ChatStore> open({required String path}) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          for (final p in pragmas) {
            await db.execute(p);
          }
        },
        onCreate: (db, _) async {
          for (final stmt in ddl) {
            await db.execute(stmt);
          }
        },
      ),
    );
    return current = ChatStore._(db);
  }

  Future<void> close() async {
    if (identical(current, this)) current = null;
    await _changes.close();
    await db.close();
  }

  /// AUTH_CONTRACT §8 — destroy every trace of the signed-out account.
  /// One transaction, every table: projections, the outbound queue,
  /// the inbound dedup set, the resource_seq counters and snapshots.
  Future<void> wipe() async {
    await db.transaction((txn) async {
      for (final table in const [
        'messages',
        'reactions',
        'channel_members',
        'op_id_seen',
        'channels',
        'contacts',
        'outbound_ops',
        'resource_seq',
        'snapshots',
      ]) {
        await txn.delete(table);
      }
    });
    _notify(const {
      'messages',
      'reactions',
      'channel_members',
      'op_id_seen',
      'channels',
      'contacts',
      'outbound_ops',
    });
  }

  /// §5.3 — optimistic send. Inserts the message row in `pending`,
  /// enqueues the outbound op, bumps the channel's activity marker.
  /// All three writes in one transaction.
  Future<void> enqueueLocalMessage({
    required MessageRow message,
    required OutboundOpRow op,
    required int nowMs,
  }) async {
    await db.transaction((txn) async {
      await txn.insert('messages', _messageToRow(message));
      await txn.insert('outbound_ops', await _opRowWithSeq(txn, op));
      await txn.update(
        'channels',
        {
          'last_activity_ms': nowMs,
          'last_message_id': message.messageId,
          // Writing into a chat the user deleted brings it back.
          'deleted_locally': 0,
        },
        where: 'channel_id = ?',
        whereArgs: [message.channelId],
      );
    });
    _notify(const {'messages', 'outbound_ops', 'channels'});
  }

  /// Enqueue a standalone outbound op (no associated message row).
  /// Used for channel creation and other REST-only ops.
  ///
  /// [op.resourceSeq] is ignored — see [_allocResourceSeq].
  Future<void> enqueueOutboundOp(OutboundOpRow op) async {
    await db.transaction(
        (txn) async => txn.insert('outbound_ops', await _opRowWithSeq(txn, op)));
    _notify(const {'outbound_ops'});
  }

  /// §6 — allocate the next `resource_seq` for [resourceId].
  ///
  /// Strictly monotonic per resource, first op is 1. The counter lives
  /// in its own `resource_seq` table rather than being derived from
  /// `MAX(resource_seq)` over `outbound_ops`, because acked rows are
  /// deleted: after the queue drains the derived value falls back to 1
  /// and the server answers `out_of_order`. Callers must run this in
  /// the same transaction as the op insert, so two concurrent
  /// enqueues (a send racing a read receipt) can't mint the same seq.
  Future<int> _allocResourceSeq(DatabaseExecutor txn, String resourceId) async {
    final rows = await txn.query(
      'resource_seq',
      columns: const ['next_seq'],
      where: 'resource_id = ?',
      whereArgs: [resourceId],
      limit: 1,
    );
    final seq = rows.isEmpty ? 1 : rows.single['next_seq'] as int;
    await txn.insert(
      'resource_seq',
      {'resource_id': resourceId, 'next_seq': seq + 1},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return seq;
  }

  /// [op] as a DB row with a freshly allocated `resource_seq`.
  Future<Map<String, Object?>> _opRowWithSeq(
    DatabaseExecutor txn,
    OutboundOpRow op,
  ) async {
    final row = _outboundOpToRow(op);
    row['resource_seq'] = await _allocResourceSeq(txn, op.resourceId);
    return row;
  }

  /// Delete an outbound op row (e.g. after ACK success for non-message ops).
  Future<void> deleteOp(String opId) async {
    await db.delete('outbound_ops', where: 'op_id = ?', whereArgs: [opId]);
    _notify(const {'outbound_ops'});
  }

  /// Flow A — dispatcher flip. Op row → `in_flight`, message → `sending`.
  Future<void> markOpInFlight({
    required String opId,
    required String? messageId,
    required int nowMs,
  }) async {
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE outbound_ops '
        "SET status = 'in_flight', dispatched_at = ?, attempts = attempts + 1 "
        'WHERE op_id = ?',
        [nowMs, opId],
      );
      if (messageId != null) {
        await txn.update(
          'messages',
          {
            'message_state': MessageState.sending.wire,
            'state_updated_at': nowMs,
          },
          where: 'message_id = ?',
          whereArgs: [messageId],
        );
      }
    });
    _notify(const {'outbound_ops', 'messages'});
  }

  /// Flow B — ACK success. Op row deleted, message promoted to `sent`
  /// with server-stamped fields.
  Future<void> applyAckSuccess({
    required String opId,
    required String messageId,
    required int serverTimestampMs,
    required int deliverySequence,
    required int nowMs,
  }) async {
    await db.transaction((txn) async {
      await txn.delete('outbound_ops', where: 'op_id = ?', whereArgs: [opId]);
      // Update server-stamped fields unconditionally, but ONLY raise
      // message_state to `sent` if the row hasn't already advanced
      // past it (e.g. a `MessageStateChanged{DELIVERED}` arriving
      // before this ACK). The states form a monotonic lifecycle —
      // SPIKE_A_SCHEMA.md §5.1 — and downgrading would flip a double
      // tick back to single.
      await txn.rawUpdate(
        '''
        UPDATE messages
           SET message_state = CASE
                 WHEN message_state IN (?, ?, ?) THEN ?
                 ELSE message_state
               END,
               state_updated_at = ?,
               server_timestamp_ms = ?,
               delivery_sequence = ?
         WHERE message_id = ?
        ''',
        [
          MessageState.pending.wire,
          MessageState.sending.wire,
          MessageState.sent.wire,
          MessageState.sent.wire,
          nowMs,
          serverTimestampMs,
          deliverySequence,
          messageId,
        ],
      );
    });
    _notify(const {'outbound_ops', 'messages'});
  }

  /// Apply a server-pushed `MessageStateChanged` event. Monotonic — the
  /// new state must be strictly LATER in the [MessageState] lifecycle
  /// (`pending < sending < sent < delivered < read < rejected`) than
  /// what's currently stored, otherwise the event is dropped (stale /
  /// reorder). No-op if the message row doesn't exist locally yet.
  Future<bool> applyMessageStateChange({
    required String messageId,
    required MessageState newState,
    required int changedAtMs,
  }) async {
    final rows = await db.query(
      'messages',
      columns: const ['message_state'],
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final current = MessageState.fromWire(rows.single['message_state'] as String);
    if (newState.index <= current.index) return false;
    await db.update(
      'messages',
      {
        'message_state': newState.wire,
        'state_updated_at': changedAtMs,
      },
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    _notify(const {'messages'});
    return true;
  }

  /// Convenience read for the smoke test and any single-row fetch.
  Future<MessageRow?> fetchMessage(String messageId) async {
    final rows = await db.query(
      'messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToMessage(rows.single);
  }

  Future<OutboundOpRow?> fetchOutboundOp(String opId) async {
    final rows = await db.query(
      'outbound_ops',
      where: 'op_id = ?',
      whereArgs: [opId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToOutboundOp(rows.single);
  }

  /// Transient reject or timeout → retry later with backoff.
  /// SPIKE_B_SYNC.md §5 Flow B / §6.
  Future<void> markOpRetrying({
    required String opId,
    required int nextRetryAt,
    required String reason,
  }) async {
    await db.update(
      'outbound_ops',
      {
        'status': OpStatus.retrying.wire,
        'next_retry_at': nextRetryAt,
        'last_error': reason,
        'dispatched_at': null,
      },
      where: 'op_id = ?',
      whereArgs: [opId],
    );
    _notify(const {'outbound_ops'});
  }

  /// Soft/hard retry limit exceeded → dead_letter. SPIKE_B_SYNC.md §6.
  /// Row stays until user acknowledges it from the UI (§10).
  Future<void> markOpDeadLetter({
    required String opId,
    required String reason,
    required String? messageId,
    required int nowMs,
  }) async {
    await db.transaction((txn) async {
      await txn.update(
        'outbound_ops',
        {
          'status': OpStatus.deadLetter.wire,
          'last_error': reason,
          'dispatched_at': null,
        },
        where: 'op_id = ?',
        whereArgs: [opId],
      );
      await _rollbackForTerminalOp(txn, opId, messageId, nowMs);
    });
    _notify(
      messageId != null
          ? const {'outbound_ops', 'messages'}
          // A channel-scoped op (role change) rolls back channel_members.
          : const {'outbound_ops', 'channel_members'},
    );
  }

  /// Projection rollback for an op that has reached a terminal state —
  /// SPIKE_B_SYNC.md §8 + V3_ARCHITECTURE decision 11. What "roll back"
  /// means depends on what the op was:
  ///
  ///   * a create ([OpKind.chatPayload]) flips its optimistic row to
  ///     `rejected` so the bubble can offer Retry;
  ///   * an edit restores the body snapshotted at enqueue time, and
  ///     drops the "edited" label unless an *earlier* edit had already
  ///     landed (`last_edit_ms` is stamped only on ACK);
  ///   * a delete lifts its tombstone — the message comes back;
  ///   * a reaction is non-destructive (decision 11 excludes it), so
  ///     the local row stays and the UI just reports the failure;
  ///   * a role change ([OpKind.setMemberRole], decision 80) puts the
  ///     member back on the role it must have held.
  Future<void> _rollbackForTerminalOp(
    DatabaseExecutor txn,
    String opId,
    String? messageId,
    int nowMs,
  ) async {
    final opRows = await txn.query(
      'outbound_ops',
      columns: const ['kind', 'rest_path', 'payload', 'target_channel_id'],
      where: 'op_id = ?',
      whereArgs: [opId],
      limit: 1,
    );
    // The pre-kind default preserves old behaviour when the row is gone.
    final kind =
        opRows.isEmpty ? OpKind.chatPayload : opRows.single['kind'] as String;
    if (kind == OpKind.setMemberRole) {
      await _rollbackMemberRole(txn, opRows.single);
      return;
    }
    if (messageId == null) return;
    switch (kind) {
      case OpKind.messageEdit:
        await txn.rawUpdate(
          'UPDATE messages '
          '   SET body = COALESCE(rollback_body, body), '
          '       rollback_body = NULL, '
          '       is_edited = CASE WHEN last_edit_ms IS NULL THEN 0 ELSE 1 END, '
          '       state_updated_at = ? '
          ' WHERE message_id = ?',
          [nowMs, messageId],
        );
      case OpKind.messageDelete:
        await txn.rawUpdate(
          'UPDATE messages '
          "   SET tombstoned = 0, tombstone_pending_until = NULL, "
          '       state_updated_at = ? '
          ' WHERE message_id = ?',
          [nowMs, messageId],
        );
      case OpKind.messageReaction:
        break;
      default:
        await txn.update(
          'messages',
          {
            'message_state': MessageState.rejected.wire,
            'state_updated_at': nowMs,
          },
          where: 'message_id = ?',
          whereArgs: [messageId],
        );
    }
  }

  /// Compensating write for a rejected `PATCH channels/{id}/members/
  /// {user_id}`: put the member back where they were.
  ///
  /// ponytail: the previous role is inferred, not snapshotted — the
  /// only assignable roles are `admin` and `member` (decision 80 makes
  /// the owner a forbidden target), so a rejected promote rolls back to
  /// `member` and a rejected demote to `admin`. Snapshot the old role
  /// on the op row if a third assignable role ever appears.
  Future<void> _rollbackMemberRole(
    DatabaseExecutor txn,
    Map<String, Object?> op,
  ) async {
    final channelId = op['target_channel_id'] as String?;
    final path = op['rest_path'] as String?;
    if (channelId == null || path == null) return;
    final userId = path.split('/').last;
    final bytes = op['payload'];
    if (bytes is! List<int> || bytes.isEmpty) return;
    final String requested;
    try {
      requested =
          (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['role']
              as String;
    } catch (_) {
      return;
    }
    await txn.update(
      'channel_members',
      {'role': requested == 'admin' ? 'member' : 'admin'},
      where: 'channel_id = ? AND user_id = ?',
      whereArgs: [channelId, userId],
    );
  }

  /// Permanent reject. Roll back message projection, mark op rejected,
  /// cascade subsequent same-resource ops.
  /// SPIKE_B_SYNC.md §5 Flow B / §8.
  Future<void> applyPermanentReject({
    required String opId,
    required String resourceId,
    required int rejectedSeq,
    required String reason,
    required String? messageId,
    required int nowMs,
  }) async {
    await db.transaction((txn) async {
      await txn.update(
        'outbound_ops',
        {
          'status': OpStatus.rejected.wire,
          'last_error': reason,
          'dispatched_at': null,
        },
        where: 'op_id = ?',
        whereArgs: [opId],
      );

      await _rollbackForTerminalOp(txn, opId, messageId, nowMs);

      // Cascade: any later-sequenced op on the same resource is
      // guaranteed to fail because the parent failed. Mark them so the
      // UI shows one coherent error instead of N.
      await txn.rawUpdate(
        '''
        UPDATE outbound_ops
        SET status = 'cascaded_rejection',
            last_error = ?,
            dispatched_at = NULL
        WHERE resource_id = ?
          AND resource_seq > ?
          AND status IN ('pending', 'retrying', 'in_flight')
        ''',
        ['parent_rejected:$reason', resourceId, rejectedSeq],
      );
    });
    _notify(const {'outbound_ops', 'messages', 'channel_members'});
  }

  /// User tapped "dismiss" on a failure toast. Marks the terminal op
  /// acknowledged; GC removes it after 24h per SPIKE_B §11.
  Future<void> acknowledgeFailure({
    required String opId,
    required int nowMs,
  }) async {
    await db.update(
      'outbound_ops',
      {'acknowledged_at': nowMs},
      where: 'op_id = ?',
      whereArgs: [opId],
    );
    _notify(const {'outbound_ops'});
  }

  /// Manual retry: clone a terminal outbound_ops row into a brand-new
  /// pending op (new op_id, next resource_seq, attempts=0). The old
  /// terminal row is acknowledged so it stops showing in [fetchFailures].
  ///
  /// This is NOT a state transition on the failed row — terminal states
  /// (rejected / dead_letter / cascaded_rejection) don't un-terminate.
  /// Server dedup is by op_id, so the fresh id means the server treats
  /// it as a new intent even if the original actually reached it.
  ///
  /// For `chat_payload` ops, the linked message row is flipped back to
  /// `pending` and re-pointed at the new op.
  Future<void> manualRetry({
    required String failedOpId,
    required String newOpId,
    required int nowMs,
  }) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'outbound_ops',
        where: 'op_id = ?',
        whereArgs: [failedOpId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('manualRetry: op $failedOpId not found');
      }
      final old = _rowToOutboundOp(rows.single);

      // Next resource_seq for the resource. Correctness note: the
      // scheduler only dispatches ops in `(resource_id, resource_seq)`
      // order (SPIKE_B §5 Flow A). A retry gets a seq strictly greater
      // than every prior op on the resource so that in-flight/queued
      // siblings drain first — otherwise a retry could jump ahead of
      // pending follow-ups and reorder user intent on the wire.
      final nextSeq = await _allocResourceSeq(txn, old.resourceId);

      await txn.insert('outbound_ops', {
        'op_id': newOpId,
        'transport': old.transport.wire,
        'kind': old.kind,
        'rest_method': old.restMethod,
        'rest_path': old.restPath,
        'resource_id': old.resourceId,
        'resource_seq': nextSeq,
        'payload': Uint8List.fromList(old.payload),
        'status': OpStatus.pending.wire,
        'attempts': 0,
        'next_retry_at': nowMs,
        'dispatched_at': null,
        'last_error': null,
        'acknowledged_at': null,
        'created_at': nowMs,
        'target_message_id': old.targetMessageId,
        'target_channel_id': old.targetChannelId,
      });

      // Dismiss the failed row so the UI stops showing it.
      await txn.update(
        'outbound_ops',
        {'acknowledged_at': nowMs},
        where: 'op_id = ?',
        whereArgs: [failedOpId],
      );

      // Only a create owns its message's lifecycle state. An edit /
      // delete / reaction retry re-sends an intent about a row that is
      // already `sent`; pulling it back to `pending` would put a clock
      // icon on somebody else's acked message.
      if (old.targetMessageId != null && old.kind == OpKind.chatPayload) {
        await txn.update(
          'messages',
          {
            'message_state': MessageState.pending.wire,
            'state_updated_at': nowMs,
          },
          where: 'message_id = ?',
          whereArgs: [old.targetMessageId],
        );
      }
    });
    _notify(const {'outbound_ops', 'messages'});
  }

  /// User-visible failures: rejected / dead_letter / cascaded_rejection
  /// with no acknowledged_at yet. SPIKE_B_SYNC.md §10.
  Future<List<OutboundOpRow>> fetchFailures() async {
    final rows = await db.rawQuery('''
      SELECT * FROM outbound_ops
      WHERE status IN ('rejected', 'dead_letter', 'cascaded_rejection')
        AND acknowledged_at IS NULL
      ORDER BY created_at DESC
    ''');
    return rows.map(_rowToOutboundOp).toList();
  }

  /// Flow C — in-flight rows whose ACK is overdue.
  /// SPIKE_B_SYNC.md §5 Flow C.
  Future<List<OutboundOpRow>> selectInFlightOlderThan({
    required int cutoffMs,
  }) async {
    final rows = await db.query(
      'outbound_ops',
      where: "status = 'in_flight' AND dispatched_at < ?",
      whereArgs: [cutoffMs],
    );
    return rows.map(_rowToOutboundOp).toList();
  }

  /// For the Flow A dispatcher query — returns up to one op per resource
  /// (the earliest unfinished), across all resources. See SPIKE_B §5 Flow A.
  Future<List<OutboundOpRow>> selectDispatchable({required int now}) async {
    final rows = await db.rawQuery(
      '''
      SELECT * FROM outbound_ops o1
      WHERE o1.status IN ('pending', 'retrying')
        AND o1.next_retry_at <= ?
        AND NOT EXISTS (
          SELECT 1 FROM outbound_ops o2
          WHERE o2.resource_id = o1.resource_id
            AND o2.resource_seq < o1.resource_seq
            AND o2.status IN ('pending', 'in_flight', 'retrying')
        )
      ORDER BY o1.resource_id, o1.resource_seq
      ''',
      [now],
    );
    return rows.map(_rowToOutboundOp).toList();
  }

  /// §3 — bootstrap a channel row. Used in scaffold tests. Production
  /// code will call higher-level repositories.
  Future<void> insertChannel({
    required String channelId,
    required String kind,
    required String ownerUserId,
    required int createdAt,
    String? name,
  }) async {
    await db.insert('channels', {
      'channel_id': channelId,
      'kind': kind,
      'name': name,
      'avatar_url': null,
      'owner_user_id': ownerUserId,
      'created_at': createdAt,
      'last_activity_ms': createdAt,
      'last_message_id': null,
      'unread_count': 0,
      'last_read_message_id': null,
      'tombstoned': 0,
    });
    _notify(const {'channels'});
  }

  // --- Inbound writers --------------------------------------------------
  //
  // Per SPIKE_A_SCHEMA.md §5.4: receiver-side application of WS_PUSH
  // fanout. Every mutating writer is paired with an `op_id_seen` INSERT
  // inside a single transaction — on gate failure the seen row is still
  // written so a re-fanout of the same op_id does not re-evaluate
  // (SYNC_PROTOCOL.md §7.2).
  //
  // Authorship and existence gates (§6a.4) are silent: a rejected payload
  // leaves no user-visible trace, only a flag on the returned future for
  // caller-side observability if wanted. Each method returns whether the
  // payload was applied (true) or dropped by the gate (false).

  /// Recipient-side dedup check (SYNC_PROTOCOL.md §7.2). Called before
  /// applying a push so the receiver can skip decode entirely on hits.
  Future<bool> hasSeenOpId(String channelId, String opId) async {
    final rows = await db.query(
      'op_id_seen',
      columns: const ['op_id'],
      where: 'channel_id = ? AND op_id = ?',
      whereArgs: [channelId, opId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// §5.4 — TYPE_MESSAGE_CREATE / TYPE_MESSAGE_FORWARD apply.
  ///
  /// Inserts the message row, advances the channel's activity marker,
  /// bumps `unread_count` iff the sender is not the local user, and
  /// records `op_id_seen`. All in one transaction.
  ///
  /// Throws `DatabaseException` on duplicate `message_id` — §10.3 rule 4
  /// forbids self-fanout on v3.0, so a create echo for the local user's
  /// own optimistic row is a server-protocol violation we surface loudly
  /// rather than swallowing.
  Future<void> applyInboundMessage({
    required String localUserId,
    required String channelId,
    required String opId,
    required String messageId,
    required String senderUserId,
    required String? body,
    required String? contentType,
    required Uint8List? attachments,
    required Uint8List? forwardSource,
    required String? replyToMessageId,
    required int clientTimestampMs,
    required int serverTimestampMs,
    required int deliverySequence,
    required int nowMs,
  }) async {
    final bumpUnread = senderUserId != localUserId;
    await db.transaction((txn) async {
      await txn.insert('messages', {
        'message_id': messageId,
        'channel_id': channelId,
        'author_user_id': senderUserId,
        'body': body,
        'content_type': contentType,
        'reply_to_message_id': replyToMessageId,
        'attachments': attachments,
        'forward_source': forwardSource,
        'client_timestamp_ms': clientTimestampMs,
        'server_timestamp_ms': serverTimestampMs,
        'delivery_sequence': deliverySequence,
        'message_state': MessageState.sent.wire,
        'state_updated_at': nowMs,
        'is_edited': 0,
        'last_edit_ms': null,
        'tombstoned': 0,
        'tombstone_pending_until': null,
      });
      await txn.rawUpdate(
        bumpUnread
            ? 'UPDATE channels '
                'SET last_activity_ms = ?, last_message_id = ?, '
                '    unread_count = unread_count + 1, deleted_locally = 0 '
                'WHERE channel_id = ?'
            : 'UPDATE channels '
                'SET last_activity_ms = ?, last_message_id = ?, '
                '    deleted_locally = 0 '
                'WHERE channel_id = ?',
        [serverTimestampMs, messageId, channelId],
      );
      await txn.insert('op_id_seen', {
        'channel_id': channelId,
        'op_id': opId,
        'seen_at': nowMs,
      });
    });
    _notify(const {'messages', 'channels', 'op_id_seen'});
  }

  /// §5.4 — TYPE_MESSAGE_UPDATE apply with §6a.4 authorship gate.
  ///
  /// Gate: local row must exist, be authored by [senderUserId], and not
  /// be tombstoned. Gate miss → silent drop; `op_id_seen` still written
  /// so re-fanout is a no-op. Returns `true` iff the update applied.
  Future<bool> applyInboundMessageUpdate({
    required String channelId,
    required String opId,
    required String messageId,
    required String senderUserId,
    required String? body,
    required String? contentType,
    required Uint8List? attachments,
    required int serverTimestampMs,
    required int nowMs,
  }) async {
    var applied = false;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'messages',
        columns: const ['author_user_id', 'tombstoned'],
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final author = rows.single['author_user_id'] as String;
        final tomb = (rows.single['tombstoned'] as int) != 0;
        if (!tomb && author == senderUserId) {
          await txn.update(
            'messages',
            {
              'body': body,
              'content_type': contentType,
              'attachments': attachments,
              'is_edited': 1,
              'last_edit_ms': serverTimestampMs,
              'state_updated_at': nowMs,
            },
            where: 'message_id = ?',
            whereArgs: [messageId],
          );
          applied = true;
        }
      }
      await txn.insert('op_id_seen', {
        'channel_id': channelId,
        'op_id': opId,
        'seen_at': nowMs,
      });
    });
    _notify(applied
        ? const {'messages', 'op_id_seen'}
        : const {'op_id_seen'});
    return applied;
  }

  /// §5.4 — TYPE_MESSAGE_DELETE apply with §6a.4 authorship gate.
  ///
  /// Gate: local row exists and is authored by [senderUserId]. Gate miss
  /// → silent drop; `op_id_seen` still written. Returns `true` iff the
  /// tombstone applied.
  Future<bool> applyInboundMessageDelete({
    required String channelId,
    required String opId,
    required String messageId,
    required String senderUserId,
    required int nowMs,
  }) async {
    var applied = false;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'messages',
        columns: const ['author_user_id'],
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      if (rows.isNotEmpty &&
          (rows.single['author_user_id'] as String) == senderUserId) {
        await txn.update(
          'messages',
          {
            'tombstoned': 1,
            'body': null,
            'content_type': null,
            'attachments': null,
            'state_updated_at': nowMs,
          },
          where: 'message_id = ?',
          whereArgs: [messageId],
        );
        applied = true;
      }
      await txn.insert('op_id_seen', {
        'channel_id': channelId,
        'op_id': opId,
        'seen_at': nowMs,
      });
    });
    _notify(applied
        ? const {'messages', 'op_id_seen'}
        : const {'op_id_seen'});
    return applied;
  }

  /// §5.4 — TYPE_REACTION_ADD apply. Target message must exist and not
  /// be tombstoned; duplicate (message_id, user_id, emoji) is a no-op
  /// via INSERT OR IGNORE.
  Future<bool> applyInboundReactionAdd({
    required String channelId,
    required String opId,
    required String messageId,
    required String senderUserId,
    required String emoji,
    required int nowMs,
  }) async {
    var applied = false;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'messages',
        columns: const ['message_id'],
        where: 'message_id = ? AND tombstoned = 0',
        whereArgs: [messageId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await txn.rawInsert(
          'INSERT OR IGNORE INTO reactions '
          '(message_id, user_id, emoji, added_at) VALUES (?, ?, ?, ?)',
          [messageId, senderUserId, emoji, nowMs],
        );
        applied = true;
      }
      await txn.insert('op_id_seen', {
        'channel_id': channelId,
        'op_id': opId,
        'seen_at': nowMs,
      });
    });
    _notify(applied
        ? const {'reactions', 'op_id_seen'}
        : const {'op_id_seen'});
    return applied;
  }

  /// §5.4 — TYPE_REACTION_REMOVE apply. Gate: target message must exist
  /// (tombstone state irrelevant — removing a reaction on a deleted
  /// message is a legitimate no-op). Missing row → silent drop.
  Future<bool> applyInboundReactionRemove({
    required String channelId,
    required String opId,
    required String messageId,
    required String senderUserId,
    required String emoji,
    required int nowMs,
  }) async {
    var applied = false;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'messages',
        columns: const ['message_id'],
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await txn.delete(
          'reactions',
          where: 'message_id = ? AND user_id = ? AND emoji = ?',
          whereArgs: [messageId, senderUserId, emoji],
        );
        applied = true;
      }
      await txn.insert('op_id_seen', {
        'channel_id': channelId,
        'op_id': opId,
        'seen_at': nowMs,
      });
    });
    _notify(applied
        ? const {'reactions', 'op_id_seen'}
        : const {'op_id_seen'});
    return applied;
  }

  // --- Contacts ----------------------------------------------------------

  /// Upsert a contact row (INSERT OR REPLACE).
  Future<void> upsertContact({
    required String userId,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? statusText,
    String? phoneHash,
    String? contactBookName,
    required int nowMs,
  }) async {
    await db.insert(
      'contacts',
      {
        'user_id': userId,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'status_text': statusText,
        'phone_hash': phoneHash,
        'contact_book_name': contactBookName,
        'last_refreshed_ms': nowMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify(const {'contacts'});
  }

  /// Apply a server-fanned `ProfileEdited` to the local contact row.
  ///
  /// Each parameter is a `($PresentField, value)` tuple — `null` for
  /// the outer field means "the proto didn't carry this field; leave
  /// it alone." A present-but-empty string means "the user cleared it"
  /// per `ProfileEdited`'s proto-`optional` semantics, and we write
  /// NULL to the column. Existing fields not mentioned in the proto
  /// (phone_hash, contact_book_name, the locally-set username if this
  /// is a profile-only edit) are preserved.
  ///
  /// If no contact row exists for [userId], inserts one with just the
  /// supplied fields — the next `discoverContacts` call will fill in
  /// phone_hash and contact_book_name when the user's number lands in
  /// the address book.
  Future<void> applyProfileEdit({
    required String userId,
    ({String? value})? displayName,
    ({String? value})? avatarUrl,
    ({String? value})? statusText,
    required int nowMs,
  }) async {
    final updates = <String, Object?>{'last_refreshed_ms': nowMs};
    if (displayName != null) updates['display_name'] = displayName.value;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl.value;
    if (statusText != null) updates['status_text'] = statusText.value;

    final existing = await db.query(
      'contacts',
      columns: const ['user_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('contacts', {
        'user_id': userId,
        ...updates,
      });
    } else {
      await db.update(
        'contacts',
        updates,
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    }
    _notify(const {'contacts'});
  }

  /// Apply a server-fanned `UsernameChanged` — sets the contact row's
  /// `username` column. Empty string in [newUsername] is treated as
  /// "user cleared their handle" and writes NULL to the column.
  Future<void> applyUsernameChange({
    required String userId,
    required String newUsername,
    required int nowMs,
  }) async {
    final value = newUsername.isEmpty ? null : newUsername;
    final existing = await db.query(
      'contacts',
      columns: const ['user_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('contacts', {
        'user_id': userId,
        'username': value,
        'last_refreshed_ms': nowMs,
      });
    } else {
      await db.update(
        'contacts',
        {'username': value, 'last_refreshed_ms': nowMs},
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    }
    _notify(const {'contacts'});
  }

  /// All contacts, sorted by display name.
  Future<List<ContactRow>> fetchContacts() async {
    final rows = await db.query(
      'contacts',
      orderBy: 'COALESCE(contact_book_name, display_name, username, user_id)',
    );
    return rows
        .map((r) => ContactRow(
              userId: r['user_id'] as String,
              username: r['username'] as String?,
              displayName: r['display_name'] as String?,
              avatarUrl: r['avatar_url'] as String?,
              statusText: r['status_text'] as String?,
              phoneHash: r['phone_hash'] as String?,
              contactBookName: r['contact_book_name'] as String?,
              lastRefreshedMs: r['last_refreshed_ms'] as int,
            ))
        .toList();
  }

  /// Check if a DM channel already exists between two users.
  /// Returns the channel_id if found, null otherwise.
  Future<String?> findExistingDmChannel(
      String userId, String peerUserId) async {
    // A DM channel has kind='one_to_one' and both users as members.
    final rows = await db.rawQuery(
      '''
      SELECT c.channel_id FROM channels c
      JOIN channel_members m1 ON c.channel_id = m1.channel_id
        AND m1.user_id = ? AND m1.removed_at IS NULL
      JOIN channel_members m2 ON c.channel_id = m2.channel_id
        AND m2.user_id = ? AND m2.removed_at IS NULL
      WHERE c.kind = 'one_to_one' AND c.tombstoned = 0
      LIMIT 1
      ''',
      [userId, peerUserId],
    );
    if (rows.isEmpty) return null;
    return rows.single['channel_id'] as String;
  }

  /// Insert a channel member row.
  Future<void> insertChannelMember({
    required String channelId,
    required String userId,
    required String role,
    required int joinedAt,
  }) async {
    await db.insert(
      'channel_members',
      {
        'channel_id': channelId,
        'user_id': userId,
        'role': role,
        'joined_at': joinedAt,
        'removed_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _notify(const {'channel_members'});
  }

  /// Upsert a membership row, role included — decision 80. Role changes
  /// and owner succession reach every client as a RE-announced
  /// `ChannelMemberAdded{members:[user], role}`, so the projection has
  /// to overwrite the role of a row it already has (plain
  /// [insertChannelMember] is INSERT OR IGNORE and would drop it).
  /// Also clears `removed_at`, so a re-add resurrects the row.
  ///
  /// An empty [role] means the announce carried none: a new row lands as
  /// `member` and an existing row keeps whatever role it holds.
  ///
  /// A `role = 'owner'` announce is the succession event: the channel's
  /// `owner_user_id` moves with it, and the outgoing owner (if still a
  /// member) falls back to `member`.
  Future<void> upsertChannelMember({
    required String channelId,
    required String userId,
    required String role,
    required int joinedAt,
  }) async {
    await db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT INTO channel_members '
        '  (channel_id, user_id, role, joined_at, removed_at) '
        'VALUES (?, ?, ?, ?, NULL) '
        'ON CONFLICT(channel_id, user_id) DO UPDATE SET '
        "  role = CASE WHEN ? = '' THEN channel_members.role "
        '              ELSE excluded.role END, '
        '  removed_at = NULL',
        [channelId, userId, role.isEmpty ? 'member' : role, joinedAt, role],
      );
      if (role != 'owner') return;
      await txn.rawUpdate(
        "UPDATE channel_members SET role = 'member' "
        ' WHERE channel_id = ? AND user_id != ? AND role = ?',
        [channelId, userId, 'owner'],
      );
      await txn.update(
        'channels',
        {'owner_user_id': userId},
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
    });
    _notify(
      role == 'owner'
          ? const {'channel_members', 'channels'}
          : const {'channel_members'},
    );
  }

  /// Local projection of a role change the local user just made — the
  /// optimistic half of `PATCH channels/{id}/members/{user_id}`. The
  /// server's re-announce lands on the same row via
  /// [upsertChannelMember].
  Future<void> setMemberRoleLocal({
    required String channelId,
    required String userId,
    required String role,
  }) async {
    await db.update(
      'channel_members',
      {'role': role},
      where: 'channel_id = ? AND user_id = ?',
      whereArgs: [channelId, userId],
    );
    _notify(const {'channel_members'});
  }

  /// Soft-delete a membership row by stamping `removed_at`. Used by the
  /// inbound ChannelMemberRemoved handler (SYNC_PROTOCOL.md §10.2). The
  /// channel itself is untouched — see [tombstoneChannel] for the
  /// self-removal case where the local user has been kicked.
  Future<void> removeChannelMember({
    required String channelId,
    required String userId,
    required int removedAtMs,
  }) async {
    await db.update(
      'channel_members',
      {'removed_at': removedAtMs},
      where: 'channel_id = ? AND user_id = ?',
      whereArgs: [channelId, userId],
    );
    _notify(const {'channel_members'});
  }

  /// Mark a channel tombstoned without dropping the row or its members.
  /// Used when the local user has been removed from a channel by someone
  /// else — the chat-list query filters on `tombstoned = 0` so the
  /// channel disappears from the UI, while history remains queryable
  /// for diagnostic / undo paths. Distinct from [leaveGroupLocal], which
  /// hard-deletes the row (cascading members + messages).
  Future<void> tombstoneChannel(String channelId) async {
    await db.update(
      'channels',
      {'tombstoned': 1},
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    _notify(const {'channels'});
  }

  /// Apply a server-fanned `ChannelEdited` to the local channel row.
  ///
  /// Same proto3-`optional` shape as [applyProfileEdit]: each field is a
  /// `($PresentField, value)` tuple — `null` for the outer field means
  /// "the proto didn't carry this field; leave it alone." A
  /// present-but-empty string writes NULL to the column (matches the
  /// "user cleared the avatar" semantics from `ChannelEdited`'s proto-
  /// `optional` fields).
  ///
  /// If the channel row doesn't exist locally, this is a no-op —
  /// `ChannelCreated` is responsible for materializing channels; an edit
  /// on its own shouldn't conjure a row with mostly-null bookkeeping.
  Future<void> applyChannelEdit({
    required String channelId,
    ({String? value})? name,
    ({String? value})? avatarUrl,
    required int editedAtMs,
  }) async {
    final existing = await db.query(
      'channels',
      columns: const ['channel_id'],
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    if (existing.isEmpty) return;
    final updates = <String, Object?>{};
    if (name != null) updates['name'] = name.value;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl.value;
    if (updates.isEmpty) return;
    await db.update(
      'channels',
      updates,
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    _notify(const {'channels'});
  }

  /// Apply a server-fanned `ChannelDeleted` — flip `tombstoned=1` so the
  /// chat-list query (which filters on `tombstoned=0`) drops the row.
  /// Membership rows stay intact so a re-create wouldn't lose history.
  /// No-op if the channel row doesn't exist locally.
  Future<void> applyChannelDelete({
    required String channelId,
    required int deletedAtMs,
  }) async {
    final existing = await db.query(
      'channels',
      columns: const ['channel_id'],
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    if (existing.isEmpty) return;
    await tombstoneChannel(channelId);
  }

  /// Active members of [channelId], left-joined with `contacts` so the
  /// caller has a display name and avatar in one shot. Owner first, then
  /// alphabetical by resolved name with userId as tiebreaker.
  Future<List<ChannelMemberRow>> fetchChannelMembers(String channelId) async {
    final rows = await db.rawQuery(
      '''
      SELECT cm.channel_id, cm.user_id, cm.role, cm.joined_at,
             ct.username, ct.display_name, ct.avatar_url, ct.status_text,
             ct.phone_hash, ct.contact_book_name, ct.last_refreshed_ms
      FROM channel_members cm
      LEFT JOIN contacts ct ON ct.user_id = cm.user_id
      WHERE cm.channel_id = ? AND cm.removed_at IS NULL
      ORDER BY (cm.role = 'owner') DESC,
               COALESCE(ct.contact_book_name, ct.display_name, ct.username, cm.user_id)
                 COLLATE NOCASE
      ''',
      [channelId],
    );
    return rows.map((r) {
      final hasContact = r['last_refreshed_ms'] != null;
      return ChannelMemberRow(
        channelId: r['channel_id'] as String,
        userId: r['user_id'] as String,
        role: r['role'] as String,
        joinedAt: r['joined_at'] as int,
        contact: hasContact
            ? ContactRow(
                userId: r['user_id'] as String,
                username: r['username'] as String?,
                displayName: r['display_name'] as String?,
                avatarUrl: r['avatar_url'] as String?,
                statusText: r['status_text'] as String?,
                phoneHash: r['phone_hash'] as String?,
                contactBookName: r['contact_book_name'] as String?,
                lastRefreshedMs: r['last_refreshed_ms'] as int,
              )
            : null,
      );
    }).toList();
  }

  /// Substring search within a single channel's messages. Case-insensitive
  /// `LIKE` over `body`; tombstoned rows excluded. Newest-first by
  /// `delivery_sequence` (with `client_timestamp_ms` as fallback for
  /// pending rows). [query] is wrapped in `%…%` after stripping any SQL
  /// wildcards so user input can't broaden the match.
  Future<List<MessageRow>> searchChannelMessages({
    required String channelId,
    required String query,
    int limit = 200,
  }) async {
    final cleaned = query.replaceAll(RegExp(r'[%_]'), '').trim();
    if (cleaned.isEmpty) return const [];
    final rows = await db.rawQuery(
      '''
      SELECT * FROM messages
      WHERE channel_id = ?
        AND tombstoned = 0
        AND body IS NOT NULL
        AND body LIKE ? COLLATE NOCASE
      ORDER BY COALESCE(delivery_sequence, 9223372036854775807) DESC,
               client_timestamp_ms DESC
      LIMIT ?
      ''',
      [channelId, '%$cleaned%', limit],
    );
    return rows.map(_rowToMessage).toList();
  }

  // --- UI reactive queries ----------------------------------------------
  //
  // These power the chat-list and chat-screen reactive streams
  // (`watchChannelList` / `watchChannelMessages`). They run the queries
  // in SPIKE_A_SCHEMA.md §13.1 and §13.2 verbatim. Watchers re-select
  // on every write to the relevant tables; coalescing/filtering is
  // deliberately pushed to the caller (`.distinct()` in Flutter land).

  /// §13.1 — Chat list hot path.
  ///
  /// Newest-first by `last_activity_ms`. JOIN (not LEFT JOIN) on
  /// `last_message_id` so channels with no messages drop off the chat
  /// list — they're still reachable via the Groups tab in the new-chat
  /// picker. The chat list is "active conversations," not "all
  /// channels." When messages arrive (or are sent), `last_message_id`
  /// is set and the channel reappears.
  Future<List<ChannelListEntry>> fetchChannelList({int limit = 100}) async {
    final rows = await db.rawQuery(
      '''
      SELECT c.channel_id, c.kind, c.name, c.avatar_url,
             c.last_activity_ms, c.unread_count,
             (SELECT ct.username FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_username,
             (SELECT ct.display_name FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_display_name,
             (SELECT ct.contact_book_name FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_contact_book_name,
             (SELECT ct.user_id FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_user_id,
             c.pinned, c.muted_until_ms,
             m.body AS last_message_preview,
             m.author_user_id AS last_message_author,
             m.tombstoned AS last_message_tombstoned,
             EXISTS (SELECT 1 FROM outbound_ops o
                     WHERE o.target_channel_id = c.channel_id
                       AND o.status = 'dead_letter') AS has_failed_op
      FROM channels c
      JOIN messages m ON m.message_id = c.last_message_id
      WHERE c.tombstoned = 0 AND c.deleted_locally = 0
      ORDER BY c.pinned DESC, c.last_activity_ms DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(_rowToChannelListEntry).toList();
  }

  /// Reactive wrapper over [fetchChannelList]. Emits on subscribe and
  /// every time the `channels` or `messages` tables change.
  ///
  /// Uses an explicit StreamController rather than `async*` so that
  /// `cancel()` on the subscription promptly tears down the
  /// [tableChanges] listener. The async-generator shape has known
  /// cancel-hang issues that bit `watchFailures` earlier in the spike.
  Stream<List<ChannelListEntry>> watchChannelList({int limit = 100}) {
    late StreamController<List<ChannelListEntry>> controller;
    StreamSubscription<Set<String>>? changeSub;

    Future<void> emit() =>
        _safeEmit(controller, () => fetchChannelList(limit: limit));

    controller = StreamController<List<ChannelListEntry>>(
      onListen: () {
        changeSub = tableChanges.listen((tables) {
          if (tables.contains('channels') ||
              tables.contains('messages') ||
              tables.contains('contacts') ||
              tables.contains('outbound_ops')) {
            emit();
          }
        });
        emit();
      },
      onCancel: () async {
        await changeSub?.cancel();
        changeSub = null;
      },
    );
    return controller.stream;
  }

  /// Re-query and emit, unless the stream or the database went away
  /// while the query was in flight.
  ///
  /// Closing a store that still has live watchers is ordinary teardown
  /// — on logout, or at the end of a test — but the queued re-query
  /// has already been handed to sqflite by then, and it comes back as
  /// "This database has already been closed". Surfacing that as a
  /// stream error would make every watcher's last act an error the
  /// caller has no way to act on.
  Future<void> _safeEmit<T>(
    StreamController<T> controller,
    Future<T> Function() query,
  ) async {
    if (controller.isClosed || !db.isOpen) return;
    try {
      final result = await query();
      if (!controller.isClosed) controller.add(result);
    } on DatabaseException {
      if (db.isOpen) rethrow;
    }
  }

  /// §13.2 — Channel chat view, newest-first (tombstoned rows included).
  ///
  /// `COALESCE(delivery_sequence, INT64_MAX)` sorts locally pending
  /// rows (null `delivery_sequence`) to the top, matching
  /// WhatsApp/Signal UX.
  ///
  /// Tombstoned rows are included: the chat view renders them as
  /// "This message was deleted" (V3_ARCHITECTURE decision 11) rather
  /// than silently closing the gap, and a row inside its Undo window
  /// has to stay addressable. Callers that want only live messages
  /// filter on [MessageRow.tombstoned].
  ///
  /// Reactions ride along in one correlated subquery instead of a
  /// second stream, packed as `user_id US emoji` pairs separated by RS
  /// (both control characters, so neither can occur in an emoji or a
  /// user_id).
  Future<List<MessageRow>> fetchChannelMessages(
    String channelId, {
    int limit = 200,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT m.*,
             (SELECT group_concat(r.user_id || char(31) || r.emoji, char(30))
                FROM reactions r
               WHERE r.message_id = m.message_id) AS reactions
      FROM messages m
      WHERE m.channel_id = ?
      ORDER BY COALESCE(m.delivery_sequence, 9223372036854775807) DESC,
               m.client_timestamp_ms DESC
      LIMIT ?
      ''',
      [channelId, limit],
    );
    return rows.map(_rowToMessage).toList();
  }

  /// Reactive wrapper over [fetchChannelMessages]. Emits on subscribe
  /// and every time `messages` or `reactions` changes.
  ///
  /// Pass a [window] to make the page size growable — "load older"
  /// calls [MessageWindow.grow], which re-runs this same query on this
  /// same subscription. [limit] is the fixed fallback when there is no
  /// window.
  Stream<List<MessageRow>> watchChannelMessages(
    String channelId, {
    int limit = 200,
    MessageWindow? window,
  }) {
    late StreamController<List<MessageRow>> controller;
    StreamSubscription<Set<String>>? changeSub;

    Future<void> emit() => _safeEmit(controller,
        () => fetchChannelMessages(channelId, limit: window?.limit ?? limit));

    controller = StreamController<List<MessageRow>>(
      onListen: () {
        window?.onGrow = () => emit();
        changeSub = tableChanges.listen((tables) {
          if (tables.contains('messages') || tables.contains('reactions')) {
            emit();
          }
        });
        emit();
      },
      onCancel: () async {
        window?.onGrow = null;
        await changeSub?.cancel();
        changeSub = null;
      },
    );
    return controller.stream;
  }

  /// §10 — local read marker advance on channel open.
  ///
  /// Resets `unread_count` to 0 and parks `last_read_message_id` at
  /// the newest non-tombstoned message in the channel. Both writes in
  /// a single transaction so a crash mid-update doesn't leave a stale
  /// read marker pointing at a message that's now behind the visible
  /// window.
  Future<void> markChannelRead(String channelId, int nowMs) async {
    await db.transaction((txn) async {
      final latest = await txn.rawQuery(
        '''
        SELECT message_id FROM messages
        WHERE channel_id = ? AND tombstoned = 0
        ORDER BY COALESCE(delivery_sequence, 9223372036854775807) DESC,
                 client_timestamp_ms DESC
        LIMIT 1
        ''',
        [channelId],
      );
      final latestId =
          latest.isEmpty ? null : latest.single['message_id'] as String?;

      await txn.update(
        'channels',
        {
          'unread_count': 0,
          if (latestId != null) 'last_read_message_id': latestId,
        },
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
    });
    _notify(const {'channels'});
  }

  /// Latest message in [channelId] NOT authored by [localUserId] — the
  /// natural target for an outbound read receipt. Returns null when the
  /// channel is empty or only has the local user's messages.
  Future<String?> latestPeerMessageId({
    required String channelId,
    required String localUserId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT message_id FROM messages
      WHERE channel_id = ? AND tombstoned = 0 AND author_user_id != ?
      ORDER BY COALESCE(delivery_sequence, 9223372036854775807) DESC,
               client_timestamp_ms DESC
      LIMIT 1
      ''',
      [channelId, localUserId],
    );
    if (rows.isEmpty) return null;
    return rows.single['message_id'] as String?;
  }

  /// Wipe every message row in [channelId] without touching the channel
  /// itself or its membership. Resets `last_message_id`, `unread_count`,
  /// and `last_read_message_id` so the chat-list query (which filters
  /// out channels with no `last_message_id`) drops the row from the
  /// list. The channel remains reachable via the Groups tab / contact
  /// picker; the next inbound or outbound message reattaches it.
  Future<void> clearChannelMessages(String channelId) async {
    await db.transaction((txn) async {
      await txn.delete(
        'messages',
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
      await txn.update(
        'channels',
        {
          'last_message_id': null,
          'last_read_message_id': null,
          'unread_count': 0,
        },
        where: 'channel_id = ?',
        whereArgs: [channelId],
      );
    });
    _notify(const {'messages', 'channels'});
  }

  /// Local-only group leave. Drops the channel row (cascades members,
  /// messages, reactions via FK ON DELETE CASCADE). Throws if [channelId]
  /// is a DM — DM channels must remain consistent across both sides
  /// because the channel_id is the stable address for incoming messages
  /// from the peer; deleting and recreating would fork the conversation.
  ///
  /// The server-side fanout is the caller's responsibility — see
  /// `ChatService.leaveGroup`, which enqueues the outbound
  /// `OpKind.deleteChannel` op before invoking this method for
  /// optimistic local removal.
  Future<void> leaveGroupLocal(String channelId) async {
    final rows = await db.query(
      'channels',
      columns: const ['kind'],
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final kind = rows.single['kind'] as String;
    if (kind != 'group') {
      throw StateError(
        'leaveGroupLocal called on non-group channel ($kind). '
        'DM channels must not be deleted — clear messages instead.',
      );
    }
    await db.delete(
      'channels',
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    _notify(const {'channels', 'channel_members', 'messages'});
  }

  /// Owner "Delete group" (decision 9) — the optimistic local half of
  /// `DELETE /v3.0/channels/{id}`. Tombstones rather than hard-deletes,
  /// exactly like the inbound `ChannelDeleted` this action will fan to
  /// everyone else ([applyChannelDelete]), so the owner's own copy of
  /// that fanout is a no-op instead of resurrecting anything. Throws on
  /// a non-group channel, same rule as [leaveGroupLocal].
  Future<void> deleteGroupLocal(String channelId) async {
    final rows = await db.query(
      'channels',
      columns: const ['kind'],
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final kind = rows.single['kind'] as String;
    if (kind != 'group') {
      throw StateError(
        'deleteGroupLocal called on non-group channel ($kind). '
        'DM channels cannot be deleted — clear messages instead.',
      );
    }
    await tombstoneChannel(channelId);
  }

  /// Local-only pin flag — V3_ARCHITECTURE decision 3 offline matrix.
  /// Pinned channels sort first in [fetchChannelList]. No outbound op.
  Future<void> setChannelPinned(String channelId, bool pinned) async {
    await db.update(
      'channels',
      {'pinned': pinned ? 1 : 0},
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    _notify(const {'channels'});
  }

  /// Local-only mute — `null` clears it, a far-future epoch-ms value is
  /// the mute sheet's "Always". Push gating against this column is
  /// server-side work (V3_RELEASE_PLAN open item 13); today it only
  /// drives the UI.
  Future<void> setChannelMuted(String channelId, int? untilMs) async {
    await db.update(
      'channels',
      {'muted_until_ms': untilMs},
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    _notify(const {'channels'});
  }

  /// "Delete chat" — local-only, and deliberately *not*
  /// [leaveGroupLocal]. Erases history and hides the row from the chat
  /// list; the channel row, its membership and its place in the Groups
  /// listing all survive, and the next message in either direction
  /// clears `deleted_locally` and brings the chat back.
  Future<void> deleteChatLocal(String channelId) async {
    await clearChannelMessages(channelId);
    await db.update(
      'channels',
      {'deleted_locally': 1},
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    _notify(const {'channels'});
  }

  /// Image-bearing messages in [channelId], newest first. Powers the
  /// "Media, links and docs" screen. Attachment blobs land with the
  /// attachment work; the query is real now, so the screen fills
  /// itself the moment image messages exist.
  Future<List<MessageRow>> fetchChannelMedia(
    String channelId, {
    int limit = 200,
  }) async {
    final rows = await db.query(
      'messages',
      where: "channel_id = ? AND tombstoned = 0 "
          "AND content_type LIKE 'image/%'",
      whereArgs: [channelId],
      orderBy: 'client_timestamp_ms DESC',
      limit: limit,
    );
    return rows.map(_rowToMessage).toList();
  }

  /// Non-image attachments in [channelId], newest first — the file
  /// list under the media grid. Mirror image of [fetchChannelMedia];
  /// a message with no attachment blob is neither.
  Future<List<MessageRow>> fetchChannelFiles(
    String channelId, {
    int limit = 200,
  }) async {
    final rows = await db.query(
      'messages',
      where: "channel_id = ? AND tombstoned = 0 AND attachments IS NOT NULL "
          "AND (content_type IS NULL OR content_type NOT LIKE 'image/%')",
      whereArgs: [channelId],
      orderBy: 'client_timestamp_ms DESC',
      limit: limit,
    );
    return rows.map(_rowToMessage).toList();
  }

  /// Replace a message's `attachments` BLOB in place — used once an
  /// upload completes and the placeholder local file path in the
  /// `Attachment` becomes the server-side fileId. Leaves every other
  /// column (and the message's position in the channel view) alone.
  Future<void> setMessageAttachments({
    required String messageId,
    required Uint8List attachments,
  }) async {
    await db.update(
      'messages',
      {'attachments': attachments},
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    _notify(const {'messages'});
  }

  /// Local projection of a group photo change. The server's own
  /// `ChannelEdited` fanout writes the same column for every other
  /// member; this is the editor's optimistic copy.
  Future<void> setChannelAvatar(String channelId, String? avatarUrl) async {
    await db.update(
      'channels',
      {'avatar_url': avatarUrl},
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );
    _notify(const {'channels'});
  }

  /// A single channel with its local settings, for the group-info
  /// header and its "Muted until …" bar. Unlike [fetchChannelList]
  /// this does not require the channel to have messages — group info
  /// opens on empty and locally deleted groups too.
  Future<ChannelListEntry?> fetchChannel(String channelId) async {
    final rows = await db.rawQuery(
      '''
      SELECT c.channel_id, c.kind, c.name, c.avatar_url,
             c.last_activity_ms, c.unread_count,
             (SELECT ct.username FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_username,
             (SELECT ct.display_name FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_display_name,
             (SELECT ct.contact_book_name FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_contact_book_name,
             (SELECT ct.user_id FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_user_id,
             c.pinned, c.muted_until_ms,
             m.body AS last_message_preview,
             m.author_user_id AS last_message_author,
             m.tombstoned AS last_message_tombstoned
      FROM channels c
      LEFT JOIN messages m ON m.message_id = c.last_message_id
      WHERE c.channel_id = ?
      ''',
      [channelId],
    );
    if (rows.isEmpty) return null;
    return _rowToChannelListEntry(rows.single);
  }

  /// Channels where the current user is an active member, optionally
  /// filtered by `kind`. Powers the Groups tab in the new-chat picker.
  /// Sort: alphabetical by name, falling back to channel_id.
  Future<List<ChannelListEntry>> fetchMemberChannels({
    required String userId,
    String? kind,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT c.channel_id, c.kind, c.name, c.avatar_url,
             c.last_activity_ms, c.unread_count,
             (SELECT ct.username FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_username,
             (SELECT ct.display_name FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_display_name,
             (SELECT ct.contact_book_name FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_contact_book_name,
             (SELECT ct.user_id FROM channel_members pm
                JOIN contacts ct ON ct.user_id = pm.user_id
               WHERE pm.channel_id = c.channel_id AND pm.removed_at IS NULL
                 AND c.kind = 'one_to_one' LIMIT 1) AS peer_user_id,
             c.pinned, c.muted_until_ms,
             m.body AS last_message_preview,
             m.author_user_id AS last_message_author,
             m.tombstoned AS last_message_tombstoned
      FROM channels c
      JOIN channel_members cm ON cm.channel_id = c.channel_id
        AND cm.user_id = ? AND cm.removed_at IS NULL
      LEFT JOIN messages m ON m.message_id = c.last_message_id
      WHERE c.tombstoned = 0 ${kind != null ? "AND c.kind = ?" : ""}
      ORDER BY COALESCE(c.name, c.channel_id) COLLATE NOCASE
      ''',
      kind != null ? [userId, kind] : [userId],
    );
    return rows.map(_rowToChannelListEntry).toList();
  }

  /// Reactive wrapper over [fetchMemberChannels]. Emits when channels or
  /// channel_members change.
  Stream<List<ChannelListEntry>> watchMemberChannels({
    required String userId,
    String? kind,
  }) {
    late StreamController<List<ChannelListEntry>> controller;
    StreamSubscription<Set<String>>? changeSub;

    Future<void> emit() => _safeEmit(
        controller, () => fetchMemberChannels(userId: userId, kind: kind));

    controller = StreamController<List<ChannelListEntry>>(
      onListen: () {
        changeSub = tableChanges.listen((tables) {
          if (tables.contains('channels') ||
              tables.contains('channel_members') ||
              tables.contains('contacts')) {
            emit();
          }
        });
        emit();
      },
      onCancel: () async {
        await changeSub?.cancel();
        changeSub = null;
      },
    );
    return controller.stream;
  }

  static ChannelListEntry _rowToChannelListEntry(Map<String, Object?> r) =>
      ChannelListEntry(
        channelId: r['channel_id'] as String,
        kind: r['kind'] as String,
        name: r['name'] as String?,
        avatarUrl: r['avatar_url'] as String?,
        lastActivityMs: r['last_activity_ms'] as int,
        unreadCount: r['unread_count'] as int,
        pinned: ((r['pinned'] as int?) ?? 0) != 0,
        mutedUntilMs: r['muted_until_ms'] as int?,
        hasFailedOp: ((r['has_failed_op'] as int?) ?? 0) != 0,
        lastMessagePreview: r['last_message_preview'] as String?,
        lastMessageAuthor: r['last_message_author'] as String?,
        lastMessageTombstoned:
            ((r['last_message_tombstoned'] as int?) ?? 0) != 0,
        // Only the `one_to_one` subqueries above ever produce a peer;
        // the AUTH_CONTRACT §2.4 resolution itself stays in
        // ContactRow.displayLabel, this just supplies it the row.
        peerContact: r['peer_user_id'] == null
            ? null
            : ContactRow(
                userId: r['peer_user_id'] as String,
                username: r['peer_username'] as String?,
                displayName: r['peer_display_name'] as String?,
                contactBookName: r['peer_contact_book_name'] as String?,
                lastRefreshedMs: 0,
              ),
      );

  // --- Local message mutations (§5.3 + V3_ARCHITECTURE decision 11) ------

  /// Optimistic local edit. Snapshots the pre-edit body into
  /// `rollback_body` (keeping the oldest snapshot if an earlier edit is
  /// still in flight, so a rollback lands on the last server-known
  /// text) and enqueues [op] in the same transaction.
  ///
  /// `last_edit_ms` is deliberately NOT stamped here — it is the
  /// server-side edit time, written by [applyInboundMessageUpdate] for
  /// a peer's edit and by [applyMessageOpAck] for our own. Its
  /// nullness is what tells a rollback whether the "edited" label
  /// predates this attempt.
  Future<void> enqueueMessageEdit({
    required String messageId,
    required String newBody,
    required OutboundOpRow op,
    required int nowMs,
  }) async {
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE messages '
        '   SET rollback_body = COALESCE(rollback_body, body), '
        '       body = ?, is_edited = 1, state_updated_at = ? '
        ' WHERE message_id = ?',
        [newBody, nowMs, messageId],
      );
      await txn.insert('outbound_ops', await _opRowWithSeq(txn, op));
    });
    _notify(const {'messages', 'outbound_ops'});
  }

  /// Decision 11 step 1 — tombstone locally and open the Undo window.
  /// Nothing is enqueued yet: an Undo inside the window costs no op at
  /// all. The body is kept so [undoTombstone] (or a rejected delete)
  /// can put the message back; [applyMessageOpAck] clears it once the
  /// delete is the server's problem.
  Future<void> beginTombstone({
    required String messageId,
    required int pendingUntilMs,
    required int nowMs,
  }) async {
    await db.update(
      'messages',
      {
        'tombstoned': 1,
        'tombstone_pending_until': pendingUntilMs,
        'state_updated_at': nowMs,
      },
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    _notify(const {'messages'});
  }

  /// Undo inside the window — the message comes back untouched.
  Future<void> undoTombstone({
    required String messageId,
    required int nowMs,
  }) async {
    await db.update(
      'messages',
      {
        'tombstoned': 0,
        'tombstone_pending_until': null,
        'state_updated_at': nowMs,
      },
      where: 'message_id = ? AND tombstone_pending_until IS NOT NULL',
      whereArgs: [messageId],
    );
    _notify(const {'messages'});
  }

  /// Decision 11 step 2 — the window elapsed: clear the pending marker
  /// and enqueue the MESSAGE_DELETE op atomically.
  ///
  /// The `tombstone_pending_until IS NOT NULL` guard is what makes the
  /// commit and an Undo racing it resolve deterministically: whichever
  /// runs first wins, and a commit that loses enqueues nothing.
  /// Returns true iff the op was enqueued.
  Future<bool> commitTombstone({
    required String messageId,
    required OutboundOpRow op,
  }) async {
    var committed = false;
    await db.transaction((txn) async {
      final n = await txn.update(
        'messages',
        {'tombstone_pending_until': null},
        where: 'message_id = ? AND tombstone_pending_until IS NOT NULL',
        whereArgs: [messageId],
      );
      if (n == 0) return;
      await txn.insert('outbound_ops', await _opRowWithSeq(txn, op));
      committed = true;
    });
    if (committed) _notify(const {'messages', 'outbound_ops'});
    return committed;
  }

  /// Message ids in [channelId] whose Undo window has already elapsed —
  /// the app was killed, or the user navigated away, before the commit
  /// timer fired. Swept on chat open.
  Future<List<String>> expiredTombstones({
    required String channelId,
    required int nowMs,
  }) async {
    final rows = await db.query(
      'messages',
      columns: const ['message_id'],
      where: 'channel_id = ? AND tombstone_pending_until IS NOT NULL '
          'AND tombstone_pending_until <= ?',
      whereArgs: [channelId, nowMs],
    );
    return rows.map((r) => r['message_id'] as String).toList();
  }

  /// Optimistic local reaction toggle plus its outbound op, in one
  /// transaction. Mirrors [applyInboundReactionAdd] /
  /// [applyInboundReactionRemove] for the local user.
  Future<void> enqueueReaction({
    required String messageId,
    required String userId,
    required String emoji,
    required bool add,
    required OutboundOpRow op,
    required int nowMs,
  }) async {
    await db.transaction((txn) async {
      if (add) {
        await txn.rawInsert(
          'INSERT OR IGNORE INTO reactions '
          '(message_id, user_id, emoji, added_at) VALUES (?, ?, ?, ?)',
          [messageId, userId, emoji, nowMs],
        );
      } else {
        await txn.delete(
          'reactions',
          where: 'message_id = ? AND user_id = ? AND emoji = ?',
          whereArgs: [messageId, userId, emoji],
        );
      }
      await txn.insert('outbound_ops', await _opRowWithSeq(txn, op));
    });
    _notify(const {'reactions', 'outbound_ops'});
  }

  /// ACK for an op that does NOT own a message's lifecycle — a REST
  /// write, or an edit / delete / reaction on a row that is already
  /// `sent`. Drops the op row and finalizes the local projection:
  /// an edit's rollback snapshot is no longer needed (and its edit
  /// time is now known), and a delete's content can finally go.
  ///
  /// Unlike [applyAckSuccess] this never writes `delivery_sequence` —
  /// stamping an edit's sequence onto its target would reorder the
  /// message in the channel view.
  Future<void> applyMessageOpAck({
    required String opId,
    required String kind,
    required String? messageId,
    required int nowMs,
  }) async {
    await db.transaction((txn) async {
      await txn.delete('outbound_ops', where: 'op_id = ?', whereArgs: [opId]);
      if (messageId == null) return;
      switch (kind) {
        case OpKind.messageEdit:
          await txn.update(
            'messages',
            {'rollback_body': null, 'last_edit_ms': nowMs},
            where: 'message_id = ?',
            whereArgs: [messageId],
          );
        case OpKind.messageDelete:
          await txn.update(
            'messages',
            {
              'body': null,
              'content_type': null,
              'attachments': null,
              'rollback_body': null,
            },
            where: 'message_id = ?',
            whereArgs: [messageId],
          );
      }
    });
    _notify(const {'outbound_ops', 'messages'});
  }

  // --- row marshalling ---------------------------------------------------

  static Map<String, Object?> _messageToRow(MessageRow m) => {
        'message_id': m.messageId,
        'channel_id': m.channelId,
        'author_user_id': m.authorUserId,
        'body': m.body,
        'content_type': m.contentType,
        'reply_to_message_id': m.replyToMessageId,
        'attachments':
            m.attachments == null ? null : Uint8List.fromList(m.attachments!),
        'forward_source': null,
        'client_timestamp_ms': m.clientTimestampMs,
        'server_timestamp_ms': m.serverTimestampMs,
        'delivery_sequence': m.deliverySequence,
        'message_state': m.state.wire,
        'state_updated_at': m.stateUpdatedAt,
        'is_edited': m.isEdited ? 1 : 0,
        'last_edit_ms': m.lastEditMs,
        'tombstoned': m.tombstoned ? 1 : 0,
        'tombstone_pending_until': m.tombstonePendingUntil,
      };

  static MessageRow _rowToMessage(Map<String, Object?> r) => MessageRow(
        messageId: r['message_id'] as String,
        channelId: r['channel_id'] as String,
        authorUserId: r['author_user_id'] as String,
        body: r['body'] as String?,
        contentType: r['content_type'] as String?,
        replyToMessageId: r['reply_to_message_id'] as String?,
        clientTimestampMs: r['client_timestamp_ms'] as int,
        serverTimestampMs: r['server_timestamp_ms'] as int?,
        deliverySequence: r['delivery_sequence'] as int?,
        state: MessageState.fromWire(r['message_state'] as String),
        stateUpdatedAt: r['state_updated_at'] as int,
        isEdited: (r['is_edited'] as int) != 0,
        lastEditMs: r['last_edit_ms'] as int?,
        tombstoned: (r['tombstoned'] as int) != 0,
        tombstonePendingUntil: r['tombstone_pending_until'] as int?,
        attachments: r['attachments'] as List<int>?,
        reactions: _parseReactions(r['reactions'] as String?),
      );

  /// Inverse of the `group_concat` in [fetchChannelMessages]. Null for
  /// every read that doesn't select the subquery.
  static List<MessageReaction> _parseReactions(String? packed) {
    if (packed == null || packed.isEmpty) return const [];
    final out = <MessageReaction>[];
    for (final pair in packed.split('\u001e')) {
      final sep = pair.indexOf('\u001f');
      if (sep <= 0) continue;
      out.add(MessageReaction(
        userId: pair.substring(0, sep),
        emoji: pair.substring(sep + 1),
      ));
    }
    return out;
  }

  static Map<String, Object?> _outboundOpToRow(OutboundOpRow o) => {
        'op_id': o.opId,
        'transport': o.transport.wire,
        'kind': o.kind,
        'rest_method': o.restMethod,
        'rest_path': o.restPath,
        'resource_id': o.resourceId,
        'resource_seq': o.resourceSeq,
        'payload': Uint8List.fromList(o.payload),
        'status': o.status.wire,
        'attempts': o.attempts,
        'next_retry_at': o.nextRetryAt,
        'dispatched_at': o.dispatchedAt,
        'last_error': o.lastError,
        'acknowledged_at': o.acknowledgedAt,
        'created_at': o.createdAt,
        'target_message_id': o.targetMessageId,
        'target_channel_id': o.targetChannelId,
      };

  static OutboundOpRow _rowToOutboundOp(Map<String, Object?> r) => OutboundOpRow(
        opId: r['op_id'] as String,
        transport: OpTransport.fromWire(r['transport'] as String),
        kind: r['kind'] as String,
        restMethod: r['rest_method'] as String?,
        restPath: r['rest_path'] as String?,
        resourceId: r['resource_id'] as String,
        resourceSeq: r['resource_seq'] as int,
        payload: (r['payload'] as List<int>),
        status: OpStatus.fromWire(r['status'] as String),
        attempts: r['attempts'] as int,
        nextRetryAt: r['next_retry_at'] as int,
        dispatchedAt: r['dispatched_at'] as int?,
        lastError: r['last_error'] as String?,
        acknowledgedAt: r['acknowledged_at'] as int?,
        createdAt: r['created_at'] as int,
        targetMessageId: r['target_message_id'] as String?,
        targetChannelId: r['target_channel_id'] as String?,
      );
}
