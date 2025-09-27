import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final Color backgroundColor;
  const AppLogo({
    super.key,
    required this.size,
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final theme = VartalapTheme.theme;
    return CircleAvatar(
      backgroundColor: backgroundColor,
      radius: size,
      child: Icon(
        Icons.chat_bubble_outline,
        color: theme.appLogoColor,
        size: size,
      ),
    );
  }
}
