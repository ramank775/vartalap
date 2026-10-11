import 'package:vartalap/utils/rich_message.dart';
import 'package:vartalap_store/vartalap_store.dart';

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
    final (glyph, kind) = switch ((contentType ?? '').split('/').first) {
      'image' => ('📷', 'Photo'),
      'video' => ('🎥', 'Video'),
      'audio' => ('🎤', 'Voice message'),
      _ => ('📄', 'File'),
    };
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

/// A [GroupEvent] line as WhatsApp words it: 'Asha added Ravi and you',
/// 'You changed the group name to "Trip"'. [nameOf] labels anyone but
/// the signed-in user, who reads as You/you.
String groupEventText(
  GroupEvent event, {
  required String actorUserId,
  required String? selfUserId,
  required String Function(String userId) nameOf,
}) {
  String who(String id, {bool first = false}) =>
      id == selfUserId ? (first ? 'You' : 'you') : nameOf(id);
  final actor = who(actorUserId, first: true);
  final users = [for (final id in event.users) who(id)];
  final list = users.length < 2
      ? users.join()
      : '${users.sublist(0, users.length - 1).join(', ')} and ${users.last}';
  return switch (event.kind) {
    GroupEventKind.created => '$actor created group "${event.text ?? ''}"',
    GroupEventKind.added => '$actor added $list',
    GroupEventKind.removed => '$actor removed $list',
    GroupEventKind.left =>
      '${who(event.users.firstOrNull ?? actorUserId, first: true)} left',
    GroupEventKind.renamed =>
      '$actor changed the group name to "${event.text ?? ''}"',
    GroupEventKind.photo => (event.text ?? '').isEmpty
        ? "$actor deleted this group's icon"
        : "$actor changed this group's icon",
  };
}
