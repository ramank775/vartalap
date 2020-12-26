import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/push_notification_service.dart';

import 'package:vartalap/services/performance_metric.dart';

class ApiService {
  static FlutterSecureStorage _storage = new FlutterSecureStorage();
  static const String ACCESS_KEY = 'accesskey';
  static Future<String> get _accesskey {
    return _storage.read(key: ACCESS_KEY);
  }

  static Future<Map<String, String>> getAuthHeader(
      {includeAccessKey = true}) async {
    String idToken = await AuthService.instance.idToken;
    Map<String, String> headers = {
      "token": idToken,
      "user": AuthService.instance.phoneNumber
    };
    if (includeAccessKey) {
      headers[ACCESS_KEY] = await _accesskey;
    }

    return headers;
  }

  static Future<http.Response> _post(String path, Map<String, dynamic> data,
      {bool includeAccesskey = true}) async {
    String url = ConfigStore().get<String>("api_url");
    String resourceUrl = "$url/$path";
    var _httpMetric = PerformanceMetric.newHttpMetric(resourceUrl, 'post');

    String content = json.encode(data);
    Map<String, String> headers =
        await getAuthHeader(includeAccessKey: includeAccesskey);
    headers["Content-Type"] = "application/json";

    await _httpMetric.start();
    http.Response resp;
    try {
      resp = await http.post(resourceUrl, headers: headers, body: content);
      _httpMetric
        ..responsePayloadSize = resp.contentLength
        ..responseContentType = resp.headers['Content-Type']
        ..requestPayloadSize = resp.contentLength
        ..httpResponseCode = resp.statusCode;
    } finally {
      _httpMetric.stop();
    }

    return resp;
  }

  static Map<String, dynamic> _handleResponse(http.Response resp) {
    if (resp.statusCode == 200) {
      var decoded = json.decode(resp.body);
      Map<String, dynamic> response = Map<String, dynamic>.from(decoded);
      return response;
    }
    throw Exception("Response code ${resp.statusCode}");
  }

  static login(String phone) async {
    var notificationToken = await PushNotificationService.instance.token;
    http.Response response = await _post(
        "login",
        {
          "username": phone,
          "notificationToken": notificationToken,
        },
        includeAccesskey: false);
    Map<String, dynamic> resp = _handleResponse(response);
    String accessKey = resp["accesskey"];
    _storage.write(key: ACCESS_KEY, value: accessKey);
  }

  static Future<Map<String, dynamic>> syncContact(List<String> users) async {
    http.Response response = await _post("profile/user/sync", {"users": users});
    Map<String, dynamic> resp = _handleResponse(response);
    return resp;
  }
}
