import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/url_helper.dart';
import 'package:vartalap/widgets/app_logo.dart';

import 'package:vartalap/screens/login/login.dart';

class IntroductionScreen extends StatelessWidget {
  final AuthService authService;
  final config = ConfigStore();
  IntroductionScreen({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kSpaceLg),
          child: Column(
            children: [
              // Top section: logo + name
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLogo(size: 48),
                    const SizedBox(height: kSpaceMd),
                    Text(
                      config.packageInfo.appName,
                      style: textTheme.headlineMedium?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              // Bottom section: terms + button + version
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          children: [
                            const TextSpan(text: 'Read our '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => launchUrl(
                                      ConfigStore.privacyPolicyUrl,
                                    ),
                            ),
                            const TextSpan(
                                text:
                                    '. Tap "Agree and continue" to accept the '),
                            TextSpan(
                              text: 'Terms of Service',
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => launchUrl(
                                      ConfigStore.privacyPolicyUrl,
                                    ),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: kSpaceLg),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) =>
                                  LoginScreen(authService: authService),
                            ),
                          );
                        },
                        child: const Text('Agree and continue'),
                      ),
                    ),
                    const SizedBox(height: kSpaceMd),
                    Text(
                      'v${config.packageInfo.version}+${config.packageInfo.buildNumber}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
