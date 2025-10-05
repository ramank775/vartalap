/// Shared Firebase lazy initialization
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

class FirebaseInitializer {
  static bool _initialized = false;

  /// Ensures Firebase is initialized lazily
  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    final firebaseStart = DateTime.now();
    debugPrint('🔥 [PERF] Lazy Firebase initialization started');

    await Firebase.initializeApp();
    debugPrint('⏱️ [PERF] Firebase.initializeApp took: ${DateTime.now().difference(firebaseStart).inMilliseconds}ms');

    final appCheckStart = DateTime.now();
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.appAttestWithDeviceCheckFallback,
    );
    debugPrint('⏱️ [PERF] FirebaseAppCheck.activate took: ${DateTime.now().difference(appCheckStart).inMilliseconds}ms');

    _initialized = true;
    debugPrint('✅ [PERF] Firebase lazy initialization completed');
  }
}
