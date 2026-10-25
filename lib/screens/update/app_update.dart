import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// Decision 192: Play installs update from Play, everything else
/// (GitHub, sideloads) from the GitHub release.
Future<void> openAppUpdate() async {
  final info = ConfigStore().packageInfo;
  final url = info.installerStore == 'com.android.vending'
      ? 'https://play.google.com/store/apps/details?id=${info.packageName}'
      : 'https://github.com/ramank775/vartalap/releases/latest';
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Shows [child] until the server refuses this build, then only the
/// update screen (decision 192: nothing else works without the server).
class AppUpdateGate extends StatelessWidget {
  final AppBuild appBuild;
  final Widget child;
  const AppUpdateGate({super.key, required this.appBuild, required this.child});

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
        stream: appBuild.changes,
        builder: (context, _) =>
            appBuild.upgradeRequired ? const _UpdateRequired() : child,
      );
}

class _UpdateRequired extends StatelessWidget {
  const _UpdateRequired();

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
              const Spacer(),
              Icon(Icons.system_update, size: 48, color: scheme.primary),
              const SizedBox(height: kSpaceMd),
              Text('Update Vartalap',
                  style: text.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: kSpaceSm),
              Text(
                'This version of Vartalap is no longer supported. Update '
                'to keep sending and receiving messages. Your chats stay '
                'on this phone.',
                style:
                    text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton(
                onPressed: openAppUpdate,
                child: const Text('Update'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "New version available" above the chat list while the server names a
/// newer build. Dismissed, it returns after a restart or a day.
class AppUpdateBanner extends StatefulWidget {
  final AppBuild appBuild;
  const AppUpdateBanner({super.key, required this.appBuild});

  @override
  State<AppUpdateBanner> createState() => _AppUpdateBannerState();
}

class _AppUpdateBannerState extends State<AppUpdateBanner> {
  static DateTime? _dismissedAt;

  bool get _dismissed =>
      _dismissedAt != null &&
      DateTime.now().difference(_dismissedAt!) < const Duration(days: 1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<void>(
      stream: widget.appBuild.changes,
      builder: (context, _) {
        if (!widget.appBuild.updateAvailable || _dismissed) {
          return const SizedBox.shrink();
        }
        return Material(
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.only(left: kSpaceMd),
            child: Row(
              children: [
                Icon(Icons.system_update,
                    size: 20, color: scheme.onSecondaryContainer),
                const SizedBox(width: kSpaceSm),
                Expanded(
                  child: Text(
                    'New version available',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
                TextButton(
                    onPressed: openAppUpdate, child: const Text('Update')),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: scheme.onSecondaryContainer,
                  tooltip: 'Dismiss',
                  onPressed: () =>
                      setState(() => _dismissedAt = DateTime.now()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
