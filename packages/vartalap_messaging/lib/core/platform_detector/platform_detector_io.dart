import 'dart:io';

import 'package:vartalap_messaging/core/platform_detector/platform_detector.dart';

PlatformType get currentPlatform {
  if (Platform.isAndroid) return PlatformType.android;
  if (Platform.isFuchsia) return PlatformType.fuchsia;
  if (Platform.isMacOS) return PlatformType.macOS;
  if (Platform.isLinux) return PlatformType.linux;
  if (Platform.isIOS) return PlatformType.ios;
  if (Platform.isWindows) return PlatformType.windows;
  return PlatformType.android;
}

bool get isFlutterTestEnvironment {
  return Platform.environment.containsKey('FLUTTER_TEST');
}
