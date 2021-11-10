import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/url_helper.dart';
import 'package:vartalap/widgets/app_logo.dart';

import 'login.dart';

class IntroductionScreen extends StatelessWidget {
  final config = ConfigStore();
  @override
  Widget build(BuildContext context) {
    final theme = VartalapTheme.theme;
    final linkTheme = theme.linkTitleStyle.copyWith(
      fontWeight: FontWeight.bold,
    );
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 340),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        child: AppLogo(
                          size: 45,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(top: 10),
                    child: Text(
                      config.packageInfo.appName,
                      style: VartalapTheme.theme.appTitleStyle.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: <TextSpan>[
                          TextSpan(
                            text: 'Read our ',
                          ),
                          TextSpan(
                            text: 'Privacy Policy. ',
                            style: linkTheme,
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => launchUrl(
                                    config.get('privacy_policy'),
                                  ),
                          ),
                          TextSpan(
                            text: 'Tap "Agree and continue" to accept the ',
                          ),
                          TextSpan(
                            text: 'Terms of Service',
                            style: linkTheme,
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => launchUrl(
                                    config.get('privacy_policy'),
                                  ),
                          )
                        ],
                        style: Theme.of(context)
                            .textTheme
                            .caption
                            ?.copyWith(fontSize: 14),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => LoginScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(14),
                          ),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              'AGREE AND CONTINUE',
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(16),
                                ),
                              ),
                              child: Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                  Text(
                    "v${config.packageInfo.version}+${config.packageInfo.buildNumber}",
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
