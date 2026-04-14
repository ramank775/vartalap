// Stub: Firebase removed per V3_ARCHITECTURE.md decision 1. Replacement pending v3 auth/push/crash work.

class PerformanceTrace {
  PerformanceTrace();

  Future<void> start() {
    return Future.value();
  }

  Future<void> stop() {
    return Future.value();
  }

  void putAttribute(String name, dynamic value) {}

  void setMetric(String name, int value) {}

  void incrementMetric(String name) {}
}

class HttpPerformanceTrace {
  int _httpResponseCode = 0;
  int _requestPayloadSize = 0;
  String _responseContentType = '';
  int _responsePayloadSize = 0;

  HttpPerformanceTrace();

  Future<void> start() {
    return Future.value();
  }

  Future<void> stop() {
    return Future.value();
  }

  int get httpResponseCode => _httpResponseCode;

  int get requestPayloadSize => _requestPayloadSize;

  String get responseContentType => _responseContentType;

  int get responsePayloadSize => _responsePayloadSize;

  set httpResponseCode(int httpResponseCode) {
    _httpResponseCode = httpResponseCode;
  }

  set requestPayloadSize(int requestPayloadSize) {
    _requestPayloadSize = requestPayloadSize;
  }

  set responseContentType(String responseContentType) {
    _responseContentType = responseContentType;
  }

  set responsePayloadSize(int responsePayloadSize) {
    _responsePayloadSize = responsePayloadSize;
  }
}

class PerformanceMetric {
  static init() {}

  static PerformanceTrace newTrace(String name) {
    return PerformanceTrace();
  }

  static HttpPerformanceTrace newHttpMetric(String url, String method) {
    return HttpPerformanceTrace();
  }
}
