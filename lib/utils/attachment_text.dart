import 'package:vartalap/utils/rich_message.dart';

/// How a message reads in one line — chat list, reply quote, reply
/// bar. With an [attachment], [contentType] is its type: a caption
/// follows the glyph, and with no caption the kind is spelled out.
/// Contact, location and event messages (decision 133) say what they
/// are rather than show their vCard / geo / iCalendar body.
String messagePreview(
  String body,
  String? contentType, {
  required bool attachment,
}) {
  if (attachment) {
    final type = contentType ?? '';
    final (glyph, kind) = type.startsWith('image/')
        ? ('📷', 'Photo')
        : type.startsWith('video/')
            ? ('🎥', 'Video')
            : ('📄', 'File');
    return '$glyph ${body.isEmpty ? kind : body}';
  }
  return switch (contentType) {
    kContactType => '👤 ${contactName(body)}',
    kLocationType => '📍 Location',
    kEventType => '📅 ${EventInfo.parse(body)?.title ?? 'Event'}',
    _ => body,
  };
}

String humanFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
