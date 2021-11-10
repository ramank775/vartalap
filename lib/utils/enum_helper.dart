const _OTHER_INDEX = -1;
const _OTHER_STR = "other";

T intToEnum<T>(int index, Iterable<T> values) {
  if (index == _OTHER_INDEX || values.length - 1 < index) {
    return stringToEnum(_OTHER_STR, values);
  }
  return values.elementAt(index);
}

int enumToInt<T>(T value, Iterable<T> values) {
  if (value.toString().split('.')[1].toLowerCase() == _OTHER_STR) {
    return _OTHER_INDEX;
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
