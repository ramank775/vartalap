import 'package:drift/drift.dart';
import 'package:taskq/storage/task_store.dart';
import 'package:taskq/task.dart' show TaskStatus;
import 'package:vartalap_messaging_flutter/db/chat_db.dart';

class ChatTaskStore implements TaskStore {
  final ChatDatabase _db;

  ChatTaskStore(this._db);

  @override
  Future<T> transaction<T>(Future<T> Function() action) {
    return _db.transaction(action);
  }

  @override
  Future<List<int>> insertTasks(List<TaskInsert> tasks) async {
    final ids = <int>[];
    for (final task in tasks) {
      final id = await _db.into(_db.tasks).insert(
            TasksCompanion.insert(
              type: task.type,
              payload: task.payload,
              state: task.state,
              status: task.status,
            ),
          );
      ids.add(id);
    }
    return ids;
  }

  @override
  Future<void> insertDependencies(
      List<TaskDependencyInsert> dependencies) async {
    if (dependencies.isEmpty) return;
    final companions = dependencies
        .map(
          (dep) => TaskDependenciesCompanion.insert(
            taskId: dep.taskId,
            dependentTaskId: dep.dependentTaskId,
          ),
        )
        .toList();
    await _db.batch((batch) {
      batch.insertAll(_db.taskDependencies, companions);
    });
  }

  @override
  Future<Set<int>> getExistingTaskIds(Iterable<int> taskIds) async {
    if (taskIds.isEmpty) return {};
    final rows = await (_db.select(_db.tasks)
          ..addColumns([_db.tasks.id])
          ..where((t) => t.id.isIn(taskIds)))
        .get();
    return rows.map((row) => row.id).toSet();
  }

  @override
  Future<List<TaskRecord>> fetchTasksByStatus(TaskStatus status) async {
    final rows = await (_db.select(_db.tasks)
          ..where((t) => t.status.equals(status.index)))
        .get();
    return rows.map(_mapTask).toList();
  }

  @override
  Stream<List<TaskRecord>> watchTasksByStatus(TaskStatus status) {
    final query = (_db.select(_db.tasks)
      ..where((t) => t.status.equals(status.index)));
    return query.watch().map((rows) => rows.map(_mapTask).toList());
  }

  @override
  Future<void> updateStatus(int taskId, TaskStatus status) async {
    final query = _db.update(_db.tasks)..where((t) => t.id.equals(taskId));
    await query.write(TasksCompanion(status: Value(status)));
  }

  @override
  Future<void> deleteDependenciesFor(int taskId) async {
    await (_db.delete(_db.taskDependencies)
          ..where((dep) => dep.taskId.equals(taskId)))
        .go();
  }

  TaskRecord _mapTask(Task task) {
    return TaskRecord(
      id: task.id,
      type: task.type,
      payload: task.payload,
      state: task.state,
      status: task.status,
    );
  }
}
