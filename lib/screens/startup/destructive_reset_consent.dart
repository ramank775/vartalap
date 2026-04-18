/// v3 first-launch consent screen.
library vartalap.screens.startup.destructive_reset_consent;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';

const String kV3ConsentAcceptedKey = 'v3_consent_accepted';
const String _kV2DbFilename = 'vartalap.db';

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
      await _wipeV2Database();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kV3ConsentAcceptedKey, true);
      if (!mounted) return;
      widget.onAccepted();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _wipeV2Database() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final v2File = File('${dir.path}/$_kV2DbFilename');
      if (await v2File.exists()) {
        await v2File.delete();
      }
    } catch (_) {}
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
                  'login are not carried over. Continuing will clear local '
                  'v2 data and require you to sign in again.\n\n'
                  'Install or keep Vartalap v2 if you need your existing history.',
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
                      : const Text('Continue and reset'),
                ),
              ),
              const SizedBox(height: kSpaceSm),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _working ? null : _onCancel,
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onCancel() {
    // Intentionally empty — cancel re-shows on next launch.
  }
}
