import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/models/auth_models.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/login/verify_otp.dart';
import 'package:vartalap/screens/new_chat/create_group.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/screens/new_chat/select_group_member.dart';
import 'package:vartalap/screens/startup/startup.dart';
import 'package:vartalap/services/otp/firebase_otp_provider.dart';
import 'package:vartalap/services/otp/iotp_provider.dart';
import 'package:vartalap/services/vartalap_authenticated_client.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

void main() async {
  final startTime = DateTime.now();
  debugPrint('🚀 [PERF] App main() started at: ${startTime.millisecondsSinceEpoch}');

  final bindingStart = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('⏱️ [PERF] WidgetsFlutterBinding took: ${DateTime.now().difference(bindingStart).inMilliseconds}ms');

  final configStart = DateTime.now();
  await AppConfig.initialize();
  debugPrint('⏱️ [PERF] AppConfig.initialize took: ${DateTime.now().difference(configStart).inMilliseconds}ms');

  // Create and initialize auth client before running the app
  final authClientStart = DateTime.now();
  final authClient = _createAuthClient();
  await authClient.initialize();
  debugPrint('⏱️ [PERF] AuthClient initialization took: ${DateTime.now().difference(authClientStart).inMilliseconds}ms');

  final runAppStart = DateTime.now();
  runApp(VartalapApp(authClient: authClient));
  debugPrint('⏱️ [PERF] runApp() took: ${DateTime.now().difference(runAppStart).inMilliseconds}ms');
  debugPrint('🎯 [PERF] Total main() time: ${DateTime.now().difference(startTime).inMilliseconds}ms');

  // Analytics will initialize lazily when first used - no Firebase blocking!
  debugPrint('✅ [PERF] Firebase deferred to lazy initialization');
}

VartalapAuthenticatedClient _createAuthClient() {
  // Create appropriate client based on MOCK_MODE flag
  final tokenManager = SecureStorageTokenManager();
  final chatClient = AppConfig.isMockMode
      ? MockVartalapChatClient(tokenManager: tokenManager)
      : VartalapChatClient(
          apiKey: AppConfig.apiKey,
          apiBaseUrl: AppConfig.apiUrl,
          wsUrl: AppConfig.wsUrl,
          tokenManager: tokenManager,
        );

  // Create appropriate OTP provider based on MOCK_MODE flag
  final otpProvider = AppConfig.isMockMode
      ? OTPProviderFactory.createTest()
      : FirebaseOTPProvider();

  final authClient = VartalapAuthenticatedClient(
    client: VartalapChatClientFlutter(
      apiKey: AppConfig.apiKey,
      apiBaseUrl: AppConfig.apiUrl,
      wsUrl: AppConfig.wsUrl,
      client: chatClient,
    ),
    otpProvider: otpProvider,
  );

  if (AppConfig.isMockMode) {
    debugPrint('🎭 [MOCK] Running in MOCK MODE - no server required!');
  }

  return authClient;
}


/// Main App Widget with Unified Authentication
class VartalapApp extends StatelessWidget {
  final VartalapAuthenticatedClient authClient;

  const VartalapApp({super.key, required this.authClient});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<VartalapAuthenticatedClient>(
      create: (_) => authClient,
      child: Consumer<VartalapAuthenticatedClient>(
        builder: (context, authClient, _) {
          return MaterialApp(
            title: AppConfig.packageInfo.appName,
            debugShowCheckedModeBanner: false,
            themeMode: VartalapTheme.themeMode,
            theme: VartalapTheme.lightTheme.appTheme,
            darkTheme: VartalapTheme.darkTheme.appTheme,
            onGenerateRoute: _routes,
            home: _buildHomeScreen(authClient),
          );
        },
      ),
    );
  }

  /// Build the appropriate home screen based on authentication state
  Widget _buildHomeScreen(VartalapAuthenticatedClient authClient) {
    switch (authClient.state) {
      case AuthState.authenticated:
        return StartupScreen();
      case AuthState.error:
        return IntroductionScreen(); // Show login on error
      case AuthState.otpSent:
      case AuthState.verifyingOTP:
        return VerifyOtpWidget();
      case AuthState.unauthenticated:
      case AuthState.sendingOTP:
        return IntroductionScreen();
    }
  }

  /// Route factory for the application
  Route<dynamic>? _routes(RouteSettings settings) {
    return MaterialPageRoute(
      settings: settings,
      builder: (BuildContext context) {
        final authClient = Provider.of<VartalapAuthenticatedClient>(context, listen: false);

        Widget widget;
        switch (settings.name) {
          case '/':
            widget = StartupScreen();
            break;
          case '/verify-otp':
            widget = VerifyOtpWidget();
            break;
          case '/chats':
            // Wrap Chats with VartalapClientManager to provide client context
            widget = VartalapClientManager(
              client: authClient.client,
              child: const Chats(),
            );
            break;
          case '/chat':
            widget = ChatScreen(settings.arguments as ChatClient);
            break;
          case '/new-chat':
            widget = NewChatScreen();
            break;
          case '/new-group':
            widget = SelectGroupMemberScreen();
            break;
          case '/create-group':
            widget = CreateGroup(settings.arguments as List<Contact>);
            break;
          default:
            // Default route also wraps with VartalapClientManager
            widget = VartalapClientManager(
              client: authClient.client,
              child: const Chats(),
            );
        }
        return widget;
      },
    );
  }
}
