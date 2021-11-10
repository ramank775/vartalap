import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';

class Crashlytics {
  static FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  static init() {
    _crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
    Function? originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails errorDetails) async {
      await FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
      // Forward to original handler.
      originalOnError!(errorDetails);
    };
  }

  static Future<void> recordError(
    dynamic exception,
    StackTrace stack, {
    dynamic reason,
    Iterable<DiagnosticsNode> information = const [],
  }) async {
    return _crashlytics.recordError(exception, stack,
        reason: reason, information: information, printDetails: false);
  }

  static Future<void> recordFlutterError(
      FlutterErrorDetails flutterErrorDetails) {
    return _crashlytics.recordFlutterError(flutterErrorDetails);
  }

  static Future<void> log(String message) async {
    return _crashlytics.log(message);
  }

  /// The value can only be a type [int], [num], [String] or [bool].
  static Future<void> setCustomKey(String key, dynamic value) async {
    return _crashlytics.setCustomKey(key, value);
  }
}
