import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
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
  String? _url;
  bool _closed = false;
  bool _reconnecting = false;
  // ignore: cancel_subscriptions
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  StreamController<RemoteMessage> _controller =
      StreamController<RemoteMessage>.broadcast();
  // ignore: close_sinks
  WebSocket? _channel;
  Stream<RemoteMessage> get stream => _controller.stream.asBroadcastStream();

  String get url {
    if (_url == null) {
      _url = ConfigStore().get("ws_url");
    }
    return _url!;
  }

  Future<void> init() async {
    _url = ConfigStore().get("ws_url");
    await _connectWs();
  }

  Future<void> externalNewMessage(RemoteMessage msg) async {
    _controller.sink.add(msg);
    return _reconnectWs();
  }

  Future<void> send(RemoteMessage msg) async {
    final _sendMsgTrace = PerformanceMetric.newTrace('send-message');
    await _sendMsgTrace.start();

    final db = await DB().getDb();
    final msgMap = msg.toMap();
    final msgStr = json.encode(msgMap);
    final outMessage = {
      "messageId": msg.id,
      "message": msgStr,
      "sent": -1,
      "created_ts": DateTime.now().millisecondsSinceEpoch,
      "sent_ts": 0,
      "retry_count": 0,
    };
    if (_channel == null || _channel!.closeCode != null) {
      await db.insert("out_message", outMessage);
      _sendMsgTrace.putAttribute('channelStatus', 'closed');
      _sendMsgTrace.stop();
      _reconnectWs();
      return;
    }
    try {
      _channel!.add(msgStr);
      final ackmsg = _sendMessageAck(msg);
      _controller.sink.add(ackmsg);
    } catch (e, stack) {
      await db.insert("out_message", outMessage);
      Crashlytics.recordError(e, stack,
          reason: "Error while sending message to socket");

      _sendMsgTrace.putAttribute('error', e.toString());
      _reconnectWs();
    } finally {
      _sendMsgTrace.stop();
    }
  }

  Future<void> sendNotifications(Iterable<RemoteMessage> msgs) async {
    final trace = PerformanceMetric.newTrace('send-notification-message');
    await trace.start();

    final db = await DB().getDb();
    final outMsgs = msgs.map((msg) {
      final msgStr = json.encode(msg.toMap());
      return {
        "messageId": msg.id,
        "message": msgStr,
        "sent": -1,
        "created_ts": DateTime.now().millisecondsSinceEpoch,
        "sent_ts": 0,
        "retry_count": 0,
      };
    });

    if (_channel == null || _channel!.closeCode != null) {
      final batch = db.batch();
      outMsgs.forEach((outMessage) {
        batch.insert("out_message", outMessage);
      });
      await batch.commit();
      trace.putAttribute('channelStatus', 'closed');
      trace.stop();
      _reconnectWs();
      return;
    }
    List<String> sent = [];
    try {
      outMsgs.forEach((msg) {
        _channel!.add(msg["message"]);
        sent.add(msg["messageId"] as String);
      });
    } catch (e, stack) {
      final batch = db.batch();
      outMsgs.forEach((outMessage) {
        if (sent.contains(outMessage["messageId"])) {
          return;
        }
        batch.insert("out_message", outMessage);
      });
      await batch.commit();
      Crashlytics.recordError(e, stack,
          reason: "Error while sending message to socket");

      trace.putAttribute('error', e.toString());
      _reconnectWs();
    } finally {
      trace.stop();
    }
  }

  RemoteMessage _sendMessageAck(RemoteMessage msg) {
    final stateMsg = StateMessge(msg.head.chatid!, name, MessageState.SENT);
    stateMsg.msgIds.add(msg.id);
    msg = RemoteMessage.fromMessage(stateMsg, msg.head.from, msg.head.type);
    return msg;
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
      _channel = await WebSocket.connect(url, headers: headers);
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
      final db = await DB().getDb();
      final result = await db.query(
        'out_message',
        columns: ["message"],
        where: 'sent=?',
        whereArgs: [-1],
      );

      final batch = db.batch();
      try {
        for (final row in result) {
          _channel!.add(row["message"]);
          final _smsg = RemoteMessage.fromMap(
            json.decode(row["message"] as String),
            ignoreError: true,
          );
          final _ackmsg = _sendMessageAck(_smsg);
          _controller.sink.add(_ackmsg);
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
    unawaited(_processingPromise!);
  }

  static SocketService get instance {
    if (_instance == null) {
      _instance = SocketService();
    }
    return _instance!;
  }
}
