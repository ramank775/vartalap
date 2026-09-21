/// Sentry opt-in wiring per docs/V3_ARCHITECTURE.md decision 8.
///
/// DSN is compiled in via `--dart-define=SENTRY_DSN` but the SDK stays
/// uninitialized — zero events, nothing phoning home — until the user
/// flips the opt-in toggle in Settings. An opted-in user may override the
/// DSN (Settings, advanced) to point at their own self-hosted instance.
library vartalap.config.sentry_config;

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config_store.dart';

const String kSentryOptInPrefKey = 'sentry_opt_in';
const String kSentryDsnOverridePrefKey = 'sentry_dsn_override';

/// User's DSN override (Settings, advanced) if set, else the compiled-in
/// build-time DSN.
Future<String> effectiveSentryDsn() async {
  final prefs = await SharedPreferences.getInstance();
  final override = prefs.getString(kSentryDsnOverridePrefKey);
  if (override != null && override.isNotEmpty) return override;
  return ConfigStore.sentryDsn;
}

/// Reads the stored opt-in pref and, if on and a DSN is available,
/// initializes Sentry. Called once at app boot (main.dart); a no-op when
/// the user hasn't opted in or no DSN is configured — nothing is
/// initialized and no events can be sent.
Future<void> initSentryIfOptedIn() async {
  final prefs = await SharedPreferences.getInstance();
  final optedIn = prefs.getBool(kSentryOptInPrefKey) ?? false;
  if (!optedIn) return;
  final dsn = await effectiveSentryDsn();
  if (dsn.isEmpty) return;
  await SentryFlutter.init((options) => options.dsn = dsn);
}

/// Settings toggle handler — starts or stops the SDK at runtime, no app
/// restart needed.
Future<void> setSentryEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kSentryOptInPrefKey, enabled);
  if (!enabled) {
    await Sentry.close();
    return;
  }
  final dsn = await effectiveSentryDsn();
  if (dsn.isEmpty) return;
  await SentryFlutter.init((options) => options.dsn = dsn);
}

/// "Send test event" Settings tile action.
Future<SentryId> sendTestEvent() {
  return Sentry.captureMessage('Vartalap test event from Settings');
}
