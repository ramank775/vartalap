/// Settings, WhatsApp's layout (decision 154): your profile on top, then
/// one row per area — Account, Privacy, Chats, Notifications, Help —
/// each opening its own page.
library vartalap.screens.settings;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/config/sentry_config.dart';
import 'package:vartalap/screens/login/push_onboarding.dart';
import 'package:vartalap/screens/profile/profile.dart';
import 'package:vartalap/screens/qr/qr.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap/services/v2_archive.dart';
import 'package:vartalap/widgets/Inherited/app_services.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

export 'package:vartalap/config/sentry_config.dart'
    show kSentryOptInPrefKey, kSentryDsnOverridePrefKey;

const String kThemeModePrefKey = 'theme_mode';

class SettingsScreen extends StatefulWidget {
  final AuthService authService;
  final ConfigStore config;

  /// Optional: without it the header shows no photo and no QR code —
  /// both belong to [ChatService] (widget tests run without one).
  final ChatService? chatService;

  const SettingsScreen({
    super.key,
    required this.authService,
    required this.config,
    this.chatService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
    final auth = widget.authService;
    for (final changes in [
      auth.displayNameChange,
      auth.statusTextChange,
      auth.usernameChange,
    ]) {
      _subs.add(changes.listen((_) {
        if (mounted) setState(() {});
      }));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _loadAvatar() {
    widget.chatService?.ownAvatarUrl().then((url) {
      if (mounted) setState(() => _avatarUrl = url);
    });
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _openProfile() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(
        authService: widget.authService,
        config: widget.config,
        chatService: widget.chatService,
      ),
    ));
    _loadAvatar(); // a new photo is picked in there
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final auth = widget.authService;
    final chat = widget.chatService;
    final name = auth.displayName ??
        (auth.username == null ? 'Your profile' : '@${auth.username}');
    final push = AppServicesProvider.maybeOf(context)?.pushService;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: kSpaceMd, vertical: kSpaceSm),
            leading: Avator(
              text: name,
              avatarUrl: _avatarUrl,
              width: kAvatarLg,
              height: kAvatarLg,
            ),
            title: Text(name, style: text.titleLarge),
            subtitle: Text(
              auth.statusText ?? 'Hey there, I am using Vartalap',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: chat == null || auth.username == null
                ? null
                : IconButton(
                    icon: Icon(Icons.qr_code_2, color: scheme.primary),
                    tooltip: 'QR code',
                    onPressed: () => _open(
                        QrScreen(authService: auth, chatService: chat)),
                  ),
            onTap: _openProfile,
          ),
          const Divider(height: 1),
          _Row(
            icon: Icons.key_outlined,
            title: 'Account',
            subtitle: 'Log out, delete account',
            onTap: () => _open(_AccountPage(authService: auth)),
          ),
          _Row(
            icon: Icons.lock_outline,
            title: 'Privacy',
            subtitle: 'Crash reports',
            onTap: () => _open(const _PrivacyPage()),
          ),
          _Row(
            icon: Icons.chat_outlined,
            title: 'Chats',
            subtitle: 'Theme',
            onTap: () => _open(const _ChatsPage()),
          ),
          if (push != null)
            ValueListenableBuilder<PushState>(
              valueListenable: push.state,
              builder: (context, state, _) => _Row(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: switch (state) {
                  PushState.registered => 'On, through ${push.choiceLabel}',
                  PushState.choiceNeeded => 'Not set up',
                  PushState.off => 'Off',
                  PushState.disabled => 'Disabled',
                  PushState.failed => 'Registration failed, tap to retry',
                  PushState.unknown => 'Checking…',
                },
                onTap: () => state == PushState.failed
                    ? push.refresh()
                    : Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (route) => PushOnboardingScreen(
                          push: push,
                          onDone: () => Navigator.of(route).pop(),
                        ),
                      )),
              ),
            ),
          _Row(
            icon: Icons.help_outline,
            title: 'Help',
            subtitle: 'Version, open source licences',
            onTap: () => _open(_HelpPage(config: widget.config)),
          ),
        ],
      ),
    );
  }
}

/// One settings row: icon, title, a line saying what is inside.
class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: onTap,
      );
}

/// A settings sub page: a title and its rows.
class _Page extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Page({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(children: children),
      );
}

// ---------------------------------------------------------------------------
// Account — log out, delete account, the v2 archive
// ---------------------------------------------------------------------------

class _AccountPage extends StatefulWidget {
  final AuthService authService;
  const _AccountPage({required this.authService});

  @override
  State<_AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<_AccountPage> {
  bool _hasV2Data = false;

  @override
  void initState() {
    super.initState();
    hasV2Data().then((has) {
      if (mounted) setState(() => _hasV2Data = has);
    });
  }

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        // AUTH_CONTRACT §8: logout wipes the local store, and the
        // server keeps no history, so say so before it happens.
        content: const Text(
          'Your chats, messages and saved names will be erased from this '
          "phone and can't be recovered. You stay in your groups. To sign "
          'back in, you will verify your phone number again.',
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Page(
      title: 'Account',
      children: [
        if (_hasV2Data)
          ListTile(
            leading:
                Icon(Icons.download_outlined, color: scheme.onSurfaceVariant),
            title: const Text('Download v2 chats'),
            subtitle: const Text('Save a copy of your chats from the old app.'),
            onTap: () => saveV2Chats(context),
          ),
        ListTile(
          leading: Icon(Icons.logout, color: scheme.error),
          title: Text('Log out', style: TextStyle(color: scheme.error)),
          onTap: _confirmLogout,
        ),
        if (widget.authService.username != null)
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
            title: Text(
              'Delete account',
              style: TextStyle(color: scheme.error),
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  _DeleteAccountDialog(authService: widget.authService),
            ),
          ),
      ],
    );
  }
}

/// AUTH_CONTRACT §8.2: the user types "DELETE <username>" — never a
/// one-tap button, there is no recovery. Owns its controller so the
/// closing animation never sees it disposed.
class _DeleteAccountDialog extends StatefulWidget {
  final AuthService authService;
  const _DeleteAccountDialog({required this.authService});

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _typed = TextEditingController();
  bool _busy = false;
  String? _error;

  String get _phrase => 'DELETE ${widget.authService.username}';

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Signs out on success, which tears the routes down.
      await widget.authService.deleteAccount(_typed.text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AuthClientException && e.message != null
            ? e.message
            : "Couldn't reach the server. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your account and @username are deleted and this phone is '
            'signed out. Chats on this phone are erased. This cannot be '
            'undone.',
          ),
          const SizedBox(height: kSpaceMd),
          Text('Type $_phrase to confirm.'),
          TextField(
            controller: _typed,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: _phrase, errorText: _error),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: !_busy && _typed.text == _phrase ? _delete : null,
          style: TextButton.styleFrom(foregroundColor: error),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Privacy — crash reports
// ---------------------------------------------------------------------------

class _PrivacyPage extends StatefulWidget {
  const _PrivacyPage();

  @override
  State<_PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<_PrivacyPage> {
  bool _sentryOptIn = false;
  final TextEditingController _dsnController = TextEditingController();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _sentryOptIn = prefs.getBool(kSentryOptInPrefKey) ?? false;
        _dsnController.text = prefs.getString(kSentryDsnOverridePrefKey) ?? '';
      });
    });
  }

  @override
  void dispose() {
    _dsnController.dispose();
    super.dispose();
  }

  Future<void> _setSentryOptIn(bool value) async {
    await setSentryEnabled(value);
    if (!mounted) return;
    setState(() => _sentryOptIn = value);
  }

  Future<void> _setDsnOverride(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(kSentryDsnOverridePrefKey);
    } else {
      await prefs.setString(kSentryDsnOverridePrefKey, trimmed);
    }
    // Re-init with the new DSN if already opted in so the override takes
    // effect without a restart.
    if (_sentryOptIn) await setSentryEnabled(true);
  }

  Future<void> _sendTestEvent() async {
    final messenger = ScaffoldMessenger.of(context);
    await sendTestEvent();
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Test event sent to Sentry.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Page(
      title: 'Privacy',
      children: [
        SwitchListTile(
          secondary:
              Icon(Icons.bug_report_outlined, color: scheme.onSurfaceVariant),
          title: const Text('Crash reporting (Sentry)'),
          subtitle: const Text(
            'Send anonymous crash reports to help improve the app. '
            'Disabled by default.',
          ),
          value: _sentryOptIn,
          onChanged: _setSentryOptIn,
        ),
        if (_sentryOptIn) ...[
          ListTile(
            leading: Icon(Icons.send_outlined, color: scheme.onSurfaceVariant),
            title: const Text('Send test event'),
            subtitle: const Text(
              'Confirms the configured Sentry backend is receiving events.',
            ),
            onTap: _sendTestEvent,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceMd, 0, kSpaceMd, kSpaceMd),
            child: TextField(
              controller: _dsnController,
              decoration: const InputDecoration(
                labelText: 'DSN override (advanced)',
                helperText: 'Leave blank to use the built-in DSN.',
              ),
              onSubmitted: _setDsnOverride,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chats — theme
// ---------------------------------------------------------------------------

class _ChatsPage extends StatefulWidget {
  const _ChatsPage();

  @override
  State<_ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<_ChatsPage> {
  ThemeMode _themeMode = VartalapTheme.themeMode;

  Future<void> _setTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemeModePrefKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
    VartalapTheme.themeMode = mode;
    if (!mounted) return;
    setState(() => _themeMode = mode);
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
                for (final mode in const [
                  ThemeMode.light,
                  ThemeMode.dark,
                  ThemeMode.system,
                ])
                  RadioListTile<ThemeMode>(
                    title: Text(_themeLabel(mode)),
                    value: mode,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System default',
      };

  @override
  Widget build(BuildContext context) => _Page(
        title: 'Chats',
        children: [
          ListTile(
            leading: Icon(Icons.palette_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(_themeMode)),
            onTap: _openThemePicker,
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Help — version, licences, and (debug builds) the developer tools
// ---------------------------------------------------------------------------

class _HelpPage extends StatefulWidget {
  final ConfigStore config;
  const _HelpPage({required this.config});

  @override
  State<_HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<_HelpPage> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    if (widget.config.packageInfo.version.isNotEmpty) {
      _packageInfo = widget.config.packageInfo;
    } else {
      PackageInfo.fromPlatform().then((info) {
        if (mounted) setState(() => _packageInfo = info);
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = _packageInfo;
    return _Page(
      title: 'Help',
      children: [
        ListTile(
          leading: Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
          title: const Text('Version'),
          subtitle: Text(
            info == null ? '—' : '${info.version} (${info.buildNumber})',
          ),
        ),
        ListTile(
          leading:
              Icon(Icons.description_outlined, color: scheme.onSurfaceVariant),
          title: const Text('Open source licenses'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: info?.appName ?? widget.config.packageInfo.appName,
            applicationVersion:
                info == null ? null : '${info.version}+${info.buildNumber}',
          ),
        ),
        if (kDebugMode)
          ListTile(
            leading:
                Icon(Icons.group_add_outlined, color: scheme.onSurfaceVariant),
            title: const Text('Seed dummy contacts'),
            subtitle: const Text(
              'Developer, mock server only. Pre-registers 5 synthetic '
              'users so New Chat has a contact list to render.',
            ),
            onTap: _seedDummyContacts,
          ),
      ],
    );
  }
}
