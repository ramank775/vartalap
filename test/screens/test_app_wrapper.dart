import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/services/vartalap_authenticated_client.dart';

/// A wrapper for widget tests that sets up all necessary dependencies.
class TestAppWrapper extends StatelessWidget {
  final Widget child;
  final VartalapAuthenticatedClient authClient;
  final Map<String, WidgetBuilder>? routes;

  const TestAppWrapper({
    super.key,
    required this.child,
    required this.authClient,
    this.routes,
  });

  static Future<void> setup() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Vartalap Test',
      packageName: 'com.one9x.vartalap.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'buildSignature',
    );

    // Mock country_codes channel
    const MethodChannel('com.neomance.country_codes')
        .setMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getDeviceLocale') {
        return 'en_IN';
      }
      return null;
    });

    await AppConfig.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<VartalapAuthenticatedClient>.value(
      value: authClient,
      child: MaterialApp(
        home: child,
        routes: routes ?? {},
      ),
    );
  }
}
