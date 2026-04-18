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
  /// Newest-first by `last_activity_ms`. LEFT JOIN picks up the preview
  /// body from the `last_message_id` row; `tombstoned` is surfaced so
  /// the UI can render "message deleted" without a second query.
  Future<List<ChannelListEntry>> fetchChannelList({int limit = 100}) async {
    final rows = await db.rawQuery(
      '''
      SELECT c.channel_id, c.kind, c.name, c.avatar_url,
             c.last_activity_ms, c.unread_count,
             m.body AS last_message_preview,
             m.author_user_id AS last_message_author,
             m.tombstoned AS last_message_tombstoned
      FROM channels c
      LEFT JOIN messages m ON m.message_id = c.last_message_id
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
