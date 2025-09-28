import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/new_chat/create_group.dart';
import 'package:vartalap/screens/new_chat/select_group_member.dart';
import 'package:vartalap/screens/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/performance_metric.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/auth_listener.dart';
import 'package:vartalap/widgets/Inherited/config_provider.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/services/crashlystics.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

final configStore = ConfigStore();
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configStore.loadConfig();
  VartalapChatClientFlutter client = VartalapChatClientFlutter(
    apiKey: configStore.get('apiKey'),
    apiBaseUrl: configStore.get('api_url'),
    wsUrl: configStore.get('ws_url'),
  );
  final homescreen = await initializeApp(client);
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };
  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  runApp(Home(configStore.packageInfo.appName, homescreen, client));
}

Future<Widget> initializeApp(VartalapChatClientFlutter client) async {
  await Firebase.initializeApp();
  await FirebaseAppCheck.instance.activate(
    // webRecaptchaSiteKey: 'recaptcha-v3-site-key',
    androidProvider: AndroidProvider.playIntegrity,
    appleProvider: AppleProvider.appAttestWithDeviceCheckFallback,
  );

  await AuthService.init(client);
  Crashlytics.init();
  PerformanceMetric.init();
  if (AuthService.instance.isLoggedIn()) {
    return StartupScreen();
  }
  return IntroductionScreen();
}

class Home extends StatefulWidget {
  final String appName;
  final Widget homeScreen;
  final VartalapChatClientFlutter client;
  const Home(this.appName, this.homeScreen, this.client, {super.key});
  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  @override
  initState() {
    super.initState();
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ConfigProvider(
      configStore: configStore,
      child: _buildAppWithConditionalClientManager(),
    );
  }

  Widget _buildAppWithConditionalClientManager() {
    // Check if user is logged in to determine app structure
    final isLoggedIn = AuthService.instance.isLoggedIn();

    if (isLoggedIn) {
      // User is logged in - provide full client management
      return VartalapClientManager(
        client: widget.client,
        child: AuthListner(
          app: MaterialApp(
            title: widget.appName,
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigatorKey,
            themeMode: VartalapTheme.themeMode,
            theme: VartalapTheme.lightTheme.appTheme,
            darkTheme: VartalapTheme.darkTheme.appTheme,
            onGenerateRoute: _routes(),
            home: widget.homeScreen,
          ),
        ),
      );
    } else {
      // User is not logged in - simple app without client management
      return MaterialApp(
        title: widget.appName,
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        themeMode: VartalapTheme.themeMode,
        theme: VartalapTheme.lightTheme.appTheme,
        darkTheme: VartalapTheme.darkTheme.appTheme,
        onGenerateRoute: _routes(),
        home: widget.homeScreen,
      );
    }
  }

  RouteFactory _routes() {
    return (RouteSettings settings) {
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

  @override
  void dispose() {
    AuthService.instance.dispose();
    super.dispose();
  }
}
