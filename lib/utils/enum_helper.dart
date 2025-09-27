const _otherIndex = -1;
const _otherStr = "other";

T intToEnum<T>(int index, Iterable<T> values) {
  if (index == _otherIndex || values.length - 1 < index) {
    return stringToEnum(_otherStr, values);
  }
  return values.elementAt(index);
}

int enumToInt<T>(T value, Iterable<T> values) {
  if (value.toString().split('.')[1].toLowerCase() == _otherStr) {
    return _otherIndex;
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
