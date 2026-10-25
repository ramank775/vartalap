import 'package:flutter/material.dart';
import 'package:vartalap/utils/random_color.dart';

Color getColor(
  String text, {
  double opacity = 1,
  Brightness brightness = Brightness.light,
}) {
  var hash = 0;
  if (text.length == 0) return Colors.amber;
  for (var i = 0; i < text.length; i++) {
    hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    hash = hash & hash;
  }
  final _colorGenerator = RandomColor(hash);
  final colorBrightness = brightness == Brightness.dark
      ? ColorBrightness.light
      : ColorBrightness.primary;
  final colorSaturation = brightness == Brightness.dark
      ? ColorSaturation.mediumSaturation
      : ColorSaturation.mediumSaturation;
  final color = _colorGenerator.randomColor(
    colorBrightness: colorBrightness,
    colorSaturation: colorSaturation,
  );
  return color.withValues(alpha: opacity);
}
