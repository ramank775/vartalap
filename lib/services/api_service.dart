import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/services/auth_service.dart';

class ApiService {
  static FlutterSecureStorage _storage = new FlutterSecureStorage();
  static const String ACCESS_KEY = 'accessey';
  static Future<String> get _accesskey {
    return _storage.read(key: ACCESS_KEY);
  }

  static Future<http.Response> _post(String path, Map<String, dynamic> data,
      {bool includeAccesskey = true}) async {
    String url = ConfigStore().get<String>("api_url");
    String content = json.encode(data);
    String idToken = await AuthService.instance.idToken;
    Map<String, String> headers = {
      "Content-Type": "application/json",
      "token": idToken
    };
    if (includeAccesskey) {
      headers[ACCESS_KEY] = await _accesskey;
    }
    http.Response resp =
        await http.post("$url/$path", headers: headers, body: content);
    return resp;
  }

  static Map<String, dynamic> _handleResponse(http.Response resp) {
    if (resp.statusCode == 200) {
      Map<String, dynamic> response = json.decode(resp.body);
      return response;
    }
    throw Exception("Response code ${resp.statusCode}");
  }

  static login(String phone) async {
    http.Response response = await _post("login", {"username": phone});
    Map<String, dynamic> resp = _handleResponse(response);
    String accessKey = resp["accesskey"];
    _storage.write(key: ACCESS_KEY, value: accessKey);
  }
}
