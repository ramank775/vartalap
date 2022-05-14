import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/utils/color_helper.dart';

final Color _primaryLightColor = Colors.blue;
final Color _primaryDarkColor = Color.fromRGBO(0, 153, 122, 1);
final Color _darkBackgroundColor = hexToColor("#222831");
final _defaultLightTheme = ThemeData.light();
final ThemeData _lightTheme = _defaultLightTheme.copyWith(
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.blue,
  ),
  colorScheme: ColorScheme.fromSwatch(
    primarySwatch: Colors.blue,
  ),
  scaffoldBackgroundColor: Colors.grey[100],
  primaryColor: Colors.blue,
  visualDensity: VisualDensity.comfortable,
  backgroundColor: Colors.grey,
  iconTheme: _defaultLightTheme.iconTheme.copyWith(color: Colors.blue),
  highlightColor: Colors.blue,
  selectedRowColor: Colors.blueAccent,
  primaryColorLight: Colors.white,
);

final _defaultDarkTheme = ThemeData.dark();
final ThemeData _darkTheme = _defaultDarkTheme.copyWith(
  appBarTheme: AppBarTheme(
    backgroundColor: hexToColor("#2C394B"),
  ),
  colorScheme: ColorScheme.fromSwatch(
    primarySwatch: generateMaterialColor(_primaryDarkColor),
    brightness: Brightness.dark,
    backgroundColor: _darkBackgroundColor,
  ),
  visualDensity: VisualDensity.comfortable,
  scaffoldBackgroundColor: _darkBackgroundColor,
  selectedRowColor: _primaryDarkColor,
  primaryColorLight: hexToColor("#2C394B"),
  iconTheme: _defaultDarkTheme.iconTheme.copyWith(
    color: _primaryDarkColor,
  ),
  cardColor: _darkBackgroundColor,
);

final _appTitle = TextStyle(
  fontFamily: "sofia",
);

@immutable
class VartalapTheme {
  const VartalapTheme({
    Key? key,
    required this.appTheme,
    required this.appTitleStyle,
    required this.appLogoColor,
    required this.linkTitleStyle,
    required this.receiverColor,
    required this.senderColor,
    this.readMessage = Colors.blueAccent,
  });

  final TextStyle appTitleStyle;
  final Color appLogoColor;
  final TextStyle linkTitleStyle;
  final ThemeData appTheme;
  final Color senderColor;
  final Color receiverColor;
  final Color readMessage;

  static ThemeMode get themeMode {
    ThemeMode t = kReleaseMode ? ThemeMode.system : ThemeMode.dark;
    return t;
  }

  static VartalapTheme get darkTheme {
    return VartalapTheme(
      appTheme: _darkTheme,
      appTitleStyle: _appTitle.copyWith(
        color: _primaryDarkColor,
      ),
      appLogoColor: _primaryDarkColor,
      linkTitleStyle: TextStyle(
        color: Colors.lightBlueAccent[100],
        decoration: TextDecoration.underline,
      ),
      receiverColor: _darkTheme.primaryColorLight,
      senderColor: _primaryDarkColor,
      readMessage: _darkBackgroundColor,
    );
  }

  static VartalapTheme get lightTheme {
    return VartalapTheme(
      appTheme: _lightTheme,
      appTitleStyle: _appTitle.copyWith(
        color: _primaryLightColor,
      ),
      appLogoColor: Colors.blue,
      linkTitleStyle: TextStyle(
        color: Colors.purpleAccent[700],
        decoration: TextDecoration.underline,
      ),
      receiverColor: _lightTheme.primaryColorLight,
      senderColor: Colors.blue[300]!,
      readMessage: Colors.blue[900]!,
    );
  }

  static VartalapTheme get theme {
    var themeMode = VartalapTheme.themeMode;
    switch (themeMode) {
      case ThemeMode.dark:
        return VartalapTheme.darkTheme;
      case ThemeMode.light:
        return VartalapTheme.lightTheme;
      case ThemeMode.system:
        final brightness =
            MediaQueryData.fromWindow(WidgetsBinding.instance.window)
                .platformBrightness;
        return brightness == Brightness.dark
            ? VartalapTheme.darkTheme
            : VartalapTheme.lightTheme;
      default:
        return VartalapTheme.lightTheme;
    }
  }
}
