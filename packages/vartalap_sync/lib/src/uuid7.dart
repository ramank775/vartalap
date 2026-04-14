import 'dart:math';
import 'dart:typed_data';

/// UUIDv7 generator with embedded user_id + device slot.
///
/// SPIKE_B_SYNC.md §4 layout:
/// ```
///  48 bits ms | 4 bits ver | 12 bits counter | 2 bits variant |
///  36 bits user_id | 4 bits device | 18 bits random
/// ```
///
/// Wire encoding: standard UUID string (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`).
///
/// Note: the server validates `op_id bits[62..26] == authenticated user_id`
/// on every inbound op (SYNC_PROTOCOL.md §3). Keep the bit layout in sync
/// with the server's validator — any drift surfaces as `prefix_mismatch`.
class Uuid7Gen {
  final int userIdBits; // 36-bit user_id
  final int deviceSlot; // 0..15; always 0 for v3.0 single-device
  final Random _rng;

  int _lastMs = 0;
  int _counter = 0;

  Uuid7Gen({
    required this.userIdBits,
    this.deviceSlot = 0,
    Random? rng,
  })  : assert(userIdBits >= 0 && userIdBits < (1 << 36)),
        assert(deviceSlot >= 0 && deviceSlot < 16),
        _rng = rng ?? Random.secure();

  /// Parses the 9-hex-char `user_id` from AUTH_CONTRACT §2 and returns
  /// the 36-bit int for [Uuid7Gen.userIdBits].
  static int parseUserIdHex(String hex) {
    if (hex.length != 9) {
      throw ArgumentError('user_id must be 9 hex chars, got "$hex"');
    }
    return int.parse(hex, radix: 16);
  }

  String next({required int nowMs}) {
    if (nowMs == _lastMs) {
      _counter = (_counter + 1) & 0xFFF;
    } else {
      _counter = 0;
      _lastMs = nowMs;
    }
    final bytes = Uint8List(16);

    // 48 bits ms
    bytes[0] = (nowMs >> 40) & 0xFF;
    bytes[1] = (nowMs >> 32) & 0xFF;
    bytes[2] = (nowMs >> 24) & 0xFF;
    bytes[3] = (nowMs >> 16) & 0xFF;
    bytes[4] = (nowMs >> 8) & 0xFF;
    bytes[5] = nowMs & 0xFF;

    // 4 bits version (7) | 12 bits counter
    bytes[6] = 0x70 | ((_counter >> 8) & 0x0F);
    bytes[7] = _counter & 0xFF;

    // 2 bits variant (10) | top 6 bits of user_id (of 36)
    bytes[8] = 0x80 | ((userIdBits >> 30) & 0x3F);
    // Next 8 bits of user_id
    bytes[9] = (userIdBits >> 22) & 0xFF;
    bytes[10] = (userIdBits >> 14) & 0xFF;
    bytes[11] = (userIdBits >> 6) & 0xFF;
    // Remaining 6 bits of user_id | 2 high bits of device slot
    bytes[12] = ((userIdBits & 0x3F) << 2) | ((deviceSlot >> 2) & 0x03);
    // 2 low bits of device slot | 6 bits random (top of 18)
    final r = _rng.nextInt(1 << 18);
    bytes[13] = ((deviceSlot & 0x03) << 6) | ((r >> 12) & 0x3F);
    bytes[14] = (r >> 4) & 0xFF;
    bytes[15] = (r & 0x0F) << 4;

    return _formatUuid(bytes);
  }

  static String _formatUuid(Uint8List b) {
    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    final buf = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buf.write(hex(b[i]));
      if (i == 3 || i == 5 || i == 7 || i == 9) buf.write('-');
    }
    return buf.toString();
  }
}
