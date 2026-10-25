/// "Asha added Ravi" — a line in a group's history that no one sent.
///
/// The server never sends these: each device writes its own, from the
/// §10.2 event it receives or, for the actor (whose own device is
/// skipped by the fanout), from the action it just took. Stored as a
/// message row so it orders, previews and clears like one; `body`
/// holds the event as JSON and `author_user_id` is the actor.
library vartalap_store.group_event;

import 'dart:convert';

const String kGroupEventType = 'application/x-vartalap-group-event';

/// [securityCode]: `users.first`'s phone has a new identity key (decision
/// 184); written into every chat with them, DMs included.
enum GroupEventKind { created, added, removed, left, renamed, photo, securityCode }

class GroupEvent {
  final GroupEventKind kind;

  /// Who it happened to: the added members, the removed one.
  final List<String> users;

  /// The group's name for [GroupEventKind.created] and
  /// [GroupEventKind.renamed]; for [GroupEventKind.photo], empty when
  /// the photo was removed.
  final String? text;

  const GroupEvent(this.kind, {this.users = const [], this.text});

  String encode() => jsonEncode({
        'k': kind.name,
        if (users.isNotEmpty) 'u': users,
        if (text != null) 't': text,
      });

  /// Null for a body this version can't read (a newer client's kind).
  static GroupEvent? parse(String? body) {
    if (body == null) return null;
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final kind = GroupEventKind.values.asNameMap()[j['k']];
      if (kind == null) return null;
      return GroupEvent(
        kind,
        users: (j['u'] as List?)?.cast<String>() ?? const [],
        text: j['t'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
