/// Settings screen — appearance, privacy, account, about.
library vartalap.screens.settings;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';

const String kThemeModePrefKey = 'theme_mode';
const String kSentryOptInPrefKey = 'sentry_opt_in';

class SettingsScreen extends StatefulWidget {
  final AuthService authService;
  final ConfigStore config;

  const SettingsScreen({
    super.key,
    required this.authService,
    required this.config,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ThemeMode _themeMode = VartalapTheme.themeMode;
  bool _sentryOptIn = false;
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = switch (prefs.getString(kThemeModePrefKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final optIn = prefs.getBool(kSentryOptInPrefKey) ?? false;
    PackageInfo info;
    if (widget.config.packageInfo.version.isNotEmpty) {
      info = widget.config.packageInfo;
    } else {
      info = await PackageInfo.fromPlatform();
    }
    if (!mounted) return;
    setState(() {
      _themeMode = mode;
      _sentryOptIn = optIn;
      _packageInfo = info;
    });
  }

  Future<void> _setTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(kThemeModePrefKey, value);
    VartalapTheme.themeMode = mode;
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  Future<void> _setSentryOptIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kSentryOptInPrefKey, value);
    if (!mounted) return;
    setState(() => _sentryOptIn = value);
  }

  void _openThemePicker() {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final entry in const [
            (ThemeMode.light, 'Light'),
            (ThemeMode.dark, 'Dark'),
            (ThemeMode.system, 'System default'),
          ])
            RadioListTile<ThemeMode>(
              title: Text(entry.$2),
              value: entry.$1,
              groupValue: _themeMode,
              onChanged: (mode) {
                if (mode == null) return;
                Navigator.of(ctx).pop();
                _setTheme(mode);
              },
            ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to verify your phone number to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.authService.logout();
            },
            child: Text(
              'Log out',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final info = _packageInfo;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(label: 'Appearance', scheme: scheme,
              textTheme: textTheme),
          ListTile(
            leading: Icon(Icons.palette_outlined,
                color: scheme.onSurfaceVariant),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(_themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openThemePicker,
          ),
          const Divider(height: 1),
          _SectionHeader(label: 'Privacy', scheme: scheme,
              textTheme: textTheme),
          SwitchListTile(
            secondary: Icon(Icons.bug_report_outlined,
                color: scheme.onSurfaceVariant),
            title: const Text('Crash reporting (Sentry)'),
            subtitle: const Text(
              'Send anonymous crash reports to help improve the app. '
              'Disabled by default.',
            ),
            value: _sentryOptIn,
            onChanged: _setSentryOptIn,
          ),
          const Divider(height: 1),
          _SectionHeader(label: 'Account', scheme: scheme,
              textTheme: textTheme),
          ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text(
              'Log out',
              style: TextStyle(color: scheme.error),
            ),
            onTap: _confirmLogout,
          ),
          const Divider(height: 1),
          _SectionHeader(label: 'About', scheme: scheme,
              textTheme: textTheme),
          ListTile(
            leading: Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
            title: const Text('Version'),
            subtitle: Text(
              info == null
                  ? '—'
                  : '${info.version} (${info.buildNumber})',
            ),
          ),
          ListTile(
            leading: Icon(Icons.description_outlined,
                color: scheme.onSurfaceVariant),
            title: const Text('Open source licenses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: info?.appName ?? widget.config.packageInfo.appName,
              applicationVersion: info == null
                  ? null
                  : '${info.version}+${info.buildNumber}',
            ),
          ),
          const SizedBox(height: kSpaceXl),
        ],
      ),
    );
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System default',
      };
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _SectionHeader({
    required this.label,
    required this.scheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kSpaceMd,
        kSpaceMd,
        kSpaceMd,
        kSpaceSm,
      ),
      child: Text(
        label,
        style: textTheme.labelLarge?.copyWith(color: scheme.primary),
      ),
    );
  }
}
