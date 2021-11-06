import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity/connectivity.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/dataAccessLayer/db.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/remoteMessage.dart';
import 'package:vartalap/services/api_service.dart';
import 'package:vartalap/services/crashlystics.dart';
import 'package:vartalap/services/performance_metric.dart';
import 'package:vartalap/utils/remote_message_helper.dart';

class SocketService {
  static String name = "SocketService";
  static SocketService? _instance;

  Future<void>? _processingPromise;

  int _retryCount = 0;
  late String _url;
  bool _closed = false;
  bool _reconnecting = false;
  // ignore: cancel_subscriptions
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  StreamController<RemoteMessage> _controller =
      StreamController<RemoteMessage>.broadcast();
  // ignore: close_sinks
  WebSocket? _channel;
  Stream<RemoteMessage> get stream => _controller.stream.asBroadcastStream();

  Future<void> init() async {
    _url = ConfigStore().get("ws_url");

    await _connectWs();
  }

  Future<void> externalNewMessage(RemoteMessage msg) async {
    _controller.sink.add(msg);
    return _reconnectWs();
  }

  Future<void> send(RemoteMessage msg) async {
    var _sendMsgTrace = PerformanceMetric.newTrace('send-message');
    await _sendMsgTrace.start();

    var db = await DB().getDb();
    var msgMap = msg.toMap();
    var msgStr = json.encode(msgMap);
    var outMessage = {
      "messageId": msg.id,
      "message": msgStr,
      "sent": 0,
      "created_ts": DateTime.now().millisecondsSinceEpoch,
      "sent_ts": 0,
      "retry_count": 0
    };
    db.insert("out_message", outMessage);
    if (_channel == null || _channel!.closeCode != null) {
      await db.update("out_message", {"sent": -1},
          where: "messageId=?", whereArgs: [msg.id]);

      _sendMsgTrace.putAttribute('channelStatus', 'closed');
      _sendMsgTrace.stop();
      _reconnectWs();
      return;
    }
    try {
      _channel!.add(msgStr);
      await db.delete(
        "out_message",
        where: "messageId=?",
        whereArgs: [msg.id],
      );
      msg = RemoteMessage.fromMap(msgMap);
      msg.head.from = name;
      msg.head.contentType = MessageType.NOTIFICATION;
      msg.body = {"id": msg.id, "state": MessageState.SENT};
      _controller.sink.add(msg);
    } catch (e, stack) {
      await db.update("out_message", {"sent": -1},
          where: "messageId=?", whereArgs: [msg.id]);

      Crashlytics.recordError(e, stack,
          reason: "Error while sending message to socket");

      _sendMsgTrace.putAttribute('error', e.toString());
      _reconnectWs();
    } finally {
      _sendMsgTrace.stop();
    }
  }

  void dispose() {
    _closed = true;
    _controller.close();
    if (_channel != null) _channel!.close();
    if (_connectivitySub != null) _connectivitySub!.cancel();
  }

  Future<void> _connectWs() async {
    var _socketConnectionTrack = PerformanceMetric.newTrace('socket-connect');
    _socketConnectionTrack.putAttribute('retryCount', _retryCount.toString());
    await _socketConnectionTrack.start();
    try {
      _reconnecting = true;
      Map<String, String> headers = await ApiService.getAuthHeader();
      _channel = await WebSocket.connect(_url, headers: headers);
      _channel!.pingInterval = Duration(seconds: 30);
      _retryCount = 0;
      _channel!.asBroadcastStream().listen(_onNewMessage,
          onError: _onError, onDone: _onDone, cancelOnError: false);
      _channel!.done.then((value) => _reconnectWs());
      _socketConnectionTrack.stop();
      _processPendingMessage();
    } catch (e, stack) {
      Crashlytics.recordError(e, stack,
          reason: "Error while connecting to socket");

      _socketConnectionTrack.putAttribute('error', e.toString());
      _socketConnectionTrack.stop();
      await _reconnectWs();
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _reconnectWs({bool ignoreFlag = false}) async {
    if (!ignoreFlag && _reconnecting) return;
    if (_closed) return;
    var _connectivity = Connectivity();
    try {
      ConnectivityResult result = await _connectivity.checkConnectivity();
      if (result == ConnectivityResult.none) {
        if (_connectivitySub != null) return;

        _connectivitySub = _connectivity.onConnectivityChanged.listen((event) {
          _reconnectWs(ignoreFlag: true);
        });
        return;
      } else {
        if (_connectivitySub != null) {
          _connectivitySub!.cancel();
          _connectivitySub = null;
        }
      }
    } catch (e, stack) {
      Crashlytics.recordError(e, stack,
          reason: "Error while checking connectivity");
    }

    _retryCount++;
    await Future.delayed(Duration(milliseconds: (_retryCount * 500)));
    if (_closed) return;
    if (_reconnecting) return;
    _reconnecting = false;
    if (_channel == null || _channel!.closeCode != null) {
      await _connectWs();
    }
  }

  void _onDone() {
    if (_closed) return;
    _reconnectWs();
  }

  void _onError(error) {
    if (this._channel!.closeCode == null) {
      return;
    }
    _reconnectWs();
  }

  void _onNewMessage(event) {
    var messages = toRemoteMessage(event);
    for (var msg in messages) {
      _controller.sink.add(msg);
    }
  }

  void _processPendingMessage() async {
    var _pendingMessageTrack = PerformanceMetric.newTrace('pending-message');
    await _pendingMessageTrack.start();
    if (_processingPromise != null) {
      _pendingMessageTrack.putAttribute('alreadyRunning', 'true');
      await _processingPromise;
    }
    _processingPromise = Future<void>(() async {
      var db = await DB().getDb();
      var result = await db.query('out_message',
          columns: ["message"], where: 'sent=?', whereArgs: [-1]);

      var batch = db.batch();
      try {
        for (var row in result) {
          var _smsg =
              RemoteMessage.fromMap(json.decode(row["message"] as String));
          _channel!.add(row["message"]);
          _smsg.head.from = name;
          _smsg.head.contentType = MessageType.NOTIFICATION;
          _smsg.body = {"id": _smsg.id, "state": MessageState.SENT};
          _controller.sink.add(_smsg);
          batch.delete("out_message",
              where: "messageId=?", whereArgs: [_smsg.id]);
        }
      } catch (e, stack) {
        Crashlytics.recordError(e, stack,
            reason: "Exception while processing pending messages");
        _pendingMessageTrack.putAttribute('error', e.toString());
      } finally {
        await batch.commit();
        _pendingMessageTrack.stop();
      }
    });
  }

  static SocketService get instance {
    if (_instance == null) {
      _instance = SocketService();
    }
    return _instance!;
  }
}
