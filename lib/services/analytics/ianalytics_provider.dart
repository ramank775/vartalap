/// Simple analytics provider interface
library;

import 'package:flutter/foundation.dart';
import 'firebase_analytics_provider.dart';

/// Simple analytics provider interface
abstract class IAnalyticsProvider {
  /// Initialize the analytics provider
  Future<void> initialize();

  /// Record an error
  Future<void> recordError(dynamic exception, StackTrace? stack, {dynamic reason});

  /// Record a Flutter error
  Future<void> recordFlutterError(FlutterErrorDetails errorDetails);

  /// Log a message
  Future<void> log(String message);

  /// Set a custom key-value pair
  Future<void> setCustomKey(String key, dynamic value);

  /// Start a performance trace
  IPerformanceTrace? newTrace(String name);

  /// Clean up
  void dispose();

  /// Factory method to create the default analytics provider
  static IAnalyticsProvider createDefault() {
    const isMockMode = bool.fromEnvironment('MOCK_MODE', defaultValue: false);
    if (isMockMode) {
      return _NoOpAnalyticsProvider();
    }
    return _createFirebaseProvider();
  }

  /// Create Firebase provider
  static IAnalyticsProvider _createFirebaseProvider() {
    try {
      return FirebaseAnalyticsProvider();
    } catch (e) {
      debugPrint('Failed to create Firebase analytics provider: $e');
      return _NoOpAnalyticsProvider();
    }
  }
}

/// Simple performance trace interface
abstract class IPerformanceTrace {
  Future<void> start();
  Future<void> stop();
  void putAttribute(String name, String value);
  void setMetric(String name, int value);
  void incrementMetric(String name);
}

/// No-op implementation
class _NoOpAnalyticsProvider implements IAnalyticsProvider {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> recordError(exception, StackTrace? stack, {reason}) async {}

  @override
  Future<void> recordFlutterError(FlutterErrorDetails errorDetails) async {}

  @override
  Future<void> log(String message) async {}

  @override
  Future<void> setCustomKey(String key, value) async {}

  @override
  IPerformanceTrace? newTrace(String name) => null;

  @override
  void dispose() {}
}