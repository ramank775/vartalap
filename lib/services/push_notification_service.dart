import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  FirebaseMessaging _fcm;
  static PushNotificationService _instance;
  InitializationSettings _initializationSettings;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  PushNotificationService() {
    _fcm = FirebaseMessaging();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    _initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
  }

  void config(
      {Function onMessage, Function onLaunch, Function onResume}) async {
    _fcm.configure(
      onLaunch: onLaunch,
      onResume: onResume,
    );
    _flutterLocalNotificationsPlugin.initialize(_initializationSettings,
        onSelectNotification: (String payload) async {
      if (onMessage != null) {
        var decoded = json.decode(payload);
        Map<String, dynamic> data = Map<String, dynamic>.from(decoded);
        return onMessage({"data": data});
      }
    });
  }

  Future<String> get token => _fcm.getToken();

  void showNotification(String title, String body, dynamic payload) {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails('VARTALAP_NOTIFICATION',
            'VARTALAP_NOTIFICATION', 'Vartalap notification channel',
            importance: Importance.max,
            priority: Priority.high,
            ticker: 'Vartalap notification');
    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    var data = json.encode(payload);
    _flutterLocalNotificationsPlugin.show(0, title, body, notificationDetails,
        payload: data);
  }

  static PushNotificationService get instance {
    if (_instance == null) {
      _instance = PushNotificationService();
    }
    return _instance;
  }
}
