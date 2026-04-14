import 'dart:async';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema.dart';
import 'types.dart';

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
    return ChatStore._(db);
  }

  Future<void> close() async {
    await _changes.close();
    await db.close();
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
      await txn.insert('outbound_ops', _outboundOpToRow(op));
      await txn.update(
        'channels',
        {'last_activity_ms': nowMs, 'last_message_id': message.messageId},
        where: 'channel_id = ?',
        whereArgs: [message.channelId],
      );
    });
    _notify(const {'messages', 'outbound_ops', 'channels'});
  }

  /// Flow A — dispatcher flip. Op row → `in_flight`, message → `sending`.
  Future<void> markOpInFlight({
    required String opId,
    required String messageId,
    required int nowMs,
  }) async {
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE outbound_ops '
        "SET status = 'in_flight', dispatched_at = ?, attempts = attempts + 1 "
        'WHERE op_id = ?',
        [nowMs, opId],
      );
      await txn.update(
        'messages',
        {
          'message_state': MessageState.sending.wire,
          'state_updated_at': nowMs,
        },
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
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
      await txn.update(
        'messages',
        {
          'message_state': MessageState.sent.wire,
          'state_updated_at': nowMs,
          'server_timestamp_ms': serverTimestampMs,
          'delivery_sequence': deliverySequence,
        },
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
    });
    _notify(const {'outbound_ops', 'messages'});
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
      if (messageId != null) {
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
    });
    _notify(
      messageId != null ? {'outbound_ops', 'messages'} : {'outbound_ops'},
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

      // Projection rollback — for v3.0 we only implement the
      // chat_payload new-message path: flip the optimistic message to
      // `rejected` so the UI can show a retry affordance. Edit/delete
      // rollback (restoring pre-edit body, clearing tombstone) lands
      // with the tombstone+undo work.
      if (messageId != null) {
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
    _notify(const {'outbound_ops', 'messages'});
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
      final seqRow = await txn.rawQuery(
        'SELECT MAX(resource_seq) m FROM outbound_ops WHERE resource_id = ?',
        [old.resourceId],
      );
      final maxSeq = seqRow.single['m'] as int?;
      final nextSeq = (maxSeq ?? 0) + 1;

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

      if (old.targetMessageId != null) {
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

  // --- row marshalling ---------------------------------------------------

  static Map<String, Object?> _messageToRow(MessageRow m) => {
        'message_id': m.messageId,
        'channel_id': m.channelId,
        'author_user_id': m.authorUserId,
        'body': m.body,
        'content_type': m.contentType,
        'reply_to_message_id': m.replyToMessageId,
        'attachments': null,
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
      );

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
