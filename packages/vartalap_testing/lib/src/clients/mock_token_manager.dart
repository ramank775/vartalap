import 'package:vartalap_messaging/vartalap_messaging.dart';

/// In-memory token manager for testing to avoid dependencies on native storage
class MockTokenManager implements TokenManager {
  Token? _currentToken;

  @override
  Future<Token?> fetchToken(String userId) async {
    if (_currentToken?.userId == userId) {
      return _currentToken;
    }
    return null;
  }

  @override
  Future<void> setToken(Token token) async {
    _currentToken = token;
  }

  @override
  Future<Token?> fetchActiveToken() async {
    return _currentToken;
  }

  @override
  Future<void> clearToken() async {
    _currentToken = null;
  }
}
