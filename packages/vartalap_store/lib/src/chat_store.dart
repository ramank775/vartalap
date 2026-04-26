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

  /// Enqueue a standalone outbound op (no associated message row).
  /// Used for channel creation and other REST-only ops.
  Future<void> enqueueOutboundOp(OutboundOpRow op) async {
    await db.insert('outbound_ops', _outboundOpToRow(op));
    _notify(const {'outbound_ops'});
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
                '    unread_count = unread_count + 1 '
                'WHERE channel_id = ?'
            : 'UPDATE channels '
                'SET last_activity_ms = ?, last_message_id = ? '
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
    // A DM channel has kind='dm' and both users as members.
    final rows = await db.rawQuery(
      '''
      SELECT c.channel_id FROM channels c
      JOIN channel_members m1 ON c.channel_id = m1.channel_id
        AND m1.user_id = ? AND m1.removed_at IS NULL
      JOIN channel_members m2 ON c.channel_id = m2.channel_id
        AND m2.user_id = ? AND m2.removed_at IS NULL
      WHERE c.kind = 'dm' AND c.tombstoned = 0
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
             m.body AS last_message_preview,
             m.author_user_id AS last_message_author,
             m.tombstoned AS last_message_tombstoned
      FROM channels c
      JOIN messages m ON m.message_id = c.last_message_id
      WHERE c.tombstoned = 0
      ORDER BY c.last_activity_ms DESC
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

    Future<void> emit() async {
      if (controller.isClosed) return;
      controller.add(await fetchChannelList(limit: limit));
    }

    controller = StreamController<List<ChannelListEntry>>(
      onListen: () {
        changeSub = tableChanges.listen((tables) {
          if (tables.contains('channels') || tables.contains('messages')) {
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

  /// §13.2 — Channel chat view, newest-first, non-tombstoned only.
  ///
  /// `COALESCE(delivery_sequence, INT64_MAX)` sorts locally pending
  /// rows (null `delivery_sequence`) to the top, matching
  /// WhatsApp/Signal UX.
  Future<List<MessageRow>> fetchChannelMessages(
    String channelId, {
    int limit = 200,
    int offset = 0,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT m.*
      FROM messages m
      WHERE m.channel_id = ? AND m.tombstoned = 0
      ORDER BY COALESCE(m.delivery_sequence, 9223372036854775807) DESC,
               m.client_timestamp_ms DESC
      LIMIT ? OFFSET ?
      ''',
      [channelId, limit, offset],
    );
    return rows.map(_rowToMessage).toList();
  }

  /// Reactive wrapper over [fetchChannelMessages]. Emits on subscribe
  /// and every time the `messages` table changes.
  Stream<List<MessageRow>> watchChannelMessages(
    String channelId, {
    int limit = 200,
  }) {
    late StreamController<List<MessageRow>> controller;
    StreamSubscription<Set<String>>? changeSub;

    Future<void> emit() async {
      if (controller.isClosed) return;
      controller.add(await fetchChannelMessages(channelId, limit: limit));
    }

    controller = StreamController<List<MessageRow>>(
      onListen: () {
        changeSub = tableChanges.listen((tables) {
          if (tables.contains('messages')) emit();
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

    Future<void> emit() async {
      if (controller.isClosed) return;
      controller.add(await fetchMemberChannels(userId: userId, kind: kind));
    }

    controller = StreamController<List<ChannelListEntry>>(
      onListen: () {
        changeSub = tableChanges.listen((tables) {
          if (tables.contains('channels') ||
              tables.contains('channel_members')) {
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
        lastMessagePreview: r['last_message_preview'] as String?,
        lastMessageAuthor: r['last_message_author'] as String?,
        lastMessageTombstoned:
            ((r['last_message_tombstoned'] as int?) ?? 0) != 0,
      );

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
