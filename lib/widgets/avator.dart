import 'package:flutter/material.dart';
import 'package:vartalap/widgets/avator_letter.dart';
import 'package:vartalap/utils/color_helper.dart';

class Avator extends StatelessWidget {
  final String text;
  final double _opacity = 0.65;
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
    return SizedBox(
      width: width,
      height: height,
      child: AvatarLetter(
        backgroundColor: getColor(
          text,
          opacity: _opacity,
          brightness: brightness,
        ),
        text: text,
        numberLetters: 2,
        upperCase: true,
        letterType: LetterType.circular,
        textColor: Colors.white,
        fontSize: 12,
      ),
    );
  }
}
