import 'dart:math';
import 'package:flutter/material.dart';
import 'package:random_color/random_color.dart';

MaterialColor generateMaterialColor(Color color) {
  return MaterialColor(color.value, {
    50: tintColor(color, 0.9),
    100: tintColor(color, 0.8),
    200: tintColor(color, 0.6),
    300: tintColor(color, 0.4),
    400: tintColor(color, 0.2),
    500: color,
    600: shadeColor(color, 0.1),
    700: shadeColor(color, 0.2),
    800: shadeColor(color, 0.3),
    900: shadeColor(color, 0.4),
  });
}

int tintValue(int value, double factor) =>
    max(0, min((value + ((255 - value) * factor)).round(), 255));

Color tintColor(Color color, double factor) => Color.fromRGBO(
    tintValue(color.red, factor),
    tintValue(color.green, factor),
    tintValue(color.blue, factor),
    1);

int shadeValue(int value, double factor) =>
    max(0, min(value - (value * factor).round(), 255));

Color shadeColor(Color color, double factor) => Color.fromRGBO(
    shadeValue(color.red, factor),
    shadeValue(color.green, factor),
    shadeValue(color.blue, factor),
    1);

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
  return color.withOpacity(opacity);
}

/// Construct a color from a hex code string, of the format #RRGGBB.
Color hexToColor(String code) {
  return new Color(int.parse(code.substring(1, 7), radix: 16) + 0xFF000000);
}
