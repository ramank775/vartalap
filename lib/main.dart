import 'package:flutter/material.dart';
import 'screens/chats/chats.dart';
import 'screens/chat/chat.dart';
import 'screens/new_chat/new_chat.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
        // This makes the visual density adapt to the platform that you run
        // the app on. For desktop platforms, the controls will be smaller and
        // closer together (more dense) than on mobile platforms.
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      onGenerateRoute: _routes(),
      home: new Chats(),
    );
  }

  RouteFactory _routes() {
    return (RouteSettings settings) {
      Widget widget;

      switch (settings.name) {
        case '/':
          widget = new Chats();
          break;
        case '/chat':
          widget = new ChatScreen(settings.arguments);
          break;
        case '/new-chat':
          widget = new NewChat();
          break;
        default:
          widget = new Chats();
      }
      return new MaterialPageRoute(builder: (BuildContext context) => widget);
    };
  }
}
