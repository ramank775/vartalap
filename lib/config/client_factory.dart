import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/services/otp/firebase_otp_provider.dart';
import 'package:vartalap/services/otp/iotp_provider.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_testing/vartalap_testing.dart';

typedef ErrorReporter = Future<void> Function(dynamic exception, StackTrace stack, {String? reason});

/// Creates a fully configured VartalapChatClientFlutter with auth.
/// Used by both the main app and background task runner.
VartalapChatClientFlutter createClient({
  ErrorReporter? reportError,
  void Function()? onBackgroundTaskRequested,
}) {
  final tokenManager = SecureStorageTokenManager();
  final chatClient = AppConfig.isMockMode
      ? MockVartalapChatClient(tokenManager: tokenManager)
      : VartalapChatClient(
          apiKey: AppConfig.apiKey,
          apiBaseUrl: AppConfig.apiUrl,
          wsUrl: AppConfig.wsUrl,
          tokenManager: tokenManager,
        );

  final otpProvider = AppConfig.isMockMode
      ? MockOTPProvider()
      : FirebaseOTPProvider(reportError: reportError);

  final client = VartalapChatClientFlutter(
    apiKey: AppConfig.apiKey,
    apiBaseUrl: AppConfig.apiUrl,
    wsUrl: AppConfig.wsUrl,
    client: chatClient,
    onBackgroundTaskRequested: onBackgroundTaskRequested,
  );

  client.initAuth(otpProvider);
  return client;
}
