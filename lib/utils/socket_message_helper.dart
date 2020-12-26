import 'dart:convert';

import 'package:vartalap/models/socketMessage.dart';
import 'package:vartalap/services/crashanalystics.dart';

List<SocketMessage> toSocketMessage(dynamic event) {
  List<SocketMessage> _messages = [];
  if (event is List<String>) {
    for (var e in event) {
      _messages.addAll(toSocketMessage(e));
    }
    return _messages;
  }
  dynamic incomming = json.decode(event);

  if (incomming is Map) {
    try {
      var message = SocketMessage.fromMap(incomming);
      _messages.add(message);
    } catch (ex, stack) {
      Crashlytics.recordError(ex, stack,
          reason: "Exception while decoding server msg");
    }
  } else if (incomming is List) {
    for (var msg in incomming) {
      if (msg is String) {
        _messages.addAll(toSocketMessage(msg));
      } else if (msg is Map) {
        try {
          _messages.add(SocketMessage.fromMap(msg));
        } catch (e, stack) {
          Crashlytics.recordError(e, stack,
              reason:
                  "Exception while decoding server msg : ${msg.toString()}");
        }
      }
    }
  }
  return _messages;
}
