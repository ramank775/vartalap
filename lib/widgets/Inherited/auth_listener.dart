import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vartalap/screens/startup/startup.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';

class AuthListner extends StatefulWidget {
  final MaterialApp app;
  const AuthListner({
    Key? key,
    required this.app,
  }) : super(key: key);

  @override
  State<AuthListner> createState() => _AuthListnerState();
}

class _AuthListnerState extends State<AuthListner> {
  final authService = AuthService.instance;

  late StreamSubscription _sub;
  late GlobalKey<NavigatorState> _navigatorKey;
  late bool _isLogin;
  @override
  void initState() {
    super.initState();
    _isLogin = authService.isLoggedIn();
    _navigatorKey = widget.app.navigatorKey!;
    _sub = authService.authStateChange.listen((event) {
      setState(() {
        this._isLogin = authService.isLoggedIn();
      });
      this._navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (ctx) => StartupScreen(),
          ),
          (route) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CurrentUser(
      user: this._isLogin ? UserService.getLoggedInUser() : null,
      child: widget.app,
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
