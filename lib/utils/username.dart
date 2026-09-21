/// The username rules, in one place.
///
/// Shared by the mandatory "choose your username" step
/// (`screens/login/choose_username.dart`) and the Username row on the
/// Profile screen, so the two can never drift apart.
library vartalap.utils.username;

/// Sync-only validator for usernames — AUTH_CONTRACT §2.4/§4.5.
///
/// Charset/length only. The server has the final say on uniqueness (via
/// `POST /v3.0/users/username/check`) and on reserved words (the
/// `reason` of an unavailable response); running these rules first
/// keeps obviously-bad input off the rate limit.
///
/// Returns null when [value] is acceptable, else a short message for
/// the field's helper line. Empty is rejected: since v1.1 the username
/// is required, so there is no "clear it" path in the UI (§2.4 keeps
/// clearing as a server capability only).
String? validateUsername(String value) {
  if (value.isEmpty) return 'Pick a username';
  if (value.length < 3) return 'At least 3 characters';
  if (value.length > 30) return 'At most 30 characters';
  if (!RegExp(r'^[a-z]').hasMatch(value)) {
    return 'Must start with a letter';
  }
  if (!RegExp(r'^[a-z0-9._]+$').hasMatch(value)) {
    return 'Only a-z, 0-9, _ and . allowed';
  }
  if (value.contains('..') || value.contains('__')) {
    return 'No double dots or underscores';
  }
  return null;
}

/// The rules, spelled out under the field (mockup frame h).
const String kUsernameRulesHint =
    '3–30 characters. Letters, numbers, dot and underscore. '
    'Must start with a letter.';

/// How long to wait after the last keystroke before asking the server
/// whether a candidate is free.
const Duration kUsernameCheckDebounce = Duration(milliseconds: 400);
