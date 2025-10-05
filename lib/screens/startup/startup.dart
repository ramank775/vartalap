import 'dart:async';

import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/services/connectivity_service.dart';
import 'package:vartalap/services/vartalap_authenticated_client.dart';
import 'package:vartalap/utils/error_types.dart';
import 'package:vartalap/widgets/error_widgets.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> with ErrorHandlingMixin {
  bool _isInitializing = true;
  AppError? _initializationError;
  String _currentStep = "Initializing...";

  Future<void> _initializeApp(BuildContext context) async {
    final startupStart = DateTime.now();
    debugPrint('🚀 [PERF] StartupScreen._initializeApp() started');

    try {
      final providerStart = DateTime.now();
      final authClient = Provider.of<VartalapAuthenticatedClient>(context, listen: false);
      debugPrint('⏱️ [PERF] Getting authClient from provider took: ${DateTime.now().difference(providerStart).inMilliseconds}ms');

      setState(() {
        _currentStep = "Checking authentication...";
      });

      final authInitStart = DateTime.now();
      await authClient.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutError(
          'Authentication check timed out.',
        ),
      );
      debugPrint('⏱️ [PERF] authClient.initialize() took: ${DateTime.now().difference(authInitStart).inMilliseconds}ms');

      final permissionsStart = DateTime.now();
      _requestPermissionsInBackground();
      debugPrint('⏱️ [PERF] Starting background permissions took: ${DateTime.now().difference(permissionsStart).inMilliseconds}ms');

      setState(() {
        _isInitializing = false;
      });

      debugPrint('🎯 [PERF] Total StartupScreen initialization: ${DateTime.now().difference(startupStart).inMilliseconds}ms');

      if (context.mounted) {
        onNext();
      }
    } catch (e) {
      debugPrint('❌ [PERF] StartupScreen initialization failed after: ${DateTime.now().difference(startupStart).inMilliseconds}ms');
      final error = ErrorMapper.mapException(e);
      setState(() {
        _isInitializing = false;
        _initializationError = error;
      });
    }
  }

  // Request permissions in background without blocking startup
  void _requestPermissionsInBackground() async {
    final backgroundStart = DateTime.now();
    debugPrint('📱 [PERF] Background permissions started');

    try {
      final connectivityStart = DateTime.now();
      final connectivityFuture = ConnectivityService().initialize();

      final notificationStart = DateTime.now();
      final notificationFuture = Permission.notification.request();

      await Future.wait([connectivityFuture, notificationFuture]);

      debugPrint('⏱️ [PERF] ConnectivityService.initialize took: ${DateTime.now().difference(connectivityStart).inMilliseconds}ms');
      debugPrint('⏱️ [PERF] Permission.notification.request took: ${DateTime.now().difference(notificationStart).inMilliseconds}ms');
      debugPrint('🎯 [PERF] Total background permissions: ${DateTime.now().difference(backgroundStart).inMilliseconds}ms');
    } catch (e) {
      debugPrint('❌ [PERF] Background permission setup failed after: ${DateTime.now().difference(backgroundStart).inMilliseconds}ms - $e');
    }
  }

  void onNext() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => Chats(),
      ),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packageInfo = AppConfig.packageInfo;

    return Scaffold(
      body: Column(
        children: [
          const OfflineIndicator(),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(color: theme.primaryColor),
                ),
                if (_initializationError != null)
                  _buildErrorState(theme, packageInfo)
                else
                  _buildLoadingState(theme, packageInfo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(
      ThemeData theme, packageInfo) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppLogo(size: 50),
              const Padding(
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
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isInitializing) ...[
                CircularProgressIndicator(
                  backgroundColor: Colors.white,
                  color: theme.iconTheme.color,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 20.0),
                ),
                Text(
                  _currentStep,
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme, packageInfo) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppLogo(size: 50),
              const Padding(
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
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.all(24),
            child: ErrorStateWidget(
              error: _initializationError!,
              onRetry: () {
                setState(() {
                  _isInitializing = true;
                  _initializationError = null;
                  _currentStep = "Retrying...";
                });
                _initializeApp(context);
              },
            ),
          ),
        ),
      ],
    );
  }
}
