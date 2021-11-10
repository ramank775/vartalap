import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/utils/socket_message_helper.dart';

Future<void> showNotificationService(String title, String body, dynamic payload,
    {String? groupKey, int id = 0}) {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  var _initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  var _androidPlatformChannelSpecifics = AndroidNotificationDetails(
    'VARTALAP_NOTIFICATION',
    'VARTALAP_NOTIFICATION',
    'Vartalap notification channel',
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'Vartalap notification',
    showWhen: true,
    playSound: true,
    groupKey: groupKey,
    setAsGroupSummary: true,
    groupAlertBehavior: GroupAlertBehavior.summary,
  );
  var _notificationDetails =
      NotificationDetails(android: _androidPlatformChannelSpecifics);
  var flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  flutterLocalNotificationsPlugin.initialize(_initializationSettings);
  var data = json.encode(payload);
  return flutterLocalNotificationsPlugin
      .show(data.hashCode, title, body, _notificationDetails, payload: data);
}

Future<dynamic> fcmBackgroundMessageHandler(RemoteMessage payload) async {
  var event = payload.data["message"];
  print(event);
  var messages = toSocketMessage(event);
  for (var msg in messages) {
    var result = await ChatService.newMessage(msg);
    if (result != null) {
      var chat = await ChatService.getChatInfo(msg.chatId!);
      if (chat == null) return;
      return showNotificationService(chat.title, msg.text, msg.toMap(),
          groupKey: chat.id, id: chat.id.hashCode);
    }
  }
  return Future<void>.value();
}

class PushNotificationService {
  static PushNotificationService? _instance;
  late InitializationSettings _initializationSettings;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  PushNotificationService() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    _initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    this.clearAllNotification();
  }

  void config({Function? onMessage}) async {
    FirebaseMessaging.onMessage.listen((event) {
      onMessage!({"data": event.data});
    });
    _flutterLocalNotificationsPlugin.initialize(_initializationSettings,
        onSelectNotification: (String? payload) async {
      if (onMessage != null && payload != null) {
        var decoded = json.decode(payload);
        Map<String, dynamic> data = Map<String, dynamic>.from(decoded);
        return onMessage({
          "data": {"message": data},
          "source": "ON_NOTIFICATION_TAP"
        });
      }
    });
  }

  Future<String?> get token => FirebaseMessaging.instance.getToken();

  void showNotification(String title, String body, dynamic payload,
      {String? groupKey, int id = 0}) {
    var _androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'VARTALAP_NOTIFICATION',
      'VARTALAP_NOTIFICATION',
      'Vartalap notification channel',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Vartalap notification',
      showWhen: true,
      playSound: true,
      timeoutAfter: 500,
      groupKey: groupKey,
      setAsGroupSummary: true,
      groupAlertBehavior: GroupAlertBehavior.summary,
    );

    var _notificationDetails =
        NotificationDetails(android: _androidPlatformChannelSpecifics);
    var data = json.encode(payload);

    _flutterLocalNotificationsPlugin.show(id, title, body, _notificationDetails,
        payload: data);
  }

  void clearAllNotification() {
    _flutterLocalNotificationsPlugin.cancelAll();
  }

  static PushNotificationService get instance {
    if (_instance == null) {
      FirebaseMessaging.onBackgroundMessage(fcmBackgroundMessageHandler);
      _instance = PushNotificationService();
    }
    return _instance!;
  }
}
