/// The username rules, in one place.
///
/// Shared by the mandatory "choose your username" step
/// (`screens/login/choose_username.dart`) and the Username row on the
/// Profile screen, so the two can never drift apart.
library vartalap.utils.username;

import 'dart:math';

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

const List<String> _adjectives = [
  'bold',
  'brave',
  'breezy',
  'bright',
  'calm',
  'cheery',
  'clever',
  'cosy',
  'crisp',
  'gentle',
  'golden',
  'happy',
  'jolly',
  'keen',
  'kind',
  'lively',
  'lucky',
  'mellow',
  'merry',
  'misty',
  'nimble',
  'plucky',
  'quick',
  'quiet',
  'rapid',
  'rosy',
  'silver',
  'snowy',
  'starry',
  'sunny',
  'swift',
  'tidy',
  'vivid',
  'warm',
  'wise',
  'witty',
  'zesty',
  'zippy',
];

const List<String> _nouns = [
  'bison',
  'cedar',
  'comet',
  'dolphin',
  'ember',
  'falcon',
  'firefly',
  'galaxy',
  'harbor',
  'heron',
  'island',
  'jasmine',
  'kite',
  'koala',
  'lantern',
  'lemur',
  'lotus',
  'mango',
  'maple',
  'meadow',
  'monsoon',
  'nova',
  'orchid',
  'otter',
  'owl',
  'panda',
  'parrot',
  'peacock',
  'pebble',
  'quokka',
  'river',
  'robin',
  'saffron',
  'sparrow',
  'tiger',
  'tulip',
  'willow',
  'zebra',
];

/// A readable random handle such as `quietfalcon42` for the "Generate"
/// button: adjective + noun + 2 digits, about 130k combinations, always
/// valid under [validateUsername]. Availability is still the server's call.
String generateUsername([Random? random]) {
  final r = random ?? Random();
  return '${_adjectives[r.nextInt(_adjectives.length)]}'
      '${_nouns[r.nextInt(_nouns.length)]}'
      '${10 + r.nextInt(90)}';
}
