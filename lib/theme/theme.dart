import 'package:flutter/material.dart';
import 'package:vartalap/utils/color_helper.dart';

class ThemeInfo {
  static ThemeMode get themeMode {
    ThemeMode t = ThemeMode.system;
    return t;
  }

  static var defaultLightTheme = ThemeData.light();
  static ThemeData lightTheme = defaultLightTheme.copyWith(
    colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue),
    scaffoldBackgroundColor: Colors.grey[100],
    primaryColor: Colors.blue,
    accentColor: Colors.blue[300],
    visualDensity: VisualDensity.comfortable,
    backgroundColor: Colors.grey,
    iconTheme: defaultLightTheme.iconTheme.copyWith(color: Colors.blue),
    highlightColor: Colors.blue,
    selectedRowColor: Colors.blueAccent,
    primaryColorLight: Colors.white,
  );

  static var defaultDarkTheme = ThemeData.dark();
  static ThemeData darkTheme = defaultDarkTheme.copyWith(
    colorScheme: ColorScheme.fromSwatch(
      primarySwatch: generateMaterialColor(
        Color.fromRGBO(0, 153, 122, 1),
      ),
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    backgroundColor: defaultDarkTheme.backgroundColor,
    scaffoldBackgroundColor: Colors.grey[850],
    accentColor: Color.fromRGBO(0, 153, 122, 1),
    selectedRowColor: Color.fromRGBO(27, 133, 133, 1),
    primaryColorLight: Colors.grey[700],
    iconTheme: defaultDarkTheme.iconTheme.copyWith(
      color: Color.fromRGBO(0, 153, 122, 1),
    ),
  );

  // Green theme
  // static ThemeData darkTheme = ThemeData.dark().copyWith(
  //   colorScheme: ColorScheme.fromSwatch(
  //     primarySwatch: generateMaterialColor(Color.fromRGBO(24, 99, 99, 1)),
  //   ),
  //   accentColor: Color.fromRGBO(24, 99, 99, 1),
  //   primaryColor: Color.fromRGBO(24, 99, 99, 1),
  //   visualDensity: VisualDensity.comfortable,
  //   backgroundColor: Color.fromRGBO(27, 70, 70, 1),
  //   scaffoldBackgroundColor: Color.fromRGBO(27, 70, 70, 1),
  //   iconTheme: ThemeData.dark().iconTheme.copyWith(color: Colors.white60),
  //   selectedRowColor: Color.fromRGBO(27, 133, 133, 1),
  //   primaryColorLight: Color.fromRGBO(0, 128, 128, 1),
  //   cardColor: Color.fromRGBO(24, 99, 99, 1),
  // );

  static TextStyle get appTitle {
    // var color = themeMode == ThemeMode.dark
    //     ? Color.fromRGBO(174, 224, 81, 0.7)
    //     : Colors.white;
    var color = Colors.white;
    return TextStyle(
      color: color,
      fontFamily: "sofia",
    );
  }
}
