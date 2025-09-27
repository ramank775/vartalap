import 'package:flutter/material.dart';
import 'package:vartalap/utils/error_types.dart';
import 'package:vartalap/services/connectivity_service.dart';

/// Widget to display error states with retry functionality
class ErrorStateWidget extends StatelessWidget {
  final AppError error;
  final VoidCallback? onRetry;
  final String? customMessage;
  final Widget? customIcon;

  const ErrorStateWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.customMessage,
    this.customIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            customIcon ?? _getErrorIcon(),
            const SizedBox(height: 16),
            Text(
              customMessage ?? error.userFriendlyMessage,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (error.isRetryable && onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _getErrorIcon() {
    switch (error.runtimeType) {
      case NetworkError _:
      case TimeoutError _:
        return const Icon(Icons.wifi_off, size: 64, color: Colors.orange);
      case AuthenticationError _:
        return const Icon(Icons.lock_outline, size: 64, color: Colors.red);
      case PermissionError _:
        return const Icon(Icons.security, size: 64, color: Colors.amber);
      case ServerError _:
        return const Icon(Icons.cloud_off, size: 64, color: Colors.red);
      case DatabaseError _:
        return const Icon(Icons.storage, size: 64, color: Colors.purple);
      default:
        return const Icon(Icons.error_outline, size: 64, color: Colors.grey);
    }
  }
}

/// Widget to show offline indicator
class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectivityService().connectivityStream,
      initialData: ConnectivityService().isConnected,
      builder: (context, snapshot) {
        final isConnected = snapshot.data ?? true;

        if (isConnected) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: Colors.red.shade600,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                'No internet connection',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Enhanced loading indicator with timeout
class EnhancedLoadingIndicator extends StatefulWidget {
  final String text;
  final Duration? timeout;
  final VoidCallback? onTimeout;

  const EnhancedLoadingIndicator({
    super.key,
    required this.text,
    this.timeout,
    this.onTimeout,
  });

  @override
  State<EnhancedLoadingIndicator> createState() =>
      _EnhancedLoadingIndicatorState();
}

class _EnhancedLoadingIndicatorState extends State<EnhancedLoadingIndicator> {
  bool _isTimedOut = false;

  @override
  void initState() {
    super.initState();
    if (widget.timeout != null) {
      Future.delayed(widget.timeout!, () {
        if (mounted) {
          setState(() {
            _isTimedOut = true;
          });
          widget.onTimeout?.call();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isTimedOut) {
      return ErrorStateWidget(
        error: const TimeoutError('Operation timed out'),
        onRetry: () {
          setState(() {
            _isTimedOut = false;
          });
        },
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            widget.text,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Retry mechanism with exponential backoff
class RetryMechanism {
  static Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    double backoffMultiplier = 2.0,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempt++;

        if (attempt >= maxRetries) {
          rethrow;
        }

        final mappedError = ErrorMapper.mapException(e);
        if (!mappedError.isRetryable) {
          rethrow;
        }

        await Future.delayed(delay);
        delay = Duration(
            milliseconds: (delay.inMilliseconds * backoffMultiplier).round());
      }
    }

    throw UnknownError('Max retries exceeded');
  }
}

/// Mixin to add error handling capabilities to StatefulWidgets
mixin ErrorHandlingMixin<T extends StatefulWidget> on State<T> {
  /// Show error dialog with retry option
  void showErrorDialog(AppError error, {VoidCallback? onRetry}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ErrorStateWidget(
              error: error,
              onRetry: onRetry != null
                  ? () {
                      Navigator.of(context).pop();
                      onRetry();
                    }
                  : null,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Show error snackbar
  void showErrorSnackBar(AppError error, {VoidCallback? onRetry}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.userFriendlyMessage),
        backgroundColor: Colors.red.shade600,
        action: error.isRetryable && onRetry != null
            ? SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Execute operation with error handling
  Future<void> executeWithErrorHandling(
    Future<void> Function() operation, {
    String? loadingMessage,
    bool showLoadingDialog = false,
    VoidCallback? onSuccess,
    Function(AppError)? onError,
  }) async {
    try {
      if (showLoadingDialog && loadingMessage != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
              content: EnhancedLoadingIndicator(text: loadingMessage),
            ),
          ),
        );
      }

      await operation();

      if (showLoadingDialog && mounted) {
        Navigator.of(context).pop();
      }

      onSuccess?.call();
    } catch (e) {
      if (showLoadingDialog && mounted) {
        Navigator.of(context).pop();
      }

      final error = ErrorMapper.mapException(e);

      if (onError != null) {
        onError(error);
      } else {
        showErrorSnackBar(error,
            onRetry: error.isRetryable
                ? () => executeWithErrorHandling(operation)
                : null);
      }
    }
  }
}
