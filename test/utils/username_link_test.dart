import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/utils/username_link.dart';

void main() {
  test('round trips with and without a key', () {
    expect(usernameLink('asha_k'), 'vartalap://u/asha_k');
    expect(usernameLink('asha_k', key: '0042'), 'vartalap://u/asha_k?k=0042');
    expect(parseUsernameLink(usernameLink('asha_k')),
        (username: 'asha_k', key: null));
    expect(parseUsernameLink(' vartalap://u/asha_k?k=0042\n'),
        (username: 'asha_k', key: '0042'));
  });

  test('anything else is not a profile link', () {
    for (final raw in [
      'https://u/asha_k',
      'vartalap://chat/asha_k',
      'vartalap://u/',
      'vartalap://u/a/b',
      'hello',
      '',
    ]) {
      expect(parseUsernameLink(raw), isNull, reason: raw);
    }
  });
}
