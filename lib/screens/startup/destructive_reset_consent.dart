/// v3 first-launch consent screen.
library vartalap.screens.startup.destructive_reset_consent;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';

const String kV3ConsentAcceptedKey = 'v3_consent_accepted';

class DestructiveResetConsentScreen extends StatefulWidget {
  final VoidCallback onAccepted;

  const DestructiveResetConsentScreen({
    super.key,
    required this.onAccepted,
  });

  @override
  State<DestructiveResetConsentScreen> createState() =>
      _DestructiveResetConsentScreenState();
}

class _DestructiveResetConsentScreenState
    extends State<DestructiveResetConsentScreen> {
  bool _working = false;

  Future<void> _onContinue() async {
    setState(() => _working = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kV3ConsentAcceptedKey, true);
      if (!mounted) return;
      widget.onAccepted();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kSpaceLg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const AppLogo(size: 40),
              const SizedBox(height: kSpaceLg),
              Text(
                'Vartalap v3',
                style: textTheme.headlineMedium?.copyWith(
                  color: scheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: kSpaceSm),
              Text(
                'Clean relaunch',
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: kSpaceLg),
              Container(
                padding: const EdgeInsets.all(kSpaceMd),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(kRadiusMd),
                ),
                child: Text(
                  'Vartalap v3 is a clean relaunch. Your previous chats and '
                  'login are not carried over, so you will need to sign in '
                  'again.\n\n'
                  'Your v2 chats are kept on this device. You can download '
                  'a copy any time from Settings.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                    height: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _working ? null : _onContinue,
                  child: _working
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
