import 'dart:async';

import 'package:package_info/package_info.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/login/login.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class StartupScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return StartupScreenState();
  }
}

class StartupScreenState extends State<StartupScreen> {
  PackageInfo info;
  @override
  void initState() {
    super.initState();
    List<Future> _promises = [];
    var configStore = ConfigStore();
    info = configStore.packageInfo;
    _promises.add(configStore.loadConfig());
    Timer(Duration(seconds: 1), () async {
      await Future.wait(_promises);
      await AuthService.init();
      bool isLoggedIn = await UserService.isAuth();
      if (!isLoggedIn) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (ctx) => LoginScreen(),
          ),
        );
        return;
      }
      _promises = [];
      _promises.add(ChatService.init());
      var value = await Permission.contacts.request();
      if (value.isGranted) {
        _promises.add(UserService.syncContacts());
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => Chats(),
          ),
        );
        await Future.wait(_promises);
      }
      if (value.isPermanentlyDenied) {
        openAppSettings();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(color: Colors.blueAccent),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 50.0,
                      child: Icon(Icons.chat_bubble_outline,
                          color: Colors.blueAccent, size: 50.0),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 10.0),
                    ),
                    Text(
                      info.appName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24.0,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  ],
                ),
              ),
            ),
            Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(backgroundColor: Colors.white),
                    Padding(
                      padding: EdgeInsets.only(top: 20.0),
                    ),
                    Text(
                      "Open source personal chat messager",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  ],
                ))
          ],
        )
      ],
    ));
  }
}
