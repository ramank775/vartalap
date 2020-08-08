T intToEnum<T>(int index, Iterable<T> values) {
  return values.elementAt(index);
}

int enumToInt<T>(T value, Iterable<T> values) {
  return values.toList().indexOf(value);
}
