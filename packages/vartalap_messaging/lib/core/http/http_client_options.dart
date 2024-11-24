part of 'http_client.dart';

class HttpClientOptions {
  const HttpClientOptions({
    required this.baseUrl,
    required this.userAgent,
    this.connectTimeout = const Duration(seconds: 60),
    this.receiveTimeout = const Duration(seconds: 60),
  });

  final String baseUrl;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final String userAgent;
}
