import 'package:flutter/foundation.dart';
import 'package:vartalap/services/analytics/ianalytics_provider.dart';

class Crashlytics {
  static final IAnalyticsProvider _provider = IAnalyticsProvider.createDefault();

  static void init() {
    // Initialize provider lazily - it will set up Firebase when first used
    _provider.initialize();

    // Set up global error handling
    Function? originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails errorDetails) async {
      await _provider.recordFlutterError(errorDetails);
      // Forward to original handler
      originalOnError?.call(errorDetails);
    };
  }

  static Future<void> recordError(
    dynamic exception,
    StackTrace stack, {
    dynamic reason,
    Iterable<DiagnosticsNode> information = const [],
  }) async {
    return _provider.recordError(exception, stack, reason: reason);
  }

  static Future<void> recordFlutterError(
      FlutterErrorDetails flutterErrorDetails) {
    return _provider.recordFlutterError(flutterErrorDetails);
  }

  static Future<void> log(String message) async {
    return _provider.log(message);
  }

  /// The value can only be a type [int], [num], [String] or [bool].
  static Future<void> setCustomKey(String key, dynamic value) async {
    return _provider.setCustomKey(key, value);
  }
}
