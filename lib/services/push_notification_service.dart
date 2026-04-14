// Stub: Firebase removed per V3_ARCHITECTURE.md decision 1. Replacement pending v3 auth/push/crash work.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> showNotificationService(String title, String body, dynamic payload,
    {String? groupKey, int id = 0}) {
  return Future.value();
}

@pragma('vm:entry-point')
Future<dynamic> fcmBackgroundMessageHandler(dynamic payload) async {
  return null;
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

  void config({required Function onMessage}) async {
    _flutterLocalNotificationsPlugin.initialize(
      settings: _initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          var decoded = json.decode(details.payload!);
          Map<String, dynamic> data = Map<String, dynamic>.from(decoded);
          return onMessage({
            "data": {"message": data},
            "source": "ON_NOTIFICATION_TAP"
          });
        }
      },
      onDidReceiveBackgroundNotificationResponse: (details) {
        if (details.payload != null) {
          var decoded = json.decode(details.payload!);
          Map<String, dynamic> data = Map<String, dynamic>.from(decoded);
          return onMessage({
            "data": {"message": data},
            "source": "ON_NOTIFICATION_TAP"
          });
        }
      },
    );
  }

  Future<String?> get token => Future.value(null);

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
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed
              ? 500
              : null,
      groupKey: groupKey,
      setAsGroupSummary: true,
      groupAlertBehavior: GroupAlertBehavior.all,
    );

    var _notificationDetails =
        NotificationDetails(android: _androidPlatformChannelSpecifics);
    var data = json.encode(payload);

    _flutterLocalNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _notificationDetails,
        payload: data);
  }

  void clearAllNotification() {
    _flutterLocalNotificationsPlugin.cancelAll();
  }

  static PushNotificationService get instance {
    if (_instance == null) {
      _instance = PushNotificationService();
    }
    return _instance!;
  }
}
