import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

/// App configuration backed by compile-time `--dart-define` values.
///
/// Usage:
///   flutter run --dart-define=API_URL=http://localhost:9777 \
///               --dart-define=WS_URL=ws://localhost:9777/wss
///
/// Omit flags for production defaults.
class ConfigStore {
  static ConfigStore _singleton = ConfigStore._internal();
  static bool _isInitialized = false;

  factory ConfigStore() => _singleton;
  ConfigStore._internal();

  // --- Compile-time constants (--dart-define) ----------------------------

  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://vartalapapp.one9x.org',
  );

  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'wss://vartalapapp.one9x.org/wss',
  );

  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://vartalap.one9x.org/privacy-policy',
  );

  // --- Runtime state (needs async init) ----------------------------------

  PackageInfo packageInfo = PackageInfo(
    appName: 'Vartalap',
    packageName: 'com.one9x.vartalap',
    buildNumber: '',
    version: '',
  );

  final String subtitle = "Open source personal chat messager";

  /// Initialize runtime state (PackageInfo + license).
  /// Call once at app boot before any widget reads [packageInfo].
  Future<void> init() async {
    if (_isInitialized) return;
    packageInfo = await PackageInfo.fromPlatform();

    LicenseRegistry.addLicense(() async* {
      final license = await rootBundle.loadString('LICENCE');
      yield LicenseEntryWithLineBreaks([packageInfo.appName], license);
    });
    _isInitialized = true;
  }
}
