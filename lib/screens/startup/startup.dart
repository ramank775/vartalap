import 'package:vartalap/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/services/connectivity_service.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    _requestPermissionsInBackground();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToChats();
    });
  }

  void _navigateToChats() {
    Navigator.of(context).pushNamedAndRemoveUntil('/chats', (route) => false);
  }

  void _requestPermissionsInBackground() async {
    try {
      await Future.wait([
        ConnectivityService().initialize(),
        Permission.notification.request(),
      ]);
    } catch (e) {
      debugPrint('Background permission setup failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packageInfo = AppConfig.packageInfo;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(color: theme.primaryColor),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppLogo(size: 50),
                  const Padding(padding: EdgeInsets.only(top: 10.0)),
                  Text(
                    packageInfo.appName,
                    style: VartalapTheme.theme.appTitleStyle.copyWith(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    AppConfig.subtitle,
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "v${packageInfo.version}+${packageInfo.buildNumber}",
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
