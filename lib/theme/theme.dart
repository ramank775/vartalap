import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:vartalap/utils/color_helper.dart';

final _defaultLightTheme = ThemeData.light();
final ThemeData _lightTheme = _defaultLightTheme.copyWith(
  colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue),
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
  colorScheme: ColorScheme.fromSwatch(
    primarySwatch: generateMaterialColor(
      Color.fromRGBO(0, 153, 122, 1),
    ),
    brightness: Brightness.dark,
    backgroundColor: Colors.grey[850],
  ),
  visualDensity: VisualDensity.adaptivePlatformDensity,
  scaffoldBackgroundColor: Colors.grey[850],
  selectedRowColor: Color.fromRGBO(27, 133, 133, 1),
  primaryColorLight: Colors.grey[700],
  iconTheme: _defaultDarkTheme.iconTheme.copyWith(
    color: Color.fromRGBO(0, 153, 122, 1),
  ),
);

final _appTitle = TextStyle(
  fontFamily: "sofia",
);

final Color _primaryLightColor = Colors.blue;
final Color _primaryDarkColor = Color.fromRGBO(0, 153, 122, 1);

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
  });

  final TextStyle appTitleStyle;
  final Color appLogoColor;
  final TextStyle linkTitleStyle;
  final ThemeData appTheme;
  final Color senderColor;
  final Color receiverColor;

  static ThemeMode get themeMode {
    ThemeMode t = ThemeMode.system;
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
        color: Colors.deepPurple[700],
        decoration: TextDecoration.underline,
      ),
      receiverColor: _darkTheme.primaryColorLight,
      senderColor: _primaryDarkColor,
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
        color: Colors.deepPurple[700],
        decoration: TextDecoration.underline,
      ),
      receiverColor: _lightTheme.primaryColorLight,
      senderColor: Colors.blue[300]!,
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
            MediaQueryData.fromWindow(WidgetsBinding.instance!.window)
                .platformBrightness;
        return brightness == Brightness.dark
            ? VartalapTheme.darkTheme
            : VartalapTheme.lightTheme;
      default:
        return VartalapTheme.lightTheme;
    }
  }
}
