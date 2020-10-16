import 'package:vartalap/screens/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/services/chat_service.dart';
import 'screens/chats/chats.dart';
import 'screens/chat/chat.dart';
import 'screens/new_chat/new_chat.dart';

void main() {
  runApp(Home());
}

class Home extends StatefulWidget {
  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vartalap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.comfortable,
        backgroundColor: Colors.grey[100],
      ),
      initialRoute: '/',
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
          widget = new ChatScreen(settings.arguments);
          break;
        case '/new-chat':
          widget = new NewChatScreen();
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
