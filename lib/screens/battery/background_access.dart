import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/services/push_service.dart';
import 'package:vartalap/theme/theme.dart';

/// Decision 201: Android's battery optimization holds back the message
/// check and the queued sends while the app is closed. [allowed]: this app
/// is left out of it. [direct]: the build may ask with the system dialog
/// (foss); the gms build only opens its settings page, since Play allows
/// the dialog only for apps that cannot use FCM.
typedef BackgroundAccess = ({bool allowed, bool direct});

const _channel = MethodChannel('vartalap/battery');

/// Null until read, and wherever there is no channel (tests, desktop).
final backgroundAccess = ValueNotifier<BackgroundAccess?>(null);

/// At start and whenever the app comes back to the front: the user may
/// have changed it in Settings meanwhile.
Future<void> refreshBackgroundAccess() async {
  try {
    final state = await _channel.invokeMapMethod<String, bool>('state');
    if (state == null) return;
    backgroundAccess.value =
        (allowed: state['allowed']!, direct: state['direct']!);
  } catch (_) {
    // No channel: nothing is shown.
  }
}

/// Worth asking: in the foss build always (no Google push to lean on),
/// in the gms build only while its push is not working.
bool backgroundAccessWanted(BackgroundAccess? access, PushState push) =>
    access != null &&
    !access.allowed &&
    (access.direct || push != PushState.registered);

const _why = 'To save battery, Android holds back apps you are not using, '
    'so new messages can reach you late, and a message sent just before '
    'you closed the app can wait. ';
const _askDialog = 'Allow Vartalap to run in the background? It only checks '
    'for messages now and then.';
const _askSettings = 'On the next screen, open App battery usage and choose '
    "Unrestricted (on some phones: Allow background activity, or Don't "
    'optimize).';

/// Says why, then the system dialog (foss) or the app's settings page.
Future<void> askBackgroundAccess(BuildContext context) async {
  final access = backgroundAccess.value;
  if (access == null) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Get messages on time'),
      content: Text(_why + (access.direct ? _askDialog : _askSettings)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(access.direct ? 'Continue' : 'Open settings'),
        ),
      ],
    ),
  );
  if (go != true) return;
  try {
    await _channel.invokeMethod<bool>('ask');
  } catch (_) {
    // Nothing to open: the Settings row stays.
  }
}

/// "Messages may arrive late" above the chat list while
/// [backgroundAccessWanted]. Dismissed, it stays away; Settings ›
/// Background activity is still there.
class BackgroundAccessBanner extends StatefulWidget {
  final PushService? push;
  const BackgroundAccessBanner({super.key, required this.push});

  @override
  State<BackgroundAccessBanner> createState() => _BackgroundAccessBannerState();
}

class _BackgroundAccessBannerState extends State<BackgroundAccessBanner> {
  static const _dismissedKey = 'v3.background_banner_dismissed';

  // Hidden until the preference says otherwise: never a flash of banner.
  bool _dismissed = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _dismissed = prefs.getBool(_dismissedKey) ?? false);
      }
    });
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    await (await SharedPreferences.getInstance()).setBool(_dismissedKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final push = widget.push;
    if (push == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([backgroundAccess, push.state]),
      builder: (context, _) {
        if (_dismissed ||
            !backgroundAccessWanted(backgroundAccess.value, push.state.value)) {
          return const SizedBox.shrink();
        }
        return Material(
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.only(left: kSpaceMd),
            child: Row(
              children: [
                Icon(Icons.battery_alert,
                    size: 20, color: scheme.onSecondaryContainer),
                const SizedBox(width: kSpaceSm),
                Expanded(
                  child: Text(
                    'Messages may arrive late',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
                TextButton(
                  onPressed: () => askBackgroundAccess(context),
                  child: const Text('Allow'),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: scheme.onSecondaryContainer,
                  tooltip: 'Dismiss',
                  onPressed: _dismiss,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
