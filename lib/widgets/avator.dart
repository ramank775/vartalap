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
    if (text.isEmpty) return '?';
    final parts = text.trim().split(RegExp(r'[\s_]+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return text[0].toUpperCase();
  }
}
