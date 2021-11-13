import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/models/remoteMessage.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/push_notification_service.dart';

import 'package:vartalap/services/performance_metric.dart';

class ApiService {
  static FlutterSecureStorage _storage = new FlutterSecureStorage();
  static const String ACCESS_KEY = 'accesskey';
  static Future<String?> get _accesskey {
    return _storage.read(key: ACCESS_KEY);
  }

  static Future<Map<String, String>> getAuthHeader(
      {includeAccessKey = true}) async {
    String? idToken = await AuthService.instance.idToken;
    Map<String, String> headers = {};
    if (idToken != null) {
      headers["token"] = idToken;
    }
    String? phone = AuthService.instance.phoneNumber;
    if (phone != null) {
      headers["user"] = phone;
    }
    if (includeAccessKey) {
      String? key = await _accesskey;
      if (key != null) headers[ACCESS_KEY] = key;
    }

    return headers;
  }

  static Future<http.Response> _post(String path, dynamic data,
      {bool includeAccesskey = true}) async {
    String baseUrl = ConfigStore().get<String>("api_url");
    var resourceUrl = Uri.parse("$baseUrl/$path");
    var _httpMetric =
        PerformanceMetric.newHttpMetric(resourceUrl.toString(), 'post');

    String content = json.encode(data);
    Map<String, String> headers =
        await getAuthHeader(includeAccessKey: includeAccesskey);
    headers["Content-Type"] = "application/json";

    await _httpMetric.start();
    http.Response resp;
    try {
      resp = await http.post(resourceUrl, headers: headers, body: content);
      _httpMetric
        ..responsePayloadSize = resp.contentLength ?? 0
        ..responseContentType = resp.headers['Content-Type'] ?? ''
        ..requestPayloadSize = resp.contentLength ?? 0
        ..httpResponseCode = resp.statusCode;
    } finally {
      _httpMetric.stop();
    }

    return resp;
  }

  static Future<http.Response> _get(String path,
      {bool includeAccesskey = true}) async {
    String baseUrl = ConfigStore().get<String>("api_url");
    var resourceUrl = Uri.parse("$baseUrl/$path");
    var _httpMetric =
        PerformanceMetric.newHttpMetric(resourceUrl.toString(), 'get');

    Map<String, String> headers =
        await getAuthHeader(includeAccessKey: includeAccesskey);

    await _httpMetric.start();
    http.Response resp;
    try {
      resp = await http.get(resourceUrl, headers: headers);
      _httpMetric
        ..responsePayloadSize = resp.contentLength ?? 0
        ..responseContentType = resp.headers['Content-Type'] ?? ''
        ..requestPayloadSize = resp.contentLength ?? 0
        ..httpResponseCode = resp.statusCode;
    } finally {
      _httpMetric.stop();
    }

    return resp;
  }

  static Map<String, dynamic> _handleResponse(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      Map<String, dynamic> response;
      if (resp.body.length > 0) {
        var decoded = json.decode(resp.body);
        response = Map<String, dynamic>.from(decoded);
      } else {
        response = {};
      }
      return response;
    }
    throw Exception("Response code ${resp.statusCode}");
  }

  static List<Map<String, dynamic>> _handleListResponse(http.Response resp) {
    if (resp.statusCode == 200) {
      var decoded = json.decode(resp.body);
      List<Map<String, dynamic>> response = [];
      if (decoded is List) {
        for (var i = 0; i < decoded.length; i++) {
          var resp = Map<String, dynamic>.from(decoded[i]);
          response.add(resp);
        }
      }
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

  static Future<String> createGroup(
      String groupTitle, List<String> members, String? profilePic) async {
    http.Response response = await _post("group/create",
        {"name": groupTitle, "members": members, "profilePic": profilePic});
    Map<String, dynamic> resp = _handleResponse(response);
    return resp["groupId"].toString();
  }

  static Future<bool> addMembersToGroup(
      List<String> members, String groupId) async {
    http.Response response =
        await _post("group/$groupId/add", {"members": members});
    Map<String, dynamic> resp = _handleResponse(response);
    return resp["status"];
  }

  static Future<bool> removeMemberToGroup(String member, String groupId) async {
    http.Response response =
        await _post("group/$groupId/remove", {"member": member});
    Map<String, dynamic> resp = _handleResponse(response);
    return resp["status"];
  }

  static Future<Map<String, dynamic>> getGroupInfo(String groupId) async {
    http.Response response = await _get("group/$groupId");
    Map<String, dynamic> resp = _handleResponse(response);
    return resp;
  }

  static Future<List<Map<String, dynamic>>> getGroups() async {
    http.Response response = await _get("group/get");
    var resp = _handleListResponse(response);
    return resp;
  }

  static Future sendMessages(Iterable<RemoteMessage> messages) async {
    final body = messages.map((msg) => json.encode(msg.toMap())).toList();
    final resp = await _post("messages", body);
    _handleResponse(resp);
  }
}
