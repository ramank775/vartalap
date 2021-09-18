import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/new_chat/create_group.dart';
import 'package:vartalap/screens/new_chat/select_group_member.dart';
import 'package:vartalap/screens/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/auth_listener.dart';
import 'package:vartalap/widgets/Inherited/config_provider.dart';
import 'models/chat.dart';
import 'models/user.dart';
import 'screens/chats/chats.dart';
import 'screens/chat/chat.dart';
import 'screens/new_chat/new_chat.dart';
import 'package:vartalap/services/crashlystics.dart';

final configStore = ConfigStore();
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await configStore.loadConfig();
  runZonedGuarded(() {
    runApp(Home(configStore.packageInfo.appName));
  }, (error, stackTrace) {
    Crashlytics.recordError(error, stackTrace);
  });
}

class Home extends StatefulWidget {
  final String appName;
  Home(this.appName);
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
      child: AuthListner(
        app: MaterialApp(
          title: widget.appName,
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          themeMode: VartalapTheme.themeMode,
          theme: VartalapTheme.lightTheme.appTheme,
          darkTheme: VartalapTheme.darkTheme.appTheme,
          onGenerateRoute: _routes(),
          home: StartupScreen(),
        ),
      ),
    );
  }

  RouteFactory _routes() {
    return (RouteSettings settings) {
      Widget widget;
      switch (settings.name) {
        case '/':
          widget = new StartupScreen();
          break;
        case '/chats':
          widget = new Chats();
          break;
        case '/chat':
          widget = new ChatScreen(settings.arguments as Chat);
          break;
        case '/new-chat':
          widget = new NewChatScreen();
          break;
        case '/new-group':
          widget = new SelectGroupMemberScreen();
          break;
        case '/create-group':
          widget = new CreateGroup(settings.arguments as List<User>);
          break;
        default:
          widget = new Chats();
      }
      return new MaterialPageRoute(builder: (BuildContext context) => widget);
    };
  }

  @override
  void dispose() {
    ChatService.dispose();
    super.dispose();
  }
}
