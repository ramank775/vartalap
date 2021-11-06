import 'dart:convert';

import 'package:vartalap/models/remoteMessage.dart';
import 'package:vartalap/services/crashlystics.dart';

List<RemoteMessage> toRemoteMessage(dynamic event) {
  List<RemoteMessage> _messages = [];
  if (event is List<String>) {
    for (var e in event) {
      _messages.addAll(toRemoteMessage(e));
    }
    return _messages;
  }
  dynamic incomming = json.decode(event);

  if (incomming is Map) {
    try {
      var message = RemoteMessage.fromMap(incomming as Map<String, dynamic>);
      _messages.add(message);
    } catch (ex, stack) {
      Crashlytics.recordError(ex, stack,
          reason: "Exception while decoding server msg");
    }
  } else if (incomming is List) {
    for (var msg in incomming) {
      if (msg is String) {
        _messages.addAll(toRemoteMessage(msg));
      } else if (msg is Map) {
        try {
          _messages.add(RemoteMessage.fromMap(msg as Map<String, dynamic>));
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
