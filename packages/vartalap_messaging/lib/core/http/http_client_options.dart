part of 'http_client.dart';

const _defaultBaseURL = "https://vartalapapp.one9x.com";
const _defaultUserAgent = "vartalap-messaging-dart-client";

class HttpClientOptions {
  const HttpClientOptions({
    String? baseUrl,
    this.connectTimeout = const Duration(seconds: 60),
    this.receiveTimeout = const Duration(seconds: 60),
    this.userAgent = _defaultUserAgent,
  }) : baseUrl = baseUrl ?? _defaultBaseURL;

  final String baseUrl;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final String userAgent;
}
