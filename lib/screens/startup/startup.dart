import 'dart:async';

import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/config_provider.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/services/contact_service.dart';
import 'package:vartalap/services/connectivity_service.dart';
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

  Future<void> _initializeApp(
      ConfigStore configStore, BuildContext context) async {
    try {
      // Get client reference before any async operations
      final client = VartalapClientProvider.of(context).client;
      
      setState(() {
        _currentStep = "Checking connectivity...";
      });

      // Initialize connectivity service
      await ConnectivityService().initialize();

      setState(() {
        _currentStep = "Requesting permissions...";
      });

      // Request notification permission with error handling
      final notificationPermission = await Permission.notification.request();
      if (notificationPermission.isDenied) {
        throw PermissionError(
          'Notification permission is required for app functionality.',
          technicalDetails: 'Notification permission denied',
        );
      }

      setState(() {
        _currentStep = "Initializing client...";
      });

      // Initialize client with timeout
      await client.init().timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutError(
              'Client initialization timed out. Please check your internet connection.',
            ),
          );

      setState(() {
        _currentStep = "Syncing contacts...";
      });

      // Handle contacts with permission check
      final contactsPermission = await Permission.contacts.status;
      if (contactsPermission.isGranted) {
        try {
          final contacts = await ContactService.fetchDeviceContacts().timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutError(
              'Contact fetching timed out.',
            ),
          );
          await client.syncContacts(contacts);
        } on Exception catch (e) {
          // Don't fail initialization for contact sync errors
          debugPrint('Contact sync failed: $e');
        }
      }

      setState(() {
        _isInitializing = false;
      });

      // Small delay to show completion
      await Future.delayed(const Duration(milliseconds: 500));

      if (context.mounted) {
        onNext();
      }
    } catch (e) {
      final error = ErrorMapper.mapException(e);
      setState(() {
        _isInitializing = false;
        _initializationError = error;
      });
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
      final configStore = ConfigProvider.of(context).configStore;
      _initializeApp(configStore, context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configStore = ConfigProvider.of(context).configStore;
    final packageInfo = configStore.packageInfo;

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
                  _buildLoadingState(theme, configStore, packageInfo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(
      ThemeData theme, ConfigStore configStore, packageInfo) {
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
                configStore.subtitle,
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
                final configStore = ConfigProvider.of(context).configStore;
                _initializeApp(configStore, context);
              },
            ),
          ),
        ),
      ],
    );
  }
}
