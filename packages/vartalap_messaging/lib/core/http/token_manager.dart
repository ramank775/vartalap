import 'package:vartalap_messaging/core/http/token.dart';

abstract class TokenManager {
  Future<void> setToken(Token token);
  Future<Token?> fetchToken(String userId);
  Future<Token?> fetchActiveToken();
}

// // TODO: Extract the Implementation outside the Core
// class SecureStorageTokenManager implements TokenManager {
//   final FlutterSecureStorage _storage = new FlutterSecureStorage();
//   static const String ACCESS_KEY = "stm_accesskey";
//   static const String USER_ID_KEY = "stm_userid";

//   String? _userId;
//   Token? _token;

//   @override
//   Future<Token?> fetchToken(String userId) async {
//     final existingUserId = await this._storage.read(key: USER_ID_KEY);
//     if (userId != existingUserId) {
//       return null;
//     }
//     final accesskey = await this._storage.read(key: ACCESS_KEY);
//     if (accesskey == null) {
//       return null;
//     }
//     return Token(userId: userId, accesskey: accesskey);
//   }

//   @override
//   Future<void> setToken(Token token) async {
//     await this._storage.write(key: USER_ID_KEY, value: token.userId);
//     await this._storage.write(key: ACCESS_KEY, value: token.accesskey);
//   }

//   @override
//   Future<Token?> fetchActiveToken() async {
//     if (this._userId == null) {
//       this._userId = await this._storage.read(key: USER_ID_KEY);
//     } else if (this._token != null) {}
//     if (this._userId == null) return null;

//     final token = await this.fetchToken(this._userId!);
//     return token;
//   }
// }
