import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vartalap/utils/random_color.dart';

MaterialColor generateMaterialColor(Color color) {
  return MaterialColor(color.toARGB32(), {
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
    tintValue((color.r * 255.0).round(), factor),
    tintValue((color.g * 255.0).round(), factor),
    tintValue((color.b * 255.0).round(), factor),
    1);

int shadeValue(int value, double factor) =>
    max(0, min(value - (value * factor).round(), 255));

Color shadeColor(Color color, double factor) => Color.fromRGBO(
    shadeValue((color.r * 255.0).round(), factor),
    shadeValue((color.g * 255.0).round(), factor),
    shadeValue((color.b * 255.0).round(), factor),
    1);

class Range {
  const Range(this.start, this.end);

  const Range.staticValue(int value)
      : start = value,
        end = value;
  const Range.zero()
      : start = 0,
        end = 0;

  final int start;
  final int end;

  Range operator +(Range range) {
    return Range((start + range.start) ~/ 2, end);
  }

  bool contain(int value) {
    return value >= start && value <= end;
  }

  int randomWithin(Random random) {
    return (start + random.nextDouble() * (end - start)).round();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Range &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}

Color getColor(
  String text, {
  double opacity = 1,
  Brightness brightness = Brightness.light,
}) {
  var hash = 0;
  if (text.isEmpty) return Colors.amber;
  for (var i = 0; i < text.length; i++) {
    hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    hash = hash & hash;
  }
  final colorGenerator = RandomColor(hash);
  final colorBrightness = brightness == Brightness.dark
      ? ColorBrightness.light
      : ColorBrightness.primary;
  final colorSaturation = brightness == Brightness.dark
      ? ColorSaturation.mediumSaturation
      : ColorSaturation.mediumSaturation;
  final color = colorGenerator.randomColor(
    colorBrightness: colorBrightness,
    colorSaturation: colorSaturation,
  );
  return color.withValues(alpha: opacity);
}

/// Construct a color from a hex code string, of the format #RRGGBB.
Color hexToColor(String code) {
  return Color(int.parse(code.substring(1, 7), radix: 16) + 0xFF000000);
}
