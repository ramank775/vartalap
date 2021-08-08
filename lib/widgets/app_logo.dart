import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({Key? key, required this.size}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return CircleAvatar(
      backgroundColor: Colors.white,
      radius: this.size,
      child: Icon(
        Icons.chat_bubble_outline,
        color: theme.primaryColor,
        size: this.size,
      ),
    );
  }
}
