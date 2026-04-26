import 'package:flutter/material.dart';
import 'package:vartalap/utils/color_helper.dart';

class Avator extends StatelessWidget {
  final String text;
  final double width;
  final double height;

  const Avator({
    super.key,
    required this.text,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bgColor = getColor(text, opacity: 0.8, brightness: brightness);
    final initials = _initials(text);
    // Scale font to ~40% of avatar size for readability.
    final fontSize = width * 0.4;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
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
