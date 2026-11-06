part of 'chat_store.dart';

/// A label the user tags contacts with (decision 223). It never leaves
/// the phone: a timeline post names user ids, never a label.
class Label {
  final int labelId;
  final String name;
  final Set<String> userIds;

  const Label({
    required this.labelId,
    required this.name,
    this.userIds = const {},
  });
}

/// Labels (decision 223), on the same database and change feed as the
/// chats.
extension LabelsStore on ChatStore {
  Future<List<Label>> fetchLabels() async {
    final labels = await db.query('labels', orderBy: 'label_id');
    final members = await db.query('label_members');
    return [
      for (final l in labels)
        Label(
          labelId: l['label_id'] as int,
          name: l['name'] as String,
          userIds: {
            for (final m in members)
              if (m['label_id'] == l['label_id']) m['user_id'] as String,
          },
        ),
    ];
  }

  /// [fetchLabels] on listen and again on every label change.
  Stream<List<Label>> watchLabels() {
    late StreamController<List<Label>> controller;
    StreamSubscription<Set<String>>? changeSub;
    Future<void> emit() => _safeEmit(controller, fetchLabels);
    controller = StreamController<List<Label>>(
      onListen: () {
        changeSub = tableChanges.listen((changed) {
          if (changed.contains('labels')) emit();
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

  Future<int> createLabel(String name) async {
    final id = await db.insert('labels', {'name': name});
    _notify(const {'labels'});
    return id;
  }

  Future<void> renameLabel(int labelId, String name) async {
    await db.update('labels', {'name': name},
        where: 'label_id = ?', whereArgs: [labelId]);
    _notify(const {'labels'});
  }

  /// Its members stay contacts; only the tag goes.
  Future<void> deleteLabel(int labelId) async {
    await db.delete('labels', where: 'label_id = ?', whereArgs: [labelId]);
    _notify(const {'labels'});
  }

  /// Who carries [labelId]: exactly [userIds].
  Future<void> setLabelMembers(int labelId, Set<String> userIds) async {
    await db.transaction((txn) async {
      await txn
          .delete('label_members', where: 'label_id = ?', whereArgs: [labelId]);
      for (final u in userIds) {
        await txn.insert('label_members', {'label_id': labelId, 'user_id': u});
      }
    });
    _notify(const {'labels'});
  }

  /// Which labels [userId] carries: exactly [labelIds].
  Future<void> setContactLabels(String userId, Set<int> labelIds) async {
    await db.transaction((txn) async {
      await txn
          .delete('label_members', where: 'user_id = ?', whereArgs: [userId]);
      for (final l in labelIds) {
        await txn.insert('label_members', {'label_id': l, 'user_id': userId});
      }
    });
    _notify(const {'labels'});
  }

  /// Who a post to [labelIds] reaches (null: everyone): the people we
  /// have a 1:1 chat with, so on Vartalap and (once invites land)
  /// connected, carrying any of those labels. Sorted, no duplicates.
  Future<List<String>> timelineAudience({
    required String selfUserId,
    Set<int>? labelIds,
  }) async {
    final labelled = labelIds == null
        ? ''
        : 'AND cm.user_id IN (SELECT user_id FROM label_members '
            'WHERE label_id IN (${List.filled(labelIds.length, '?').join(',')}))';
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT cm.user_id FROM channel_members cm
        JOIN channels c ON c.channel_id = cm.channel_id
       WHERE c.kind = 'one_to_one' AND c.tombstoned = 0
         AND cm.removed_at IS NULL AND cm.user_id != ?
         $labelled
       ORDER BY cm.user_id
      ''',
      [selfUserId, ...?labelIds],
    );
    return [for (final r in rows) r['user_id'] as String];
  }
}
