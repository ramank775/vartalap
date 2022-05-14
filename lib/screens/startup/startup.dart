import 'dart:async';

import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/config_provider.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/widgets/rich_message.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({Key? key}) : super(key: key);

  Future<void> _initializeApp(
      ConfigStore configStore, BuildContext context) async {
    var value = await Permission.contacts.status;
    if (value.isGranted) {
      onContactPermissionGranted(context);
      onNext(context);
    } else {
      final dialog = AlertDialog(
        title: Icon(
          Icons.contact_page_rounded,
          size: 40,
        ),
        titleTextStyle: TextStyle(fontSize: 14),
        content: RichMessage(
          "To help you connect with friends and family, allow ${configStore.packageInfo.appName} access to your contacts.",
          TextStyle(
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            child: Text("Not Now"),
            onPressed: () {
              Navigator.of(context).pop();
              onNext(context);
            },
          ),
          TextButton(
              child: Text("Continue"),
              onPressed: () async {
                Navigator.of(context).pop();
                final value = await Permission.contacts.request();
                if (value.isGranted) {
                  onContactPermissionGranted(context);
                  onNext(context);
                }
              }),
        ],
      );
      showDialog(context: context, builder: (BuildContext context) => dialog);
    }
  }

  void onNext(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => Chats(),
      ),
      (route) => false,
    );
  }

  void onContactPermissionGranted(BuildContext context) {
    unawaited(UserService.syncContacts(onInit: true));
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
