/// Firebase implementation of IAnalyticsProvider with lazy initialization
library;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'ianalytics_provider.dart';
import '../firebase_initializer.dart';

/// Firebase implementation with lazy initialization
class FirebaseAnalyticsProvider implements IAnalyticsProvider {
  /// Lazy getter for Crashlytics
  static Future<FirebaseCrashlytics> get _crashlytics async {
    await FirebaseInitializer.ensureInitialized();
    return FirebaseCrashlytics.instance;
  }


  @override
  Future<void> initialize() async {
    // Firebase will be initialized lazily when first needed
    debugPrint('📊 [PERF] FirebaseAnalyticsProvider.initialize() - deferred to first use');
  }

  @override
  Future<void> recordError(dynamic exception, StackTrace? stack, {dynamic reason}) async {
    try {
      final crashlytics = await _crashlytics;
      await crashlytics.recordError(
        exception,
        stack,
        reason: reason,
        printDetails: false,
      );
    } catch (e) {
      debugPrint('Failed to record error to Firebase: $e');
    }
  }

  @override
  Future<void> recordFlutterError(FlutterErrorDetails errorDetails) async {
    try {
      final crashlytics = await _crashlytics;
      await crashlytics.recordFlutterError(errorDetails);
    } catch (e) {
      debugPrint('Failed to record Flutter error to Firebase: $e');
    }
  }

  @override
  Future<void> log(String message) async {
    try {
      final crashlytics = await _crashlytics;
      await crashlytics.log(message);
    } catch (e) {
      debugPrint('Failed to log message to Firebase: $e');
    }
  }

  @override
  Future<void> setCustomKey(String key, dynamic value) async {
    try {
      final crashlytics = await _crashlytics;
      await crashlytics.setCustomKey(key, value);
    } catch (e) {
      debugPrint('Failed to set custom key in Firebase: $e');
    }
  }

  @override
  IPerformanceTrace? newTrace(String name) {
    // Return a lazy trace that will initialize Firebase when started
    return _FirebasePerformanceTrace(name);
  }

  @override
  void dispose() {
    // Firebase cleanup is handled by the framework
  }
}

/// Firebase performance trace with lazy initialization
class _FirebasePerformanceTrace implements IPerformanceTrace {
  final String _name;
  Trace? _trace;

  _FirebasePerformanceTrace(this._name);

  Future<Trace> get _lazyTrace async {
    if (_trace != null) return _trace!;
    await FirebaseInitializer.ensureInitialized();
    final performance = FirebasePerformance.instance;
    _trace = performance.newTrace(_name);
    return _trace!;
  }

  @override
  Future<void> start() async {
    try {
      final trace = await _lazyTrace;
      await trace.start();
    } catch (e) {
      debugPrint('Failed to start Firebase trace: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      final trace = await _lazyTrace;
      await trace.stop();
    } catch (e) {
      debugPrint('Failed to stop Firebase trace: $e');
    }
  }

  @override
  void putAttribute(String name, String value) {
    // Defer attribute setting until trace is started
    _lazyTrace.then((trace) {
      try {
        trace.putAttribute(name, value);
      } catch (e) {
        debugPrint('Failed to set trace attribute: $e');
      }
    });
  }

  @override
  void setMetric(String name, int value) {
    _lazyTrace.then((trace) {
      try {
        trace.setMetric(name, value);
      } catch (e) {
        debugPrint('Failed to set trace metric: $e');
      }
    });
  }

  @override
  void incrementMetric(String name) {
    _lazyTrace.then((trace) {
      try {
        trace.incrementMetric(name, 1);
      } catch (e) {
        debugPrint('Failed to increment trace metric: $e');
      }
    });
  }
}