import 'package:vartalap_messaging/core/http/token.dart';

abstract class TokenManager {
  Future<void> setToken(Token token);
  Future<Token?> fetchToken(String userId);
  Future<Token?> fetchActiveToken();
  Future<void> clearToken();
}
