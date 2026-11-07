/// "Verify security code" (decision 184): the safety number two people
/// compare to know their messages are end-to-end encrypted between their
/// own phones, with nobody in the middle. As on WhatsApp, also a QR of it:
/// one phone scans the other's and says whether they match.
library vartalap.screens.chat_info.security_code;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vartalap/screens/qr/qr.dart';
import 'package:vartalap/theme/theme.dart';

/// What the QR carries: a version, then the 60 digits. They come from
/// both phones' public identity keys, so they are no secret.
String securityCodeQr(String digits) => 'vartalap-sc:1:$digits';

/// The digits in a scanned [raw] code, or null when it is no security
/// code of ours (another QR, or a version this app does not know).
String? securityCodeFromQr(String raw) {
  final m = RegExp(r'^vartalap-sc:1:(\d{60})$').firstMatch(raw.trim());
  return m?.group(1);
}

/// Opens the camera; the first code read, or null if backed out.
Future<String?> _scanWithCamera(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (route) {
        var done = false;
        return Scaffold(
          appBar: AppBar(title: const Text('Scan code')),
          body: QrScanView(onText: (raw) {
            // The camera keeps reading it while it stays in view.
            if (done) return;
            done = true;
            Navigator.of(route).pop(raw);
          }),
        );
      },
    ));

enum _Scan { verified, mismatch, notACode }

class SecurityCodeScreen extends StatefulWidget {
  final String name;

  /// 60 digits, or null before any message has gone between the phones.
  final Future<String?> number;

  /// Reads a QR; tests stand in for the camera.
  final Future<String?> Function(BuildContext context) scan;

  const SecurityCodeScreen({
    super.key,
    required this.name,
    required this.number,
    this.scan = _scanWithCamera,
  });

  /// Twelve groups of five, four to a row, as WhatsApp lays it out.
  static List<String> rows(String digits) => [
        for (var row = 0; row < digits.length; row += 20)
          [
            for (var i = row; i < row + 20 && i < digits.length; i += 5)
              digits.substring(i, i + 5)
          ].join('  ')
      ];

  @override
  State<SecurityCodeScreen> createState() => _SecurityCodeScreenState();
}

class _SecurityCodeScreenState extends State<SecurityCodeScreen> {
  /// The last scan's outcome, for this visit only: the app keeps no
  /// verified flag.
  _Scan? _result;

  Future<void> _scan(String digits) async {
    final raw = await widget.scan(context);
    if (raw == null || !mounted) return;
    final theirs = securityCodeFromQr(raw);
    setState(() => _result = theirs == null
        ? _Scan.notACode
        : theirs == digits
            ? _Scan.verified
            : _Scan.mismatch);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final name = widget.name;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify security code')),
      body: FutureBuilder<String?>(
        future: widget.number,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final digits = snap.data;
          return ListView(
            padding: EdgeInsets.fromLTRB(kSpaceLg, kSpaceLg, kSpaceLg,
                kSpaceLg + MediaQuery.paddingOf(context).bottom),
            children: [
              if (digits == null) ...[
                Icon(Icons.lock_outline, size: 48, color: scheme.primary),
                const SizedBox(height: kSpaceLg),
                Text(
                  'Send or receive a message with $name first; then a '
                  'security code appears here to compare.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
              ] else ...[
                if (_result case final result?) ...[
                  _ScanResult(result: result, name: name),
                  const SizedBox(height: kSpaceMd),
                ],
                Center(
                  child: Container(
                    width: 220,
                    height: 220,
                    padding: const EdgeInsets.all(kSpaceSm),
                    // Always light behind the modules: a QR on a dark
                    // surface does not scan.
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(kRadiusMd),
                    ),
                    child: QrImageView(
                      data: securityCodeQr(digits),
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      semanticsLabel: 'Security code QR',
                    ),
                  ),
                ),
                const SizedBox(height: kSpaceLg),
                for (final row in SecurityCodeScreen.rows(digits))
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
                  'encrypted, scan the code on their phone, or compare '
                  'these numbers with theirs. They are the same on both '
                  'phones.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: kSpaceLg),
                Center(
                  child: FilledButton.icon(
                    onPressed: () => _scan(digits),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan code'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Green when the codes match, red, saying why, when they do not.
class _ScanResult extends StatelessWidget {
  final _Scan result;
  final String name;
  const _ScanResult({required this.result, required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = result == _Scan.verified;
    final color = ok ? Colors.green.shade700 : scheme.error;
    final (title, detail) = switch (result) {
      _Scan.verified => (
          'Security code verified',
          'Your messages with $name are end-to-end encrypted, with nobody '
              'in between.'
        ),
      _Scan.mismatch => (
          "Security codes don't match",
          "The code you scanned is not the one for your chat with $name. "
              "Scan $name's code from their chat with you. If one of you "
              'reinstalled Vartalap, send each other a message and scan '
              'again.'
        ),
      _Scan.notACode => (
          'Not a security code',
          "Scan the QR under Encryption in $name's chat info with you."
        ),
    };
    return Container(
      padding: const EdgeInsets.all(kSpaceMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.verified_user : Icons.gpp_bad_outlined,
              color: color),
          const SizedBox(width: kSpaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: color)),
                const SizedBox(height: kSpaceXs),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
