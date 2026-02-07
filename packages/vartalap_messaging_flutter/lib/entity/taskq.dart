import 'package:drift/drift.dart';
import 'package:taskq/task.dart' show TaskStatus;
import 'package:vartalap_messaging_flutter/converter/converter.dart';

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text().withLength(max: 50)();
  TextColumn get payload => text().named('payload')();
  TextColumn get state => text().named('state').map(MapConverter())();
  IntColumn get status => intEnum<TaskStatus>()();
}

class TaskDependencies extends Table {
  IntColumn get taskId => integer().references(Tasks, #id)();
  @ReferenceName("ref_dependenct_task_id")
  IntColumn get dependentTaskId => integer().references(Tasks, #id)();
}
