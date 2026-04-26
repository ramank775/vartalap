/// Settings screen — appearance, privacy, account, about.
library vartalap.screens.settings;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
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
          RadioGroup<ThemeMode>(
            groupValue: _themeMode,
            onChanged: (mode) {
              if (mode == null) return;
              Navigator.of(ctx).pop();
              _setTheme(mode);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in const [
                  (ThemeMode.light, 'Light'),
                  (ThemeMode.dark, 'Dark'),
                  (ThemeMode.system, 'System default'),
                ])
                  RadioListTile<ThemeMode>(
                    title: Text(entry.$2),
                    value: entry.$1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Debug-only. Two-step:
  ///   1. POST `/v3.0/_dev/seed-users` so the mock server has the
  ///      synthetic users registered (server-side discovery target).
  ///   2. Insert each returned user into the device address book so
  ///      the normal New Chat flow (read phones → SHA-256 → POST hashes
  ///      → match) finds them. Skips entries whose phone is already in
  ///      the book.
  ///
  /// Both steps are mock-only; the endpoint exists only on the dev
  /// server and the contact rows live in the emulator's address book.
  /// Release builds never see the action.
  Future<void> _seedDummyContacts() async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(ConfigStore.apiUrl).resolve('/v3.0/_dev/seed-users');

    List<Map<String, dynamic>> users;
    try {
      final resp = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'count': 5}),
      );
      if (!mounted) return;
      if (resp.statusCode != 200) {
        messenger.showSnackBar(
          SnackBar(content: Text('Seed failed: HTTP ${resp.statusCode}')),
        );
        return;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      users = (body['users'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Seed error: $e')));
      return;
    }

    // Make sure we have contacts permission before inserting. The user
    // may have only granted READ via the New Chat flow; insertion needs
    // write access too — permission_handler treats Permission.contacts
    // as the combined READ+WRITE on Android.
    final perm = await Permission.contacts.request();
    if (!mounted) return;
    if (!perm.isGranted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Contacts permission denied.')),
      );
      return;
    }

    // Index existing contacts by phone so the seed is idempotent —
    // re-tapping the button doesn't create dupes.
    final existing = await FlutterContacts.getAll(
      properties: {ContactProperty.phone},
    );
    final existingPhones = <String>{
      for (final c in existing)
        for (final p in c.phones)
          (p.normalizedNumber?.isNotEmpty ?? false)
              ? p.normalizedNumber!
              : p.number.replaceAll(RegExp(r'\s+'), ''),
    };

    int created = 0;
    for (final u in users) {
      final phone = u['phone'] as String?;
      final displayName = u['display_name'] as String? ??
          u['username'] as String? ??
          'Dummy';
      if (phone == null || existingPhones.contains(phone)) continue;
      final contact = Contact(
        name: Name(first: displayName),
        phones: [Phone(number: phone)],
      );
      try {
        await FlutterContacts.create(contact);
        created++;
      } catch (e) {
        debugPrint('Seed contact insert failed for $phone: $e');
      }
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
        'Seeded ${users.length} on server, '
        'added $created to address book.',
      ),
    ));
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
          if (kDebugMode) ...[
            const Divider(height: 1),
            _SectionHeader(label: 'Developer', scheme: scheme,
                textTheme: textTheme),
            ListTile(
              leading: Icon(Icons.group_add_outlined,
                  color: scheme.onSurfaceVariant),
              title: const Text('Seed dummy contacts'),
              subtitle: const Text(
                'Mock server only. Pre-registers 5 synthetic users so '
                'New Chat has a contact list to render.',
              ),
              onTap: _seedDummyContacts,
            ),
          ],
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
