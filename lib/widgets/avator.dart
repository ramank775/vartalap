import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vartalap/widgets/avator_letter.dart';
import 'package:vartalap/utils/color_helper.dart';

class Avator extends StatelessWidget {
  final String text;
  final String? image;
  final double _opacity = 0.65;
  final double width;
  final double height;
  final double fontSize;
  const Avator({
    super.key,
    required this.text,
    this.image,
    required this.width,
    required this.height,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    Widget child;
    if (image != null && image!.isNotEmpty) {
      if (image!.startsWith('http')) {
        child = Image.network(
          image!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildLetterAvatar(brightness),
        );
      } else {
        child = Image.file(
          File(image!),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildLetterAvatar(brightness),
        );
      }
    } else {
      child = _buildLetterAvatar(brightness);
    }

    return SizedBox(
      width: width,
      height: height,
      child: ClipOval(child: child),
    );
  }

  Widget _buildLetterAvatar(Brightness brightness) {
    return AvatarLetter(
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
      fontSize: fontSize,
    );
  }
}
