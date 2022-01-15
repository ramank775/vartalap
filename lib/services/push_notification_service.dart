import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/remoteMessage.dart' as vRemoteMessage;
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/utils/chat_message_helper.dart';
import 'package:vartalap/utils/remote_message_helper.dart';

Future<void> showNotificationService(String title, String body, dynamic payload,
    {String? groupKey, int id = 0}) {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  var _initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  var _androidPlatformChannelSpecifics = AndroidNotificationDetails(
    'VARTALAP_NOTIFICATION',
    'VARTALAP_NOTIFICATION',
    channelDescription: 'Vartalap notification channel',
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
  await Firebase.initializeApp();
  await ConfigStore().loadConfig();
  await AuthService.init();
  final event = payload.data["message"];
  final messages = toRemoteMessage(event);
  final List<vRemoteMessage.RemoteMessage> deliveryAcks = [];
  for (var msg in messages) {
    var result = await ChatService.newMessage(msg);
    if (result != null && msg.head.contentType != MessageType.NOTIFICATION) {
      var chat = await ChatService.getChatInfo(msg.head.chatid!);
      if (chat == null) return;
      deliveryAcks.add(result);
      final notify = toChatMessage(msg).notificationContent;
      if (notify.show && notify.content != null) {
        showNotificationService(chat.title, notify.content!, msg.toMap(),
            groupKey: chat.id, id: chat.id.hashCode);
      }
    }
  }
  return await ChatService.ackMessageDelivery(deliveryAcks, socket: false);
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
      channelDescription: 'Vartalap notification channel',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Vartalap notification',
      showWhen: true,
      playSound: true,
      timeoutAfter:
          WidgetsBinding.instance!.lifecycleState == AppLifecycleState.resumed
              ? 500
              : null,
      groupKey: groupKey,
      setAsGroupSummary: true,
      groupAlertBehavior: GroupAlertBehavior.all,
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
