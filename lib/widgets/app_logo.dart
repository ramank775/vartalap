import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({Key? key, required this.size}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = VartalapTheme.theme;
    return CircleAvatar(
      backgroundColor: Colors.white,
      radius: this.size,
      child: Icon(
        Icons.chat_bubble_outline,
        color: theme.appLogoColor,
        size: this.size,
      ),
    );
  }
}
