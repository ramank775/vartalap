/// "Verify security code" (decision 184): the safety number two people
/// compare to know their messages are end-to-end encrypted between their
/// own phones, with nobody in the middle.
library vartalap.screens.chat_info.security_code;

import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';

class SecurityCodeScreen extends StatelessWidget {
  final String name;

  /// 60 digits, or null before any message has gone between the phones.
  final Future<String?> number;

  const SecurityCodeScreen({super.key, required this.name, required this.number});

  /// Twelve groups of five, four to a row, as WhatsApp lays it out.
  static List<String> rows(String digits) => [
        for (var row = 0; row < digits.length; row += 20)
          [
            for (var i = row; i < row + 20 && i < digits.length; i += 5)
              digits.substring(i, i + 5)
          ].join('  ')
      ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify security code')),
      body: FutureBuilder<String?>(
        future: number,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final digits = snap.data;
          return ListView(
            padding: const EdgeInsets.all(kSpaceLg),
            children: [
              Icon(Icons.lock_outline, size: 48, color: scheme.primary),
              const SizedBox(height: kSpaceLg),
              if (digits == null)
                Text(
                  'Send or receive a message with $name first; then a '
                  'security code appears here to compare.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                )
              else ...[
                for (final row in rows(digits))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: kSpaceXs),
                    child: Text(
                      row,
                      textAlign: TextAlign.center,
                      style: textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                const SizedBox(height: kSpaceLg),
                Text(
                  'To verify that messages with $name are end-to-end '
                  'encrypted, compare these numbers with the ones on their '
                  'phone. They are the same on both phones.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
