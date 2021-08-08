import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:vartalap/widgets/avator_letter.dart';
import 'package:vartalap/utils/color_helper.dart';

class Avator extends StatelessWidget {
  final String text;
  final double _opacity = 0.65;
  final double width;
  final double height;
  Avator({
    Key? key,
    required this.text,
    required this.width,
    required this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: this.width,
      height: this.height,
      child: AvatarLetter(
        backgroundColor: getColor(this.text, opacity: this._opacity),
        backgroundColorHex: null,
        text: this.text,
        numberLetters: 2,
        upperCase: true,
        letterType: LetterType.Circular,
        textColor: Colors.white,
        textColorHex: null,
      ),
    );
  }
}
