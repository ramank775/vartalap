String formatMessageDate(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final format = (int n) => n < 10 ? "0$n" : n;

  return "${date.day}/${format(date.month)}/${format(date.year)}";
}

String formatMessageTime(int timestamp) {
  var date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  var format = (int n) => n < 10 ? "0$n" : n;
  return "${date.hour}:${format(date.minute)}";
}
