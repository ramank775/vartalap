import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info/package_info.dart';

class ConfigStore {
  static ConfigStore _singleTon = ConfigStore._internal();
  static String _configFile = "config.json";
  static String _licenseFile = "LICENCE";
  factory ConfigStore() {
    return _singleTon;
  }

  Map<String, dynamic> _appConfig = Map<String, dynamic>();
  PackageInfo packageInfo = PackageInfo(
    appName: 'Vartalap',
    packageName: 'com.one9x.vartalap',
    buildNumber: '',
    version: '',
  );

  ConfigStore._internal();

  Future<void> loadConfig() async {
    String rawContent = await rootBundle.loadString(_configFile);
    Map<String, dynamic> content =
        Map<String, dynamic>.from(json.decode(rawContent));
    _appConfig.addAll(content);
    packageInfo = await PackageInfo.fromPlatform();

    LicenseRegistry.addLicense(() async* {
      var license = await rootBundle.loadString(_licenseFile);
      yield LicenseEntryWithLineBreaks([packageInfo.appName], license);
    });
  }

  T get<T>(String key) {
    return _appConfig[key];
  }
}
