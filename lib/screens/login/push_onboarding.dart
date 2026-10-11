/// The push chooser (DECISIONS 120): Google Play services (gms builds on
/// phones with Play services), each installed push app — or a link to
/// get one — and "Not now". Nothing is pre-selected.
///
/// First-run onboarding shows it once after the username step, while
/// there is a question to ask ([PushState.choiceNeeded]); "Not now" is a
/// real answer. Settings → Push notifications opens the same screen to
/// change the answer.
library vartalap.screens.login.push_onboarding;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap/theme/theme.dart';

/// SharedPreferences flag: the prompt has been answered once.
const String kPushPromptSeenKey = 'push_prompt_seen';

/// Where "Get ntfy" goes: whichever store answers `market://` on this
/// phone (Play, F-Droid, Aurora, …), else F-Droid's web page.
const String kNtfyStoreUrl = 'market://details?id=io.heckel.ntfy';
const String kNtfyFdroidUrl = 'https://f-droid.org/packages/io.heckel.ntfy/';

/// The push-app option while none is installed: picking it opens a store.
const String _getPushApp = 'get-push-app';

class PushOnboardingScreen extends StatefulWidget {
  final PushService push;

  /// Called once the user has answered — a push method or "Not now".
  final VoidCallback onDone;

  const PushOnboardingScreen({
    super.key,
    required this.push,
    required this.onDone,
  });

  @override
  State<PushOnboardingScreen> createState() => _PushOnboardingScreenState();
}

class _PushOnboardingScreenState extends State<PushOnboardingScreen>
    with WidgetsBindingObserver {
  PushOptions? _options;
  String? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the store: a push app may have arrived.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final options = await widget.push.options();
    if (!mounted) return;
    setState(() {
      // The user asked for a push app and one is now installed: that
      // pick carries over. Otherwise only Settings has a current choice
      // to show; onboarding starts with nothing selected.
      if (_selected == _getPushApp && options.distributors.length == 1) {
        _selected = options.distributors.keys.single;
      } else if (_options == null) {
        _selected = _offered(options).contains(widget.push.choice)
            ? widget.push.choice
            : null;
      }
      _options = options;
    });
  }

  static List<String> _offered(PushOptions options) => [
        if (options.google) kPushChoiceGoogle,
        ...options.distributors.keys,
        if (options.distributors.isEmpty) _getPushApp,
        kPushChoiceNone,
      ];

  Future<void> _continue() async {
    final selected = _selected!;
    if (selected == _getPushApp) {
      // Stay here: back from the store, [_load] offers what was installed.
      try {
        if (await launchUrl(Uri.parse(kNtfyStoreUrl),
            mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {/* no store on this phone */}
      await launchUrl(Uri.parse(kNtfyFdroidUrl),
          mode: LaunchMode.externalApplication);
      return;
    }
    // The service asks for the notification grant itself, now that the
    // user has said yes to push.
    unawaited(widget.push.choose(selected));
    widget.onDone();
  }

  (String, String) _describe(String option) => switch (option) {
        kPushChoiceGoogle => (
            'Google Play services',
            'Works out of the box. Google can see that a notification '
                'arrived, never your messages.',
          ),
        _getPushApp => (
            'A push app such as ntfy',
            'No Google, needs one small extra app.',
          ),
        kPushChoiceNone => (
            'Not now',
            'Messages arrive only while Vartalap is open.',
          ),
        _ => (_options!.distributors[option]!, 'Push app. No Google.'),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final options = _options;
    // Pushed from Settings → a back arrow; as onboarding → none.
    final fromSettings = ModalRoute.of(context)?.canPop ?? false;

    return Scaffold(
      appBar: fromSettings ? AppBar() : null,
      body: SafeArea(
        // The options scroll and the button stays put, so a short screen
        // or large text never overflows. (Not the username screen's
        // IntrinsicHeight + Spacer: it under-measures wrapped tiles.)
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    kSpaceLg, kSpaceLg, kSpaceLg, 0),
                children: [
                  Icon(Icons.notifications_active_outlined,
                      size: 48, color: scheme.primary),
                  const SizedBox(height: kSpaceMd),
                  Text(
                    'Get messages when Vartalap is closed',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: kSpaceSm),
                  Text(
                    'Something has to wake Vartalap up when a message '
                    'arrives. The wake-up never carries your messages.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: kSpaceMd),
                  if (options == null)
                    const Padding(
                      padding: EdgeInsets.all(kSpaceLg),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    RadioGroup<String>(
                      groupValue: _selected,
                      onChanged: (v) => setState(() => _selected = v),
                      child: Column(
                        children: [
                          for (final option in _offered(options))
                            RadioListTile<String>(
                              value: option,
                              contentPadding: EdgeInsets.zero,
                              title: Text(_describe(option).$1),
                              subtitle: Text(_describe(option).$2),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(kSpaceLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _selected == null ? null : _continue,
                    child: Text(
                        _selected == _getPushApp ? 'Get ntfy' : 'Continue'),
                  ),
                  if (!fromSettings) ...[
                    const SizedBox(height: kSpaceSm),
                    Text(
                      'You can change this later in Settings.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
