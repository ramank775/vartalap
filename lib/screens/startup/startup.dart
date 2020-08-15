import 'package:chat_flutter_app/screens/chats/chats.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class StartupScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return StartupScreenState();
  }
}

class StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    Permission.contacts.request().then((value) {
      if (value.isGranted) {
        print("Permission Granted");
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (context) => Chats()));
      }
      if (value.isPermanentlyDenied) {
        openAppSettings();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).backgroundColor,
      ),
      child: Center(
        child: Text("Chat App"),
      ),
    );
  }
}
