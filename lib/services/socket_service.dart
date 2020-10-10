import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity/connectivity.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/dataAccessLayer/db.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/socketMessage.dart';
import 'package:vartalap/services/api_service.dart';

class SocketService {
  static String name = "SocketService";
  static SocketService _instance;

  Future<void> _processingPromise;

  int _retryCount = 0;
  String _url;
  bool _closed = false;
  bool _reconnecting = false;
  StreamSubscription<ConnectivityResult> _connectivitySub;
  StreamController<SocketMessage> _controller =
      StreamController<SocketMessage>.broadcast();
  WebSocket _channel;
  Stream<SocketMessage> get stream => _controller.stream.asBroadcastStream();

  Future<void> init() async {
    _url = ConfigStore().get("ws_url");
    await _connectWs();
  }

  Future<void> send(SocketMessage msg) async {
    var db = await DB().getDb();
    var msgMap = msg.toMap();
    var msgStr = json.encode(msgMap);
    var outMessage = {
      "messageId": msg.msgId,
      "message": msgStr,
      "sent": 0,
      "created_ts": DateTime.now().millisecondsSinceEpoch,
      "sent_ts": 0,
      "retry_count": 0
    };
    db.insert("out_message", outMessage);
    if (_channel != null && _channel.closeCode != null) {
      await db.update("out_message", {"sent": -1},
          where: "messageId=?", whereArgs: [msg.msgId]);
      return;
    }
    try {
      _channel.add(msgStr);
      await db
          .delete("out_message", where: "messageId=?", whereArgs: [msg.msgId]);
      msg = SocketMessage.fromMap(msgMap);
      msg.from = name;
      msg.state = MessageState.SENT;
      msg.type = MessageType.NOTIFICATION;
      _controller.sink.add(msg);
    } catch (e) {
      await db.update("out_message", {"sent": -1},
          where: "messageId=?", whereArgs: [msg.msgId]);
    }
  }

  void dispose() {
    _closed = true;
    if (_controller != null) _controller.close();
    if (_channel != null) _channel.close();
    if (_connectivitySub != null) _connectivitySub.cancel();
  }

  Future<void> _connectWs() async {
    try {
      Map<String, String> headers = await ApiService.getAuthHeader();
      _channel = await WebSocket.connect(_url, headers: headers);
      _retryCount = 0;
      _channel.asBroadcastStream().listen(_onNewMessage,
          onError: _onError, onDone: _onDone, cancelOnError: false);
      _processPendingMessage();
    } catch (e) {
      print("Error while connecting websocket $e");
      await _reconnectWs();
    }
  }

  Future<void> _reconnectWs({bool ignoreFlag = false}) async {
    if (!ignoreFlag && _reconnecting) return;
    if (_closed) return;
    var _connectivity = Connectivity();
    try {
      ConnectivityResult result = await _connectivity.checkConnectivity();
      if (result == ConnectivityResult.none) {
        _connectivity.onConnectivityChanged.listen((event) {
          _reconnectWs(ignoreFlag: true);
        });
        return;
      } else {
        if (_connectivitySub != null) {
          _connectivitySub.cancel();
          _connectivitySub = null;
        }
      }
    } catch (e) {
      print("Error while checking for connectivity $e, proceeding with it");
    }

    _retryCount++;
    await Future.delayed(Duration(milliseconds: (_retryCount * 500)));
    if (_closed) return;
    if (_reconnecting) return;
    _reconnecting = false;
    if (_channel != null && _channel.closeCode != null) {
      await _connectWs();
    }
  }

  void _onDone() {
    if (_closed) return;
    print("Socket done.. reconnecting");
    _reconnectWs();
  }

  void _onError(error) {
    print(error);
    if (this._channel.closeCode == null) {
      return;
    }
    _reconnectWs();
  }

  void _onNewMessage(event) {
    if (event is List<String>) {
      for (var e in event) {
        _onNewMessage(e);
      }
      return;
    }
    dynamic incomming = json.decode(event);

    if (incomming is Map) {
      try {
        var message = SocketMessage.fromMap(incomming);
        _controller.sink.add(message);
      } catch (ex) {
        print("Exception while decoding server msg: ${ex.toString()}");
      }
    } else if (incomming is List) {
      for (var msg in incomming) {
        if (msg is String) {
          _onNewMessage(msg);
        } else if (msg is Map) {
          try {
            _controller.sink.add(SocketMessage.fromMap(msg));
          } catch (e) {
            print("Exception while decoding server msg : ${msg.toString()}");
          }
        }
      }
    }
  }

  void _processPendingMessage() async {
    if (_processingPromise != null) {
      await _processingPromise;
    }
    _processingPromise = Future<void>(() async {
      var db = await DB().getDb();
      var result = await db.query('out_message',
          columns: ["message"], where: 'sent=?', whereArgs: [-1]);
      for (var row in result) {
        var _smsg = SocketMessage.fromMap(json.decode(row["message"]));
        _channel.add(row["message"]);
        _smsg.from = name;
        _smsg.state = MessageState.SENT;
        _smsg.type = MessageType.NOTIFICATION;
        _controller.sink.add(_smsg);
        await db.update(
            "out_message",
            {
              "sent": 1,
              "sent_ts": DateTime.now().millisecondsSinceEpoch,
            },
            where: "messageId=?",
            whereArgs: [_smsg.msgId]);
      }
    });
  }

  static SocketService get instance {
    if (_instance == null) {
      _instance = SocketService();
    }
    return _instance;
  }
}
