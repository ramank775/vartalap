import 'package:vartalap/services/analytics/ianalytics_provider.dart';

class PerformanceTrace {
  final IPerformanceTrace? _trace;
  PerformanceTrace(this._trace);

  Future<void> start() {
    return _trace?.start() ?? Future.value();
  }

  Future<void> stop() {
    return _trace?.stop() ?? Future.value();
  }

  void putAttribute(String name, dynamic value) {
    _trace?.putAttribute(name, value.toString());
  }

  void setMetric(String name, int value) {
    _trace?.setMetric(name, value);
  }

  void incrementMetric(String name) {
    _trace?.incrementMetric(name);
  }
}

class PerformanceMetric {
  static final IAnalyticsProvider _provider = IAnalyticsProvider.createDefault();

  static void init() {
    // Initialize provider lazily - it will set up Firebase when first used
    _provider.initialize();
  }

  static PerformanceTrace newTrace(String name) {
    final trace = _provider.newTrace(name);
    return PerformanceTrace(trace);
  }
}
