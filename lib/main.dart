import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/models/auth_models.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/new_chat/create_group.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/screens/new_chat/select_group_member.dart';
import 'package:vartalap/screens/startup/startup.dart';
import 'package:vartalap/services/crashlystics.dart';
import 'package:vartalap/services/performance_metric.dart';
import 'package:vartalap/services/vartalap_authenticated_client.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/config_provider.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

final configStore = ConfigStore();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configStore.loadConfig();

  // Initialize Firebase and core services
  await _initializeFirebase();
  Crashlytics.init();
  PerformanceMetric.init();

  // Set up global error handling
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(VartalapApp());
}

Future<void> _initializeFirebase() async {
  await Firebase.initializeApp();
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
    appleProvider: AppleProvider.appAttestWithDeviceCheckFallback,
  );
}

/// Main App Widget with Unified Authentication
class VartalapApp extends StatelessWidget {
  const VartalapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ConfigProvider(
      configStore: configStore,
      child: ChangeNotifierProvider<VartalapAuthenticatedClient>(
        create: (_) => VartalapAuthenticatedClient(
          client: VartalapChatClientFlutter(
            apiKey: configStore.get('apiKey'),
            apiBaseUrl: configStore.get('api_url'),
            wsUrl: configStore.get('ws_url'),
          ),
        )..initialize(),
        child: Consumer<VartalapAuthenticatedClient>(
          builder: (context, authClient, _) {
            return MaterialApp(
              title: configStore.packageInfo.appName,
              debugShowCheckedModeBanner: false,
              themeMode: VartalapTheme.themeMode,
              theme: VartalapTheme.lightTheme.appTheme,
              darkTheme: VartalapTheme.darkTheme.appTheme,
              onGenerateRoute: _routes,
              home: _buildHomeScreen(authClient),
            );
          },
        ),
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
