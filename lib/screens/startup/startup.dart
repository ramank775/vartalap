import 'dart:async';

import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/config_provider.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/app_logo.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({Key? key}) : super(key: key);

  Future<void> _initializeApp(
      ConfigStore configStore, BuildContext context) async {
    await Permission.notification.request();
    final client = VartalapClientProvider.of(context).client;
    await client.init();
    var value = await Permission.contacts.status;
    if (value.isGranted) {
      await client.syncContacts();
    }

    onNext(context);
  }

  void onNext(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => Chats(),
      ),
      (route) => false,
    );
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
                        style: VartalapTheme.theme.appTitleStyle.copyWith(
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
