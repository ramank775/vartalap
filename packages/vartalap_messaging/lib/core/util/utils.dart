import 'package:vartalap_messaging/core/http/token.dart';

Map<String, String> authHeader(Token token) {
  const String accessKey = 'accesskey';
  const String userKey = 'user';
  return {
    accessKey: token.accesskey,
    userKey: token.userId,
  };
}

const otherIndex = -1;
const otherStr = "other";

T intToEnum<T>(int index, Iterable<T> values) {
  if (index == otherIndex || values.length - 1 < index) {
    return stringToEnum(otherStr, values);
  }
  return values.elementAt(index);
}

int enumToInt<T>(T value, Iterable<T> values) {
  if (value.toString().split('.')[1].toLowerCase() == otherStr) {
    return otherIndex;
  }
  return values.toList().indexOf(value);
}

T stringToEnum<T>(String value, Iterable<T> values) {
  return values.firstWhere((element) =>
      element.toString().split('.')[1].toLowerCase() == value.toLowerCase());
}

String enumToString<T>(T value) {
  return value.toString().toLowerCase().split('.')[1];
}
