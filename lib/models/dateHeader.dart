class DateHeader {
  final String date;

  const DateHeader({
    required this.date,
  });

  int get hashCode => this.date.hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}
