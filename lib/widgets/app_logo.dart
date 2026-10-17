import 'package:flutter/material.dart';

/// The launcher icon drawn in Flutter: a white bubble on the launcher's
/// green (`mipmap-*/ic_launcher_background`, #156B54), so the intro and
/// login screens match the icon the user just tapped.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 2,
      height: size * 2,
      decoration: BoxDecoration(
        color: const Color(0xFF156B54),
        borderRadius: BorderRadius.circular(size * 0.4),
      ),
      child: Icon(
        Icons.chat_bubble_outline_rounded,
        color: Colors.white,
        size: size,
      ),
    );
  }
}
