import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/config/client_factory.dart';

bool get _isWorkmanagerSupported => Platform.isAndroid || Platform.isIOS;

class WorkmanagerTasks {
  static const String syncTaskName = 'taskq_background_sync';

  static void initialize() {
    if (!_isWorkmanagerSupported) return;
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
  }

  static void registerSyncTask() {
    if (!_isWorkmanagerSupported) return;
    Workmanager().registerOneOffTask(
      "${syncTaskName}_${DateTime.now().millisecondsSinceEpoch}",
      syncTaskName,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('[Background] Running task: $taskName');

    if (taskName != WorkmanagerTasks.syncTaskName) return true;

    try {
      await AppConfig.initialize();

      final client = createClient();
      await client.auth.checkAuth();

      if (!client.auth.isAuthenticated) {
        debugPrint('[Background] Not authenticated. Aborting sync.');
        return true;
      }

      await client.init();
      await client.scheduler.run(returnOnCompletion: true);
      debugPrint('[Background] Scheduler finished.');
    } catch (e) {
      debugPrint('[Background] Task error: $e');
      return false;
    }

    return true;
  });
}
