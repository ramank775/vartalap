import 'package:vartalap_messaging/core/http/token.dart';

Map<String, String> authHeader(Token token) {
  const String accessKey = 'accesskey';
  const String userKey = 'user';
  return {
    accessKey: token.accesskey,
    userKey: token.userId,
  };
}
