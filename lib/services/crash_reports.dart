/// Crash and error reports, the app's own (decision 214 took Sentry out).
///
/// Uncaught Dart errors (here) and Android crashes (`Application.kt`) are
/// written to files on the phone. On the next start the home screen sends
/// them if the user turned on Settings › Privacy › "Send crash reports
/// automatically", else asks once; either way they then leave the phone.
/// A report is the app build, Android version, device model, the time and
/// the error's type and stack frames, never its message, so no chat text,
/// number, contact or key goes with it. The server keeps them 30 days
/// (chat-server `POST /v3.0/crash-reports`).
library vartalap.services.crash_reports;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

/// Off unless the user turns it on (opt-in).
const kCrashReportsAutoKey = 'crash_reports_auto';

class CrashReports {
  /// `<files dir>/crash_reports`, where `Application.kt` writes too. Each
  /// report is `<ms>.<dart|android>.txt`: the build, a newline, the trace.
  final Directory dir;

  /// `<version>+<build number>` of the build that is running.
  final String build;

  /// Posts one report to the server; set once signed in.
  Future<void> Function(Map<String, Object> report)? send;

  /// The Android version and device model, asked of `MainActivity`.
  Future<Map<String, String>> Function() device = () async =>
      Map<String, String>.from(await const MethodChannel('vartalap/crash')
              .invokeMapMethod<String, String>('device') ??
          const {});

  CrashReports(this.dir, {this.build = ''});

  /// The one for this engine, once [install]ed.
  static CrashReports? instance;

  /// A crash loop must not fill the phone.
  static const maxWaiting = 10;

  /// The server's limit on a trace.
  static const maxTrace = 16000;

  final _seen = <String>{};

  /// Hooks this engine's Dart error handlers (each engine runs its own:
  /// the app, a push wake, a background job, live location). Errors in
  /// other isolates reach these through whoever awaits them.
  static Future<void> install({required String build}) async {
    if (instance != null) return;
    final Directory files;
    try {
      files = await getApplicationSupportDirectory();
    } catch (_) {
      return; // nowhere to keep them: the app runs without
    }
    final reports = instance =
        CrashReports(Directory('${files.path}/crash_reports'), build: build);
    final flutter = FlutterError.onError;
    FlutterError.onError = (details) {
      reports.record(details.exception, details.stack);
      flutter?.call(details);
    };
    final platform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      reports.record(error, stack);
      // false: still printed, as before
      return platform?.call(error, stack) ?? false;
    };
  }

  /// Keeps [error]'s type and [stack]; never its message, which can hold
  /// what the user typed. Once per run for the same trace, and none past
  /// [maxWaiting]. Synchronous, and never throws: the app may be going.
  void record(Object error, StackTrace? stack) {
    final trace = '${error.runtimeType}\n${stack ?? ''}'.trimRight();
    if (!_seen.add(trace)) return;
    try {
      dir.createSync(recursive: true);
      if (waiting().length >= maxWaiting) return;
      var ms = DateTime.now().millisecondsSinceEpoch;
      while (File('${dir.path}/$ms.dart.txt').existsSync()) {
        ms++; // two in one millisecond
      }
      File('${dir.path}/$ms.dart.txt').writeAsStringSync('$build\n$trace');
    } catch (_) {}
  }

  /// The reports on the phone, oldest first.
  List<File> waiting() {
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.txt'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  /// On the home screen at start: what waits is sent when the user said
  /// always, else asked about once. A report that cannot reach the server
  /// stays for the next start; one it refuses goes.
  Future<void> offer(BuildContext context) async {
    final reports = waiting();
    final send = this.send;
    if (reports.isEmpty || send == null) return;
    var auto = false;
    try {
      auto = (await SharedPreferences.getInstance())
              .getBool(kCrashReportsAutoKey) ??
          false;
    } catch (_) {}
    if (!auto) {
      if (!context.mounted) return;
      final crashed = reports.any((f) => f.path.endsWith('.android.txt'));
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Text(
            '${crashed ? 'Vartalap closed unexpectedly.' : 'Vartalap ran into a problem.'}'
            ' Send a report to help fix it?\n\n'
            'It has no messages, phone numbers or contacts.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Don't send"),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Send'),
            ),
          ],
        ),
      );
      if (ok != true) {
        for (final f in reports) {
          f.deleteSync();
        }
        return;
      }
    }
    final device = await this.device().catchError((_) => <String, String>{});
    for (final file in reports) {
      final [ms, kind, ...] = file.uri.pathSegments.last.split('.');
      final text = file.readAsStringSync();
      final cut = text.indexOf('\n');
      final trace = text.substring(cut + 1);
      try {
        await send({
          'at': int.tryParse(ms) ?? 0,
          'kind': kind,
          'build': text.substring(0, cut < 0 ? 0 : cut),
          'android': device['android'] ?? '',
          'model': device['model'] ?? '',
          'trace':
              trace.length > maxTrace ? trace.substring(0, maxTrace) : trace,
        });
      } on AuthClientException catch (e) {
        if (e.statusCode >= 500) return;
      } catch (_) {
        return; // offline: next start
      }
      file.deleteSync();
    }
  }
}
