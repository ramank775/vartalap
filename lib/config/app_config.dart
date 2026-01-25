import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Application configuration using --dart-define build-time constants
/// Pure static implementation for maximum performance
class AppConfig {
  // Core configuration from --dart-define
  static const String apiKey = String.fromEnvironment('API_KEY', defaultValue: '');
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://vartalapapp.one9x.org',
  );
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'https://vartalapapp.one9x.org/wss',
  );

  // Static content - can be build-time defined or use defaults
  static const String description = String.fromEnvironment(
    'APP_DESCRIPTION',
    defaultValue: 'Vartalap is an open source personal chat messager. It is design to provide the level of transparency in the personal messaging application with your data.\n\nGithub Repo:\nFlutter App: - https://github.com/ramank775/vartalap\nBackend Server:- https://github.com/ramank775/chat-server \n\nIf you are an open source contributor and interested in contributing towards this app, reach out to me at twitter @vartalap_app\nIf you have found any issue feel free to raise a issue on the Github or email on the developer mail vartalap@one9x.org.\nPrivacy Policy: https://vartalap.one9x.org/privacy-policy.',
  );

  static const String shareMessage = String.fromEnvironment(
    'SHARE_MESSAGE',
    defaultValue: "Let's chat on vartalap. It's an open source personal chatting application. Get it at https://vartalap.one9x.org",
  );

  static const String privacyPolicy = String.fromEnvironment(
    'PRIVACY_POLICY',
    defaultValue: 'https://vartalap.one9x.org/privacy-policy',
  );

  // Development mode configuration
  static const bool isMockMode = bool.fromEnvironment('MOCK_MODE', defaultValue: false);
  static bool isTesting = false;

  // App metadata - static singleton loaded once
  static late final PackageInfo packageInfo;
  static const String subtitle = "Open source personal chat messager";
  static bool _isInitialized = false;

  // Private constructor to prevent instantiation
  AppConfig._();

  /// Initialize package info - call once at app startup
  static Future<void> initialize() async {
    if (_isInitialized) return;
    isTesting = const bool.fromEnvironment('dart.library.io') && Platform.environment.containsKey('FLUTTER_TEST');
    final packageStart = DateTime.now();
    debugPrint('📦 [PERF] PackageInfo.fromPlatform() started');
    packageInfo = await PackageInfo.fromPlatform();
    _isInitialized = true;
    debugPrint('⏱️ [PERF] PackageInfo.fromPlatform() took: ${DateTime.now().difference(packageStart).inMilliseconds}ms');
  }

  /// Check if all required configuration is present
  static bool get isValid {
    return apiUrl.isNotEmpty && wsUrl.isNotEmpty;
  }

  /// Get environment info for debugging
  static String get environmentInfo {
    return '''
Environment: ${kDebugMode ? 'Development' : 'Production'}
Mock Mode: ${isMockMode ? 'Enabled' : 'Disabled'}
API URL: $apiUrl
WS URL: $wsUrl
API Key: ${apiKey.isEmpty ? 'Not Set' : 'Set (${apiKey.length} chars)'}
''';
  }
}