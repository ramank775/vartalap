/// Shown when this phone cannot open the signed-in account's encryption
/// keys (a lost or unreadable wrapping key): the chats stay closed until
/// the user tries again or starts this phone's encryption over.
library vartalap.screens.startup.crypto_locked;

import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';

class CryptoLockedScreen extends StatefulWidget {
  final Future<void> Function() onRetry;
  final Future<void> Function() onReset;

  const CryptoLockedScreen({
    super.key,
    required this.onRetry,
    required this.onReset,
  });

  @override
  State<CryptoLockedScreen> createState() => _CryptoLockedScreenState();
}

class _CryptoLockedScreenState extends State<CryptoLockedScreen> {
  bool _working = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirmReset() async {
    final reset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset encryption?'),
        content: const Text(
            'Messages that arrived for the old keys can no longer be read. '
            'Your chats on this phone stay.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (reset == true) await _run(widget.onReset);
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
            children: [
              const Spacer(),
              const AppLogo(size: 40),
              const SizedBox(height: kSpaceLg),
              Text(
                "Can't unlock your messages",
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: kSpaceMd),
              Text(
                'Vartalap could not read the keys that protect your messages '
                'on this phone. Try again, or reset encryption: your chats '
                'stay, and your contacts will see that your security code '
                'changed.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _working ? null : () => _run(widget.onRetry),
                  child: const Text('Try again'),
                ),
              ),
              const SizedBox(height: kSpaceSm),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _working ? null : _confirmReset,
                  child: const Text('Reset encryption'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
