import 'package:flutter/foundation.dart';

class SetNotifier<T> extends ValueNotifier<Set<T>> {
  SetNotifier(super.value);
  void update() {
    notifyListeners();
  }
}
