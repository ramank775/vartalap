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
  const a = '0a1b2c3d4';
  const b = 'f00dcafe1';

  test('fixture vector', () {
    expect(dmChannelId(a, b), 'dbccd1126751877952141531d8ed1dab');
    expect(
      dmChannelId('000000001', '000000002'),
      'dab5ae539af949320c25f7f5eb29cc2f',
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
    expect(dmChannelId(a, b), isNot(dmChannelId(a, '000000003')));
  });

  test('d-prefixed ids are DMs, UUIDv7 group ids are not', () {
    expect(isDmChannelId(dmChannelId(a, b)), isTrue);
    expect(isDmChannelId('01996f0e-1a2b-7c3d-8e4f-000000000000'), isFalse);
  });
}
