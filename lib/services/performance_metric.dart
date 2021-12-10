import 'package:firebase_performance/firebase_performance.dart';
import 'package:vartalap/utils/enum_helper.dart';

class PerformanceTrace {
  final Trace _trace;
  PerformanceTrace(this._trace);

  Future<void> start() {
    return _trace.start();
  }

  Future<void> stop() {
    return _trace.stop();
  }

  void putAttribute(String name, dynamic value) {
    return _trace.putAttribute(name, value.toString());
  }

  void setMetric(String name, int value) {
    return _trace.setMetric(name, value);
  }

  void incrementMetric(String name) {
    return _trace.incrementMetric(name, 1);
  }
}

class HttpPerformanceTrace {
  final HttpMetric _metric;

  HttpPerformanceTrace(this._metric);

  Future<void> start() {
    return _metric.start();
  }

  Future<void> stop() {
    return _metric.stop();
  }

  int get httpResponseCode => _metric.httpResponseCode!;

  int get requestPayloadSize => _metric.requestPayloadSize ?? 0;

  String get responseContentType => _metric.responseContentType ?? '';

  int get responsePayloadSize => _metric.responsePayloadSize ?? 0;

  set httpResponseCode(int httpResponseCode) {
    _metric.httpResponseCode = httpResponseCode;
  }

  set requestPayloadSize(int requestPayloadSize) {
    _metric.requestPayloadSize = requestPayloadSize;
  }

  set responseContentType(String responseContentType) {
    _metric.responseContentType = responseContentType;
  }

  set responsePayloadSize(int responsePayloadSize) {
    _metric.responsePayloadSize = responsePayloadSize;
  }
}

class PerformanceMetric {
  static FirebasePerformance _firebasePerformance =
      FirebasePerformance.instance;

  static init() {
    _firebasePerformance.setPerformanceCollectionEnabled(true);
  }

  static PerformanceTrace newTrace(String name) {
    return PerformanceTrace(_firebasePerformance.newTrace(name));
  }

  static HttpPerformanceTrace newHttpMetric(String url, String method) {
    var httpMethod = stringToEnum(method, HttpMethod.values);
    return HttpPerformanceTrace(
        _firebasePerformance.newHttpMetric(url, httpMethod));
  }
}
