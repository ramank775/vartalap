import 'dart:async';
import 'dart:io';

/// Comprehensive error types for the application
abstract class AppError implements Exception {
  final String message;
  final String? technicalDetails;
  final bool isRetryable;

  const AppError(this.message,
      {this.technicalDetails, this.isRetryable = false});

  String get userFriendlyMessage => message;
  String get debugInfo => technicalDetails ?? message;
}

/// Network-related errors
class NetworkError extends AppError {
  const NetworkError(
    super.message, {
    super.technicalDetails,
    super.isRetryable = true,
  });
}

/// Authentication-related errors
class AuthenticationError extends AppError {
  const AuthenticationError(
    super.message, {
    super.technicalDetails,
    super.isRetryable,
  });
}

/// Permission-related errors
class PermissionError extends AppError {
  const PermissionError(
    super.message, {
    super.technicalDetails,
    super.isRetryable,
  });
}

/// Server-related errors
class ServerError extends AppError {
  final int? statusCode;

  const ServerError(
    super.message, {
    this.statusCode,
    super.technicalDetails,
    super.isRetryable = true,
  });
}

/// Database-related errors
class DatabaseError extends AppError {
  const DatabaseError(
    super.message, {
    super.technicalDetails,
    super.isRetryable,
  });
}

/// Validation errors
class ValidationError extends AppError {
  const ValidationError(
    super.message, {
    super.technicalDetails,
    super.isRetryable,
  });
}

/// Timeout errors
class TimeoutError extends AppError {
  const TimeoutError(
    super.message, {
    super.technicalDetails,
    super.isRetryable = true,
  });
}

/// Unknown/unexpected errors
class UnknownError extends AppError {
  const UnknownError(
    super.message, {
    super.technicalDetails,
    super.isRetryable,
  });
}

/// Helper to convert exceptions to AppError using type checks
class ErrorMapper {
  static AppError mapException(dynamic error) {
    if (error is AppError) return error;

    if (error is TimeoutException) {
      return TimeoutError(
        'Request timed out. Please check your connection and try again.',
        technicalDetails: error.toString(),
      );
    }

    if (error is SocketException) {
      return NetworkError(
        'Network connection failed. Please check your internet connection.',
        technicalDetails: error.toString(),
      );
    }

    return UnknownError(
      'Something went wrong. Please try again.',
      technicalDetails: error.toString(),
    );
  }
}
