import 'package:flutter/material.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap/utils/error_types.dart';
import 'package:vartalap/widgets/error_widgets.dart';
import 'package:vartalap/services/connectivity_service.dart';

/// Enhanced client provider with error handling and connection monitoring
class VartalapClientProvider extends InheritedWidget {
  const VartalapClientProvider({
    super.key,
    required this.client,
    required this.connectionState,
    required super.child,
  });

  final VartalapChatClientFlutter client;
  final ClientConnectionState connectionState;

  static VartalapClientProvider of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<VartalapClientProvider>();

    if (provider == null) {
      throw const UnknownError(
        'VartalapClientProvider not found in widget tree',
        technicalDetails:
            'Make sure VartalapClientProvider is an ancestor of this widget',
      );
    }

    return provider;
  }

  /// Safely get client with error handling
  static VartalapChatClientFlutter? tryGetClient(BuildContext context) {
    try {
      return of(context).client;
    } catch (e) {
      debugPrint('Failed to get client: $e');
      return null;
    }
  }

  @override
  bool updateShouldNotify(VartalapClientProvider oldWidget) {
    return client != oldWidget.client ||
        connectionState != oldWidget.connectionState;
  }
}

/// Connection state for the client
enum ClientConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Stateful wrapper that manages client lifecycle and error states
class VartalapClientManager extends StatefulWidget {
  final VartalapChatClientFlutter client;
  final Widget child;
  final Widget Function(AppError error, VoidCallback onRetry)? errorBuilder;
  final Widget Function()? loadingBuilder;

  const VartalapClientManager({
    super.key,
    required this.client,
    required this.child,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  State<VartalapClientManager> createState() => _VartalapClientManagerState();
}

class _VartalapClientManagerState extends State<VartalapClientManager>
    with ErrorHandlingMixin {
  ClientConnectionState _connectionState = ClientConnectionState.disconnected;
  AppError? _connectionError;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initializeClient();
    _setupConnectivityListener();
  }

  void _setupConnectivityListener() {
    ConnectivityService().connectivityStream.listen((isConnected) {
      if (!isConnected && _connectionState == ClientConnectionState.connected) {
        setState(() {
          _connectionState = ClientConnectionState.disconnected;
          _connectionError = const NetworkError(
            'Lost internet connection. Reconnecting when available...',
          );
        });
      } else if (isConnected &&
          _connectionState == ClientConnectionState.disconnected) {
        _reconnectClient();
      }
    });
  }

  Future<void> _initializeClient() async {
    setState(() {
      _connectionState = ClientConnectionState.connecting;
      _connectionError = null;
      _isInitializing = true;
    });

    try {
      await RetryMechanism.withRetry(
        () async {
          await widget.client.init().timeout(
                const Duration(seconds: 30),
                onTimeout: () => throw TimeoutError(
                  'Client initialization timed out. Please check your connection.',
                ),
              );
        },
        maxRetries: 3,
      );

      setState(() {
        _connectionState = ClientConnectionState.connected;
        _connectionError = null;
        _isInitializing = false;
      });
    } catch (e) {
      // Check if this is a login-related error
      if (e.toString().contains('No user is currently logged in')) {
        debugPrint('User not logged in to chat service - auth state will handle navigation');
        // Don't show error page, just set to disconnected state
        // The Consumer<VartalapAuthenticatedClient> in main.dart will handle navigation
        setState(() {
          _connectionState = ClientConnectionState.disconnected;
          _connectionError = null;
          _isInitializing = false;
        });
        return;
      }

      final error = ErrorMapper.mapException(e);
      debugPrint('VartalapClientManager initialization error: $e');
      debugPrint('Mapped error: ${error.userFriendlyMessage}');
      setState(() {
        _connectionState = ClientConnectionState.error;
        _connectionError = error;
        _isInitializing = false;
      });
    }
  }

  Future<void> _reconnectClient() async {
    if (_connectionState == ClientConnectionState.reconnecting) return;

    setState(() {
      _connectionState = ClientConnectionState.reconnecting;
      _connectionError = null;
    });

    try {
      await RetryMechanism.withRetry(
        () async {
          // Re-initialize the client for reconnection
          await widget.client.init().timeout(
                const Duration(seconds: 20),
                onTimeout: () => throw TimeoutError(
                  'Reconnection timed out. Please try again.',
                ),
              );
        },
        maxRetries: 2,
      );

      setState(() {
        _connectionState = ClientConnectionState.connected;
        _connectionError = null;
      });
    } catch (e) {
      // Check if this is a login-related error during reconnection
      if (e.toString().contains('No user is currently logged in')) {
        debugPrint('User not logged in during reconnection - auth state will handle navigation');
        // Don't show error page, just set to disconnected state
        setState(() {
          _connectionState = ClientConnectionState.disconnected;
          _connectionError = null;
        });
        return;
      }

      final error = ErrorMapper.mapException(e);
      debugPrint('VartalapClientManager reconnection error: $e');
      debugPrint('Mapped reconnection error: ${error.userFriendlyMessage}');
      setState(() {
        _connectionState = ClientConnectionState.error;
        _connectionError = error;
      });
    }
  }

  void _handleRetry() {
    if (_connectionState == ClientConnectionState.error) {
      if (ConnectivityService().isConnected) {
        _initializeClient();
      } else {
        showErrorSnackBar(
          const NetworkError(
              'No internet connection. Please connect and try again.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading state during initialization
    if (_isInitializing &&
        _connectionState == ClientConnectionState.connecting) {
      return widget.loadingBuilder?.call() ?? _buildDefaultLoading();
    }

    // Show error state if there's a connection error
    if (_connectionError != null &&
        _connectionState == ClientConnectionState.error) {
      return widget.errorBuilder?.call(_connectionError!, _handleRetry) ??
          _buildDefaultError(_connectionError!, _handleRetry);
    }

    // Provide client to children
    return VartalapClientProvider(
      client: widget.client,
      connectionState: _connectionState,
      child: Column(
        children: [
          // Show connection status indicator
          _buildConnectionIndicator(),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator() {
    if (_connectionState == ClientConnectionState.reconnecting) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        color: Colors.orange.shade600,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Reconnecting...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildDefaultLoading() {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.white,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Initializing client...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultError(AppError error, VoidCallback onRetry) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.white,
        child: ErrorStateWidget(
          error: error,
          onRetry: onRetry,
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Client doesn't have explicit dispose method,
    // but we can clean up our resources
    super.dispose();
  }
}

/// Extension to provide safe client access with fallback
extension SafeClientAccess on BuildContext {
  /// Safely get the client with error handling
  VartalapChatClientFlutter? get safeClient {
    return VartalapClientProvider.tryGetClient(this);
  }

  /// Get client connection state
  ClientConnectionState get clientConnectionState {
    try {
      return VartalapClientProvider.of(this).connectionState;
    } catch (e) {
      return ClientConnectionState.error;
    }
  }

  /// Check if client is connected and ready
  bool get isClientReady {
    return clientConnectionState == ClientConnectionState.connected;
  }
}
