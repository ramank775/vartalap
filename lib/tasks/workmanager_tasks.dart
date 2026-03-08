import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/services/otp/firebase_otp_provider.dart';
import 'package:vartalap/services/otp/iotp_provider.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_testing/vartalap_testing.dart';

class WorkmanagerTasks {
  static const String syncTaskName = 'taskq_background_sync';

  static void initialize() {
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
  }

  static void registerSyncTask() {
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
    
    // We only want to handle our sync task
    if (taskName != WorkmanagerTasks.syncTaskName) return true;

    try {
      // 1. Initialize configuration for backend URLs
      await AppConfig.initialize();

      // 2. Initialize the client manually without UI attached
      final tokenManager = SecureStorageTokenManager();
      final chatClientStr = AppConfig.isMockMode
          ? MockVartalapChatClient(tokenManager: tokenManager)
          : VartalapChatClient(
              apiKey: AppConfig.apiKey,
              apiBaseUrl: AppConfig.apiUrl,
              wsUrl: AppConfig.wsUrl,
              tokenManager: tokenManager,
            );

      final client = VartalapChatClientFlutter(
        apiKey: AppConfig.apiKey,
        apiBaseUrl: AppConfig.apiUrl,
        wsUrl: AppConfig.wsUrl,
        client: chatClientStr,
      );
      
      // Need to init Auth to get the user ID to open DB
      final otpProvider = AppConfig.isMockMode ? MockOTPProvider() : FirebaseOTPProvider();
      client.initAuth(otpProvider);
      
      await client.auth.checkAuth();
      if (!client.auth.isAuthenticated) {
        debugPrint('[Background] Could not authenticate. Aborting sync.');
        return true; 
      }
      
      // Initialize the database and scheduler exactly as normal
      await client.init();
      
      // Allow task scheduler to run up to completion for scheduled tasks
      debugPrint('[Background] Running scheduler...');
      await client.scheduler.run(returnOnCompletion: true);
      debugPrint('[Background] Scheduler finished.');

    } catch (e) {
      debugPrint('[Background] Task error: $e');
      return false; // Tells Workmanager it failed
    }
    
    return true; // Tells Workmanager it succeeded
  });
}
