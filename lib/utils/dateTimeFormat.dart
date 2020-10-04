String formatMessageDateTime(int timestamp) {
  var date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  var currentDate = DateTime.now();
  var format = (int n) => n < 10 ? "0$n" : n;

  if (date.day == currentDate.day &&
      date.month == currentDate.month &&
      date.year == currentDate.year) {
    return "${date.hour}:${format(date.minute)}";
  }
  return "${date.day}/${format(date.month)} ${date.hour}:${format(date.minute)}";
}
