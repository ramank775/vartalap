import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Trim 4 — a DM channel id is *derived* from the pair, never minted
/// and never created (`design/protocol/TRIM_4_12_CONTRACT.md` §1,
/// PROTOCOL_V4_DRAFT §5.2):
///
/// ```
/// dm_chan(a, b) = "d" + sha256_hex(min(a,b) + "\x00" + max(a,b))[0:31]
/// ```
///
/// [a] and [b] are the two 9-lowercase-hex `user_id`s, compared as
/// ASCII byte strings (`String.compareTo` is code-unit order, which for
/// `[0-9a-f]` is byte order). The result is exactly 32 chars.
///
/// Both clients compute it offline with no coordination, so two people
/// who start the same DM while offline land on the same channel: there
/// is no winner, no fold, no merge and no id remap. The server
/// recomputes it from the authenticated sender plus `Envelope.peer`
/// and answers `forbidden` on a mismatch, which is why a third party
/// cannot squat the id — there is no row to pre-create.
String dmChannelId(String a, String b) {
  final low = a.compareTo(b) <= 0 ? a : b;
  final high = a.compareTo(b) <= 0 ? b : a;
  final digest = sha256.convert(utf8.encode('$low\u0000$high'));
  return 'd${digest.toString().substring(0, 31)}';
}

final RegExp _dmChannelIdShape = RegExp(r'^d[0-9a-f]{31}$');

/// A channel id that names a derived DM: `d` plus 31 lowercase hex
/// chars, no dashes.
///
/// The test is the full shape, not the prefix, and the server's is the
/// same regex. A group id is a dashed UUID, so the dash at index 8
/// keeps the two id spaces provably disjoint even for the ~1/16 of
/// UUIDs that happen to start with `d`.
bool isDmChannelId(String channelId) =>
    _dmChannelIdShape.hasMatch(channelId);
