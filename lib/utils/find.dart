T? find<T>(Iterable<T> items, bool Function(T) fn) {
  try {
    return items.firstWhere(fn);
  } catch (_) {
    return null;
  }
}
