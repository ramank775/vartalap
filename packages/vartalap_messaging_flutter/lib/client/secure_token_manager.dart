// ignore_for_file: constant_identifier_names

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vartalap_messaging/vartalap_messaging.dart';

class SecureStorageTokenManager implements TokenManager {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String ACCESS_KEY = "stm_accesskey";
  static const String USER_ID_KEY = "stm_userid";

  String? _userId;
  Token? _token;

  @override
  Future<Token?> fetchToken(String userId) async {
    final existingUserId = await _storage.read(key: USER_ID_KEY);
    if (userId != existingUserId) {
      return null;
    }
    final accesskey = await _storage.read(key: ACCESS_KEY);
    if (accesskey == null) {
      return null;
    }
    return Token(userId: userId, accesskey: accesskey);
  }

  @override
  Future<void> setToken(Token token) async {
    await _storage.write(key: USER_ID_KEY, value: token.userId);
    await _storage.write(key: ACCESS_KEY, value: token.accesskey);
  }

  @override
  Future<Token?> fetchActiveToken() async {
    if (_userId == null) {
      _userId = await _storage.read(key: USER_ID_KEY);
    } else if (_token != null) {}
    if (_userId == null) return null;

    final token = await fetchToken(_userId!);
    return token;
  }
}
