import 'dart:async';

import 'package:package_info/package_info.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/crashanalystics.dart';
import 'package:vartalap/services/performance_metric.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';

class StartupScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return StartupScreenState();
  }
}

class StartupScreenState extends State<StartupScreen> {
  late PackageInfo info;
  var configStore = ConfigStore();
  @override
  void initState() {
    super.initState();
    initializeApp().then((value) => {info = configStore.packageInfo});
  }

  Future<void> initializeApp() async {
    List<Future> _promises = [];
    info = configStore.packageInfo;
    await AuthService.init();
    Crashlytics.init();
    PerformanceMetric.init();
    bool isLoggedIn = await UserService.isAuth();
    if (isLoggedIn) {
      ChatService.init().then((value) => null);
    }
    if (!isLoggedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (ctx) => IntroductionScreen(),
        ),
      );
      return;
    }
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
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(color: theme.primaryColor),
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
                      AppLogo(size: 50),
                      Padding(
                        padding: EdgeInsets.only(top: 10.0),
                      ),
                      Text(
                        info.appName,
                        style: ThemeInfo.appTitle.copyWith(
                          fontSize: 30,
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
                    CircularProgressIndicator(
                      backgroundColor: Colors.white,
                      color: theme.iconTheme.color,
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 20.0),
                    ),
                    Text(
                      configStore.subtitle,
                      style: TextStyle(
                          fontSize: 18.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    Text(
                      "v${info.version}+${info.buildNumber}",
                      style: TextStyle(color: Colors.white),
                    )
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }
}
