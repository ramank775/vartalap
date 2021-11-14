import 'package:flutter/foundation.dart';

class SetNotifier<T> extends ValueNotifier<Set<T>> {
  SetNotifier(Set<T> value) : super(value);
  update() {
    this.notifyListeners();
  }
}
