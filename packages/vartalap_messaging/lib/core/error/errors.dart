import 'package:dio/dio.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/error/error_code.dart';

class Error implements Exception {
  const Error(this.message);

  final String message;

  @override
  String toString() => 'Error(message: $message)';
}

class NetworkError extends Error {
  NetworkError(
    ErrorCode errorCode, {
    this.statusCode,
    this.data,
  })  : code = errorCode.code,
        super(errorCode.message);

  NetworkError.raw({
    required this.code,
    required String message,
    this.statusCode,
    this.data,
  }) : super(message);

  ///
  factory NetworkError.fromDioError(DioError error) {
    final response = error.response;
    ErrorResponse? errorResponse;
    final data = response?.data;
    if (data != null) {
      errorResponse = ErrorResponse.fromJson(data);
    }
    return NetworkError.raw(
      code: errorResponse?.code ?? -1,
      message:
          errorResponse?.message ?? response?.statusMessage ?? error.message,
      statusCode: errorResponse?.statusCode ?? response?.statusCode,
      data: errorResponse,
    )..stackTrace = error.stackTrace;
  }

  // Error Code
  final int code;

  // Http Status Code
  final int? statusCode;

  final dynamic data;

  StackTrace? _stackTrace;

  set stackTrace(StackTrace? stack) => _stackTrace = stack;

  ErrorCode? get errorCode => errorCodeFromCode(code);

  @override
  String toString({bool printStackTrace = false}) {
    var params = 'code: $code, message: $message';
    if (statusCode != null) params += ', statusCode: $statusCode';
    if (data != null) params += ', data: $data';
    var msg = 'NetworkError($params)';

    if (printStackTrace && _stackTrace != null) {
      msg += '\n$_stackTrace';
    }
    return msg;
  }
}
