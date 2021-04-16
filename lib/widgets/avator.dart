import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:vartalap/widgets/avator_letter.dart';

class Avator extends StatelessWidget {
  final String text;
  final double _opacity = 1;
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
        backgroundColor: this.getColor(),
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

  Color getColor() {
    var hash = 0;
    if (this.text.length == 0) return Colors.amber;
    for (var i = 0; i < this.text.length; i++) {
      hash = this.text.codeUnitAt(i) + ((hash << 5) - hash);
      hash = hash & hash;
    }
    var rgb = [0, 0, 0];
    for (var i = 0; i < 3; i++) {
      var value = (hash >> (i * 8)) & 255;
      rgb[i] = value;
    }
    return Color.fromRGBO(rgb[0], rgb[1], rgb[2], this._opacity);
  }
}
