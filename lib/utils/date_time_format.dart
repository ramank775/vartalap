final List<String> _months = [
  "",
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "June",
  "July",
  "Aug",
  "Sept",
  "Oct",
  "Nov",
  "Dec"
];

String formatMessageDate(DateTime date) {
  Object format(int n) => n < 10 ? "0$n" : n;
  final today = DateTime.now();
  if (date.year == today.year && date.month == today.month) {
    if (date.day == today.day) {
      return "Today";
    } else if (date.day == today.day - 1) {
      return "Yesterday";
    }
  }
  if (date.year == today.year) {
    return "${_months[date.month]} ${date.day}";
  }
  return "${_months[date.month]} ${date.day}, ${format(date.year)}";
}

String formatMessageTime(DateTime date) {
  Object format(int n) => n < 10 ? "0$n" : n;
  return "${date.hour}:${format(date.minute)}";
}

String formatMessageTimestamp(DateTime date) {
  final today = DateTime.now();
  if (date.year == today.year &&
      date.day == today.day &&
      date.month == today.month) {
    return formatMessageTime(date);
  }
  return formatMessageDate(date);
}
