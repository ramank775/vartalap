/// v3 first-launch consent screen.
library vartalap.screens.startup.destructive_reset_consent;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';

const String kV3ConsentAcceptedKey = 'v3_consent_accepted';

/// v2's sqflite DB: `getDatabasesPath()/Chat`, which is the app's
/// `databases/` dir on Android (a sibling of path_provider's
/// `app_flutter/` documents dir) and Documents on iOS.
Future<File> _v2DbFile() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Platform.isAndroid ? '${docs.parent.path}/databases' : docs.path;
  return File('$dir/Chat');
}

/// True only when a v2 install left data behind; a fresh v3 install has
/// nothing to reset, so the consent screen is skipped.
Future<bool> hasV2Data() async {
  try {
    return await (await _v2DbFile()).exists();
  } catch (_) {
    return false;
  }
}

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
      final db = await _v2DbFile();
      for (final suffix in ['', '-journal', '-wal', '-shm']) {
        final f = File('${db.path}$suffix');
        if (await f.exists()) await f.delete();
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
                  'Install or keep Vartalap v2 if you need your existing '
                  'history. v3 cannot run alongside the old data, so '
                  'declining this reset will close the app.',
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
    // v3 cannot proceed without the reset — declining exits rather than
    // silently re-showing this screen (which used to be a no-op).
    SystemNavigator.pop();
  }
}
