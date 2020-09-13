import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class ConfigStore {
  static ConfigStore _singleTon = ConfigStore._internal();
  static String _configFile = "config.json";
  factory ConfigStore() {
    return _singleTon;
  }

  Map<String, dynamic> _appConfig = Map<String, dynamic>();

  ConfigStore._internal();

  Future<void> loadConfig() async {
    String rawContent = await rootBundle.loadString(_configFile);
    Map<String, dynamic> content =
        Map<String, dynamic>.from(json.decode(rawContent));
    _appConfig.addAll(content);
  }

  T get<T>(String key) {
    return _appConfig[key];
  }
}
