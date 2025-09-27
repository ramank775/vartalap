import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Connectivity service to monitor network status
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  // Current connectivity status
  bool _isConnected = true;
  bool get isConnected => _isConnected;
  
  // Stream for connectivity changes
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  Stream<bool> get connectivityStream => _connectivityController.stream;

  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    try {
      // Check initial connectivity status
      final connectivityResults = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(connectivityResults);
      
      // Listen for connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _updateConnectivityStatus,
        onError: (error) {
          debugPrint('Connectivity monitoring error: $error');
        },
      );
    } catch (e) {
      debugPrint('Failed to initialize connectivity service: $e');
      // Assume connected if we can't check
      _isConnected = true;
    }
  }

  /// Update connectivity status and notify listeners
  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    final wasConnected = _isConnected;
    _isConnected = results.any((result) => 
      result == ConnectivityResult.mobile || 
      result == ConnectivityResult.wifi ||
      result == ConnectivityResult.ethernet ||
      result == ConnectivityResult.vpn
    );
    
    if (wasConnected != _isConnected) {
      _connectivityController.add(_isConnected);
      debugPrint('Connectivity changed: ${_isConnected ? "Connected" : "Disconnected"}');
    }
  }

  /// Dispose of resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityController.close();
  }
}