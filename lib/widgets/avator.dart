import 'package:flutter/material.dart';
import 'package:vartalap/utils/color_helper.dart';

/// One avatar for people and groups alike.
///
/// Photo when [avatarUrl] is set, otherwise the generated fallback:
/// initials for a person, the group glyph for a group (frame a1 —
/// "groups get the filled glyph avatar", so a group row reads as a
/// group before you read its name). Both sit on a colour seeded from
/// [seed], which should be the stable channel or user id: renaming a
/// group or saving a contact must not change its colour.
class Avator extends StatelessWidget {
  final String text;
  final double width;
  final double height;

  /// Remote photo. Null or empty falls straight through to the
  /// generated avatar; a load error or a slow load shows it too, so
  /// there is never a blank hole in a list row.
  final String? avatarUrl;

  /// Colour seed. Defaults to [text] for callers that have no id.
  final String? seed;

  /// Renders the group glyph instead of initials when there is no
  /// photo.
  final bool isGroup;

  const Avator({
    super.key,
    required this.text,
    required this.width,
    required this.height,
    this.avatarUrl,
    this.seed,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final fallback = _generated(context);
    if (url == null || url.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        // Both the in-flight and the failed case land on the generated
        // avatar rather than a spinner or a broken-image glyph.
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
        errorBuilder: (context, _, __) => fallback,
      ),
    );
  }

  Widget _generated(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bgColor =
        getColor(seed ?? text, opacity: 0.8, brightness: brightness);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
      ),
      alignment: Alignment.center,
      child: isGroup
          ? Icon(
              Icons.groups_rounded,
              // Slightly larger than the text cap-height so the glyph
              // reads at 32px as well as at 80px.
              size: width * 0.55,
              color: Colors.white,
            )
          : Text(
              _initials(text),
              style: TextStyle(
                color: Colors.white,
                // Scale font to ~40% of avatar size for readability.
                fontSize: width * 0.4,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
    );
  }

  String _initials(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'[\s_]+'));
    if (parts.length >= 2 &&
        _isLetterOrDigit(parts[0][0]) &&
        _isLetterOrDigit(parts[1][0])) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    // Find the first letter or digit; skips leading symbols like
    // "+" on phone numbers so "+919876543210" becomes "9", not "+".
    for (final rune in trimmed.runes) {
      final ch = String.fromCharCode(rune);
      if (_isLetterOrDigit(ch)) return ch.toUpperCase();
    }
    return trimmed[0].toUpperCase();
  }

  static bool _isLetterOrDigit(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    // 0-9
    if (code >= 0x30 && code <= 0x39) return true;
    // A-Z
    if (code >= 0x41 && code <= 0x5A) return true;
    // a-z
    if (code >= 0x61 && code <= 0x7A) return true;
    // Letters outside ASCII (broad approximation): anything above 0x7F
    // that isn't a common ASCII symbol is probably a letter (e.g. á, ñ,
    // 你). Good enough for an avatar initial.
    return code > 0x7F;
  }
}
