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

/// Helper class to categorize and convert exceptions to AppError
class ErrorMapper {
  static AppError mapException(dynamic error) {
    if (error is AppError) return error;

    final errorString = error.toString().toLowerCase();

    // Network-related errors
    if (errorString.contains('socket') ||
        errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('unreachable')) {
      if (errorString.contains('timeout')) {
        return TimeoutError(
          'Request timed out. Please check your internet connection and try again.',
          technicalDetails: error.toString(),
        );
      }
      return NetworkError(
        'Network connection failed. Please check your internet connection.',
        technicalDetails: error.toString(),
      );
    }

    // Authentication errors
    if (errorString.contains('auth') ||
        errorString.contains('unauthorized') ||
        errorString.contains('forbidden') ||
        errorString.contains('token')) {
      return AuthenticationError(
        'Authentication failed. Please log in again.',
        technicalDetails: error.toString(),
      );
    }

    // Permission errors
    if (errorString.contains('permission') ||
        errorString.contains('access denied')) {
      return PermissionError(
        'Permission denied. Please grant the required permissions.',
        technicalDetails: error.toString(),
      );
    }

    // Server errors (HTTP status codes)
    if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504')) {
      return ServerError(
        'Server is temporarily unavailable. Please try again later.',
        technicalDetails: error.toString(),
      );
    }

    // Database errors
    if (errorString.contains('database') ||
        errorString.contains('sql') ||
        errorString.contains('drift')) {
      return DatabaseError(
        'Database operation failed. Please restart the app.',
        technicalDetails: error.toString(),
      );
    }

    // Default to unknown error
    return UnknownError(
      'Something went wrong. Please try again.',
      technicalDetails: error.toString(),
    );
  }
}
