// Stub: Firebase removed per V3_ARCHITECTURE.md decision 1. Replacement pending v3 auth/push/crash work.
import 'package:flutter/foundation.dart';

class Crashlytics {
  static init() {}

  static Future<void> recordError(
    dynamic exception,
    StackTrace stack, {
    dynamic reason,
    Iterable<DiagnosticsNode> information = const [],
  }) async {
    return Future.value();
  }

  static Future<void> recordFlutterError(
      FlutterErrorDetails flutterErrorDetails) {
    return Future.value();
  }

  static Future<void> log(String message) async {
    return Future.value();
  }

  /// The value can only be a type [int], [num], [String] or [bool].
  static Future<void> setCustomKey(String key, dynamic value) async {
    return Future.value();
  }
}
