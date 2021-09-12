import 'dart:async';

import 'package:package_info/package_info.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/crashlystics.dart';
import 'package:vartalap/services/performance_metric.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/config_provider.dart';
import 'package:vartalap/widgets/app_logo.dart';

class StartupScreen extends StatelessWidget {
  Future<void> _initializeApp(
      ConfigStore configStore, BuildContext context) async {
    List<Future> _promises = [];
    await AuthService.init();
    Crashlytics.init();
    PerformanceMetric.init();
    bool isLoggedIn = await UserService.isAuth();
    if (!isLoggedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (ctx) => IntroductionScreen(),
        ),
      );
      return;
    }

    ChatService.init().then((value) => null);
    var value = await Permission.contacts.request();
    if (value.isGranted) {
      _promises.add(UserService.syncContacts());
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => Chats(),
        ),
        (route) => false,
      );
      await Future.wait(_promises);
    }
    if (value.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configStore = ConfigProvider.of(context).configStore;
    this._initializeApp(configStore, context);
    final packageInfo = configStore.packageInfo;

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
                        packageInfo.appName,
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
                      "v${packageInfo.version}+${packageInfo.buildNumber}",
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
