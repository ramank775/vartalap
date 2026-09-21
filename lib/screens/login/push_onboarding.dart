/// One-screen prompt shown after the username step when the ntfy app —
/// the pinned UnifiedPush distributor (V3_ARCHITECTURE decision 6) — is
/// not installed. Without it Vartalap only receives while it is open.
///
/// Shown once; "Later" is a real answer. Settings → Push notifications
/// is the way back.
library vartalap.screens.login.push_onboarding;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap/theme/theme.dart';

/// SharedPreferences flag: the prompt has been answered once.
const String kPushPromptSeenKey = 'push_prompt_seen';

class PushOnboardingScreen extends StatefulWidget {
  /// Called for both buttons — the prompt is one-shot either way.
  final VoidCallback onDone;

  const PushOnboardingScreen({super.key, required this.onDone});

  @override
  State<PushOnboardingScreen> createState() => _PushOnboardingScreenState();
}

class _PushOnboardingScreenState extends State<PushOnboardingScreen> {
  @override
  void initState() {
    super.initState();
    // API 33+ runtime grant, asked at the one point in the flow where
    // the user is being told what notifications are for.
    Permission.notification.request().ignore();
  }

  Future<void> _install() async {
    await launchUrl(
      Uri.parse(kNtfyInstallUrl),
      mode: LaunchMode.externalApplication,
    );
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kSpaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: kSpaceXl),
              Icon(Icons.notifications_active_outlined,
                  size: 64, color: scheme.primary),
              const SizedBox(height: kSpaceLg),
              Text(
                'Install ntfy to receive messages when Vartalap is closed',
                style: text.headlineSmall,
              ),
              const SizedBox(height: kSpaceMd),
              Text(
                'Vartalap has no Google services. It uses ntfy, a small '
                'open-source app, to wake it up when a message arrives. '
                'Without ntfy you only receive messages while Vartalap is '
                'open.',
                style: text.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _install,
                child: const Text('Install'),
              ),
              const SizedBox(height: kSpaceSm),
              TextButton(
                onPressed: widget.onDone,
                child: const Text('Later'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
