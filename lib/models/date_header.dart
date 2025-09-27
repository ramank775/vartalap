class DateHeader {
  final String date;

  const DateHeader({
    required this.date,
  });

  @override
  int get hashCode => date.hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}
