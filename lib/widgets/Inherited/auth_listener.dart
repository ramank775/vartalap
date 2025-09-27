import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/startup/startup.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap_messaging_flutter/models/contact.dart';

class AuthListner extends StatefulWidget {
  final MaterialApp app;
  const AuthListner({
    super.key,
    required this.app,
  });

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
        _isLogin = authService.isLoggedIn();
      });
      _isLogin = authService.isLoggedIn();
      _navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (ctx) => _isLogin ? StartupScreen() : IntroductionScreen(),
          ),
          (route) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final client = VartalapClientProvider.of(context).client;
    return FutureBuilder(
      future: client.getLoggedInUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text("Error"),
          );
        }
        Contact? user;
        if (snapshot.data != null) {
          user = Contact(
            id: 1,
            username: 'sampleUser',
            status: ContactStatus.active,
            phone: snapshot.data!.userId,
          );
        }
        return CurrentUser(
          user: user,
          child: widget.app,
        );
      },
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
