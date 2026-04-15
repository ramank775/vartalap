/// v3 first-launch consent screen — V3_ARCHITECTURE.md "v3 release
/// model" section.
///
/// Shown on the first launch of any v3 build until the user hits
/// "Continue and reset". The screen tells the user the rebrand is a
/// clean break (no v2 history, no v2 session) and offers them the
/// choice to proceed or keep v2 by sideloading the old APK. Tapping
/// "Continue and reset" wipes the old v2 sqflite db from disk (if
/// it exists), flips the `v3_consent_accepted` flag in
/// SharedPreferences, and jumps to the OTP flow. "Cancel" leaves the
/// consent pending so the next launch shows the same screen.
library vartalap.screens.startup.destructive_reset_consent;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';

/// SharedPreferences key — read by `main.dart` during
/// `initializeApp()` to decide whether to show this screen.
const String kV3ConsentAcceptedKey = 'v3_consent_accepted';

/// v2 sqflite db filename. The v2 `DB` class in
/// `lib/dataAccessLayer/db.dart` opened `vartalap.db` under the
/// platform default db path. We wipe it unconditionally on consent
/// accept — if the file isn't there, delete is a no-op.
const String _kV2DbFilename = 'vartalap.db';

class DestructiveResetConsentScreen extends StatefulWidget {
  /// Callback invoked after the consent flag is persisted and v2 data
  /// is wiped. `main.dart` uses it to swap the root widget to the
  /// login screen.
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

  /// Deletes the old v2 sqflite db file from the platform documents
  /// directory. Missing file is fine. Failure to delete (permission,
  /// disk full) is fine too — the v3 app opens its own db at a
  /// different path via `path_provider` regardless.
  Future<void> _wipeV2Database() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final v2File = File('${dir.path}/$_kV2DbFilename');
      if (await v2File.exists()) {
        await v2File.delete();
      }
    } catch (_) {
      // swallowed — v2 data wipe is best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = VartalapTheme.theme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 40),
              const SizedBox(height: 24),
              Text(
                'Vartalap v3 — clean relaunch',
                style: theme.appTitleStyle.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Vartalap v3 is a clean relaunch. Your previous chats and '
                'login are not carried over. Continuing will clear local '
                'v2 data and require you to sign in again. Install or '
                'keep Vartalap v2 if you need your existing history.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _working ? null : _onContinue,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  child: _working
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Continue and reset'),
                ),
              ),
              const SizedBox(height: 8),
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

  /// Cancel: don't persist anything. The next app launch will
  /// re-present this screen because `v3_consent_accepted` is still
  /// false. We also explicitly don't pop — there's no previous route
  /// to go back to. Put the app in the foreground state it was in.
  void _onCancel() {
    // Intentionally empty (per V3_ARCHITECTURE "v3 release model":
    // cancel re-shows on next launch). If the user backgrounds the
    // app and returns, they see the same screen. No action here.
  }
}
