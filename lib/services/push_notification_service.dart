import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/utils/socket_message_helper.dart';

Future<void> showNotificationService(
    String title, String body, dynamic payload) {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  var _initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  AndroidNotificationDetails _androidPlatformChannelSpecifics =
      AndroidNotificationDetails('VARTALAP_NOTIFICATION',
          'VARTALAP_NOTIFICATION', 'Vartalap notification channel',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'Vartalap notification');
  var _notificationDetails =
      NotificationDetails(android: _androidPlatformChannelSpecifics);
  var flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  flutterLocalNotificationsPlugin.initialize(_initializationSettings);
  var data = json.encode(payload);
  return flutterLocalNotificationsPlugin
      .show(data.hashCode, title, body, _notificationDetails, payload: data);
}

Future<dynamic> fcmBackgroundMessageHandler(
    Map<String, dynamic> payload) async {
  var event = payload["data"]["message"];
  var messages = toSocketMessage(event);
  for (var msg in messages) {
    var result = await ChatService.newMessage(msg);
    if (result != null) {
      return showNotificationService("New Message", msg.text, msg.toMap());
    }
  }
  return Future<void>.value();
}

class PushNotificationService {
  FirebaseMessaging _fcm;
  static PushNotificationService _instance;
  InitializationSettings _initializationSettings;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  NotificationDetails _notificationDetails;

  PushNotificationService() {
    _fcm = FirebaseMessaging();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    _initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    AndroidNotificationDetails _androidPlatformChannelSpecifics =
        AndroidNotificationDetails('VARTALAP_NOTIFICATION',
            'VARTALAP_NOTIFICATION', 'Vartalap notification channel',
            importance: Importance.max,
            priority: Priority.high,
            ticker: 'Vartalap notification');
    _notificationDetails =
        NotificationDetails(android: _androidPlatformChannelSpecifics);
  }

  void config(
      {Function onMessage, Function onLaunch, Function onResume}) async {
    _fcm.configure(
      onMessage: onMessage,
      onLaunch: onLaunch,
      onResume: onResume,
      onBackgroundMessage: fcmBackgroundMessageHandler,
    );
    _flutterLocalNotificationsPlugin.initialize(_initializationSettings,
        onSelectNotification: (String payload) async {
      if (onMessage != null) {
        var decoded = json.decode(payload);
        Map<String, dynamic> data = Map<String, dynamic>.from(decoded);
        return onMessage({
          "data": {"message": data},
          "source": "ON_NOTIFICATION_TAP"
        });
      }
    });
  }

  Future<String> get token => _fcm.getToken();

  void showNotification(String title, String body, dynamic payload) {
    var data = json.encode(payload);
    _flutterLocalNotificationsPlugin.show(0, title, body, _notificationDetails,
        payload: data);
  }

  static PushNotificationService get instance {
    if (_instance == null) {
      _instance = PushNotificationService();
    }
    return _instance;
  }
}
