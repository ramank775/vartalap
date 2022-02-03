import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final Color backgroundColor;
  const AppLogo({
    Key? key,
    required this.size,
    this.backgroundColor = Colors.white,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = VartalapTheme.theme;
    return CircleAvatar(
      backgroundColor: this.backgroundColor,
      radius: this.size,
      child: Icon(
        Icons.chat_bubble_outline,
        color: theme.appLogoColor,
        size: this.size,
      ),
    );
  }
}
