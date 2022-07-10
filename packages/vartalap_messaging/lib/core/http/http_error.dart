import 'package:dio/dio.dart';
import 'package:vartalap_messaging/core/error/error.dart';

class HttpError extends DioError {
  HttpError({
    required this.error,
    required super.requestOptions,
    super.response,
    super.type,
  }) : super(
          error: error,
        );

  @override
  // ignore: overridden_fields
  final NetworkError error;
}
