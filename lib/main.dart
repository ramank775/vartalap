import 'dart:async';

import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/new_chat/create_group.dart';
import 'package:vartalap/screens/new_chat/select_group_member.dart';
import 'package:vartalap/screens/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'models/chat.dart';
import 'models/user.dart';
import 'screens/chats/chats.dart';
import 'screens/chat/chat.dart';
import 'screens/new_chat/new_chat.dart';
import 'package:vartalap/services/crashanalystics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var store = ConfigStore();
  await store.loadConfig();
  runZonedGuarded(() {
    runApp(Home(store.packageInfo.appName));
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
  @override
  initState() {
    super.initState();
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeInfo.themeMode,
      theme: ThemeInfo.lightTheme,
      darkTheme: ThemeInfo.darkTheme,
      onGenerateRoute: _routes(),
      home: new StartupScreen(),
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
