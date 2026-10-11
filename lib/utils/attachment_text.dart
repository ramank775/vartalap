/// How a message reads in one line — chat list, reply quote, reply
/// bar. [attachmentMime] is the attachment's type, null for plain text.
/// A caption follows the glyph; with no caption the kind is spelled out.
String messagePreview(String body, String? attachmentMime) {
  if (attachmentMime == null) return body;
  final (glyph, kind) = attachmentMime.startsWith('image/')
      ? ('📷', 'Photo')
      : attachmentMime.startsWith('video/')
          ? ('🎥', 'Video')
          : ('📄', 'File');
  return '$glyph ${body.isEmpty ? kind : body}';
}

String humanFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
