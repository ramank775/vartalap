import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/models/auth_models.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/new_chat/create_group.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/screens/new_chat/select_group_member.dart';
import 'package:vartalap/screens/startup/startup.dart';
import 'package:vartalap/services/vartalap_authenticated_client.dart';
import 'package:vartalap/theme/theme.dart';
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

  final runAppStart = DateTime.now();
  runApp(VartalapApp());
  debugPrint('⏱️ [PERF] runApp() took: ${DateTime.now().difference(runAppStart).inMilliseconds}ms');
  debugPrint('🎯 [PERF] Total main() time: ${DateTime.now().difference(startTime).inMilliseconds}ms');

  // Analytics will initialize lazily when first used - no Firebase blocking!
  debugPrint('✅ [PERF] Firebase deferred to lazy initialization');
}


/// Main App Widget with Unified Authentication
class VartalapApp extends StatelessWidget {
  const VartalapApp({super.key});

  @override
  Widget build(BuildContext context) {
    final buildStart = DateTime.now();
    debugPrint('🏗️ [PERF] VartalapApp.build() started');

    final providerStart = DateTime.now();
    final authClient = VartalapAuthenticatedClient(
      client: VartalapChatClientFlutter(
        apiKey: AppConfig.apiKey,
        apiBaseUrl: AppConfig.apiUrl,
        wsUrl: AppConfig.wsUrl,
      ),
    );
    debugPrint('⏱️ [PERF] VartalapAuthenticatedClient creation took: ${DateTime.now().difference(providerStart).inMilliseconds}ms');

    return ChangeNotifierProvider<VartalapAuthenticatedClient>(
      create: (_) => authClient,
      child: Consumer<VartalapAuthenticatedClient>(
        builder: (context, authClient, _) {
          final materialAppStart = DateTime.now();
          final app = MaterialApp(
            title: AppConfig.packageInfo.appName,
            debugShowCheckedModeBanner: false,
            themeMode: VartalapTheme.themeMode,
            theme: VartalapTheme.lightTheme.appTheme,
            darkTheme: VartalapTheme.darkTheme.appTheme,
            onGenerateRoute: _routes,
            home: _buildHomeScreen(authClient),
          );
          debugPrint('⏱️ [PERF] MaterialApp creation took: ${DateTime.now().difference(materialAppStart).inMilliseconds}ms');
          debugPrint('🎯 [PERF] Total VartalapApp.build() time: ${DateTime.now().difference(buildStart).inMilliseconds}ms');
          return app;
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
      case AuthState.unauthenticated:
      case AuthState.sendingOTP:
      case AuthState.otpSent:
      case AuthState.verifyingOTP:
        return IntroductionScreen();
    }
  }

  /// Route factory for the application
  RouteFactory get _routes => (RouteSettings settings) {
    Widget widget;
    switch (settings.name) {
      case '/':
        widget = StartupScreen();
        break;
      case '/chats':
        widget = Chats();
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
        widget = Chats();
    }
    return MaterialPageRoute(builder: (BuildContext context) => widget);
  };
}
