import 'dart:async';
import 'dart:io';

import 'package:vartalap_messaging/core/error/errors.dart';
import 'package:vartalap_messaging/core/http/token_manager.dart';
import 'package:vartalap_messaging/core/models/event.dart';
import 'package:vartalap_messaging/core/util/utils.dart';
import 'package:vartalap_messaging/core/ws/connection_status.dart';

class Websocket {
  Websocket({
    required this.url,
    required this.tokenManager,
    this.pingInterval = const Duration(seconds: 30),
  });

  final TokenManager tokenManager;
  final String url;
  final Duration pingInterval;

  StreamController<RemoteMessage> get _messageController =>
      StreamController<RemoteMessage>();
  StreamController<ConnectionStatus> get _connectionStatusController =>
      StreamController<ConnectionStatus>();
  Stream<ConnectionStatus> get connectionStatusStream =>
      _connectionStatusController.stream.distinct().asBroadcastStream();

  Stream<RemoteMessage> get messageStream => _messageController.stream;

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;

  ConnectionStatus get connectionStatus => _connectionStatus;

  set connectionStatus(ConnectionStatus status) {
    if (_connectionStatusController.isClosed) return;
    _connectionStatusController.sink.add(status);
    _connectionStatus = status;
  }

  WebSocket? _channel;
  bool _closed = false;

  void _onDone() {
    if (_closed) return;
    _channel = null;
    _connectWebSocket(force: true);
  }

  void _onError(error) {
    if (_channel!.closeCode == null) {
      return;
    }
    _channel = null;
    _connectWebSocket(force: true);
  }

  void _onNewMessage(event) {
    final rmsg = RemoteMessage.fromString(event);
    _messageController.sink.add(rmsg);
  }

  Future<void> _disconnectWebSocket() async {
    if (_channel == null) return;
    connectionStatus = ConnectionStatus.disconnected;
    if (_channel!.closeCode != null) {
      await _channel!.close(WebSocketStatus.normalClosure);
    }
    _channel = null;
  }

  Future<void> _connectWebSocket({bool force = false}) async {
    if (_channel != null && !force) {
      return;
    }
    await _disconnectWebSocket();
    final token = await tokenManager.fetchActiveToken();
    if (token == null) {
      return;
    }
    final headers = authHeader(token);
    connectionStatus = ConnectionStatus.connecting;
    await WebSocket.connect(url, headers: headers).then((channel) {
      channel.pingInterval = pingInterval;
      channel.listen(_onNewMessage, onDone: _onDone, onError: _onError);
      connectionStatus = ConnectionStatus.connected;
    });
  }

  Future<void> connect() async {
    return await _connectWebSocket();
  }

  Future<void> reconnect({bool force = false}) async {
    return await _connectWebSocket(force: force);
  }

  Future<void> send(RemoteMessage msg) async {
    if (connectionStatus == ConnectionStatus.connected) {
      _channel!.add(msg.toString());
      return;
    }
    throw const Error(
      "Websocket is not connect. Call connect() before sending message",
    );
  }

  void close() {
    _closed = true;
    _disconnectWebSocket();
    _connectionStatusController.sink.close();
    _connectionStatusController.close();
  }
}
