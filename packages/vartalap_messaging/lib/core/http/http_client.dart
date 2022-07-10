import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:vartalap_messaging/core/error/error.dart';
import 'package:vartalap_messaging/core/http/http_error.dart';
import 'package:vartalap_messaging/core/http/interceptors/auth_interceptor.dart';
import 'package:vartalap_messaging/core/http/token_manager.dart';
import 'package:vartalap_messaging/version.dart';

part 'http_client_options.dart';

class HttpClient {
  HttpClient({
    TokenManager? tokenManager,
    Dio? dio,
    HttpClientOptions? options,
    this.apiKey = "<api-key>",
  })  : _options = options ?? const HttpClientOptions(),
        httpClient = dio ?? Dio() {
    httpClient
      ..options.baseUrl = _options.baseUrl
      ..options.receiveTimeout = _options.receiveTimeout.inMilliseconds
      ..options.connectTimeout = _options.connectTimeout.inMilliseconds
      ..options.headers = {
        'Content-Type': 'application/json',
        'X-Client-AGENT': '${_options.userAgent}:$PACKAGE_VERSION',
      }
      ..interceptors.addAll([
        if (tokenManager != null) AuthInterceptor(tokenManager),
      ]);
  }

  final String apiKey;
  final HttpClientOptions _options;
  final Dio httpClient;

  void close({bool force = false}) => httpClient.close(force: force);

  NetworkError _parseError(DioError err) {
    NetworkError error;
    // locally thrown dio error
    if (err is HttpError) {
      error = err.error;
    } else {
      // real network request dio error
      error = NetworkError.fromDioError(err);
    }
    return error..stackTrace = err.stackTrace;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, Object?>? queryParams,
    Map<String, Object?>? headers,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await httpClient.get<T>(
        path,
        queryParameters: queryParams,
        options: Options(headers: headers),
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
      );
      return response;
    } on DioError catch (error) {
      throw _parseError(error);
    }
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, Object?>? queryParams,
    Map<String, Object?>? headers,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await httpClient.post<T>(
        path,
        data: data,
        queryParameters: queryParams,
        options: Options(headers: headers),
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      return response;
    } on DioError catch (error) {
      throw _parseError(error);
    }
  }

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, Object?>? queryParams,
    Map<String, Object?>? headers,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await httpClient.put<T>(
        path,
        data: data,
        queryParameters: queryParams,
        options: Options(headers: headers),
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      return response;
    } on DioError catch (error) {
      throw _parseError(error);
    }
  }

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, Object?>? queryParams,
    Map<String, Object?>? headers,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await httpClient.delete<T>(
        path,
        data: data,
        queryParameters: queryParams,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );
      return response;
    } on DioError catch (error) {
      throw _parseError(error);
    }
  }

  Future<Response<T>> uploadFile<T>(
    String path,
    File file, {
    Map<String, Object?>? queryParams,
    Map<String, Object?>? headers,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    headers ??= <String, Object?>{};
    final len = await file.length();
    headers[Headers.contentLengthHeader] = len;
    final response = await put<T>(
      path,
      data: file.openRead(),
      queryParams: queryParams,
      headers: headers,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    return response;
  }

  Future<Response<dynamic>> downloadFile<T>(
    String urlPath,
    String localPath, {
    Map<String, Object?>? queryParams,
    Map<String, Object?>? headers,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await httpClient.download(
        urlPath,
        localPath,
        queryParameters: queryParams,
        options: Options(headers: headers),
        deleteOnError: true,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
      );
      return response;
    } on DioError catch (error) {
      throw _parseError(error);
    }
  }
}
