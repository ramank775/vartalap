import 'package:dio/dio.dart';
import 'package:vartalap_messaging/core/error/error.dart';
import 'package:vartalap_messaging/core/http/token_manager.dart';
import 'package:vartalap_messaging/core/util/utils.dart';

class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._tokenManager);
  final TokenManager _tokenManager;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenManager.fetchActiveToken();
    if (token == null) {
      final error = NetworkError(ErrorCode.undefinedToken);
      final dioError = DioError(requestOptions: options, error: error);
      return handler.reject(dioError);
    }
    final headers = authHeader(token);
    options.headers.addAll(headers);
    return handler.next(options);
  }
}
