import 'package:test/test.dart';
import 'package:vartalap_sync/vartalap_sync.dart';

/// Trim 4 — `design/protocol/TRIM_4_12_CONTRACT.md` §1.
///
/// The fixture vector below is the whole interop contract with the
/// server: two implementations that agree on it agree everywhere, and
/// two that don't produce `forbidden` on the first message rather than
/// anything subtler. Computed independently of this code:
///
/// ```python
/// 'd' + hashlib.sha256(b'0a1b2c3d4\x00f00dcafe1').hexdigest()[:31]
/// ```
void main() {
  // The cross-repo vector. chat-server's test/dm-channel-id.test.js
  // pins the same two pairs to the same two strings; change either
  // side and DMs stop routing.
  const a = 'a3f2e8c5d';
  const b = 'b1c2d3e4f';

  test('fixture vector, byte for byte with the server', () {
    expect(dmChannelId(a, b), 'dddb157c8f60f31b6a37bd1dbac44245');
    expect(
      dmChannelId('000000001', 'fffffffff'),
      'daea83a8c892d7aea12609dc292aa1a8',
    );
  });

  test('argument order does not matter', () {
    expect(dmChannelId(b, a), dmChannelId(a, b));
  });

  test('exactly 32 chars, "d" + 31 hex', () {
    final id = dmChannelId(a, b);
    expect(id, hasLength(32));
    expect(id, matches(RegExp(r'^d[0-9a-f]{31}$')));
  });

  test('the NUL separator is load-bearing', () {
    // Without it, ("0a1b2c" , "3d4f00dcafe1") and ("0a1b2c3d4",
    // "f00dcafe1") would concatenate to the same bytes. They must not
    // collide, or two different pairs could share a channel.
    expect(
      dmChannelId('0a1b2c', '3d4f00dcafe1'),
      isNot(dmChannelId(a, b)),
    );
  });

  test('a different pair is a different channel', () {
    expect(dmChannelId(a, b), isNot(dmChannelId(a, 'c2d3e4f5a')));
  });

  test('a self DM is derivable and stable', () {
    expect(dmChannelId(a, a), dmChannelId(a, a));
    expect(isDmChannelId(dmChannelId(a, a)), isTrue);
  });

  test('only the full shape is a DM id — a group UUID never is', () {
    expect(isDmChannelId(dmChannelId(a, b)), isTrue);
    expect(isDmChannelId('01996f0e-1a2b-7c3d-8e4f-000000000000'), isFalse);
    // The strict test, not a `d` prefix: a UUID starting with `d` still
    // has a dash at index 8, so the two id spaces cannot collide.
    expect(isDmChannelId('d1efabcd-7000-8000-8abc-000000000002'), isFalse);
    expect(isDmChannelId('d'), isFalse);
    expect(isDmChannelId('D${'0' * 31}'), isFalse);
  });
}
