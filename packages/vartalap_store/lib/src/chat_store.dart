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

  ChatStore._(this.db);

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

  Future<void> close() => db.close();

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
