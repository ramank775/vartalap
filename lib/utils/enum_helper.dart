T intToEnum<T>(int index, Iterable<T> values) {
  return values.elementAt(index);
}

int enumToInt<T>(T value, Iterable<T> values) {
  return values.toList().indexOf(value);
}

T stringToEnum<T>(String value, Iterable<T> values) {
  return values.firstWhere((element) =>
      element.toString().split('.')[1].toLowerCase() == value.toLowerCase());
}

String enumToString<T>(T value) {
  return value.toString().toLowerCase().split('.')[1];
}
