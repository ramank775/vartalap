/// Crash and error reports, the app's own (decision 214 took Sentry out).
///
/// Uncaught Dart errors (here) and Android crashes (`Application.kt`) are
/// written to files on the phone. On the next start the home screen asks
/// once; on Send it opens the phone's email app with them filled in, to
/// [kCrashReportsTo], for the user to read and send (owner: "start with a
/// simple mail"). Either way they then leave the phone. A report is the
/// app build, Android version, device model, the time and the error's type
/// and stack frames, never its message, so no chat text, number, contact
/// or key goes with it. Our server receives none.
library vartalap.services.crash_reports;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// The project's address, as on the website.
const kCrashReportsTo = 'vartalap@one9x.org';

class CrashReports {
  /// `<files dir>/crash_reports`, where `Application.kt` writes too. Each
  /// report is `<ms>.<dart|android>.txt`: the build, a newline, the trace.
  final Directory dir;

  /// `<version>+<build number>` of the build that is running.
  final String build;

  /// MainActivity's `vartalap/intents`: `email` (an email app) or `share`
  /// (the share sheet) with `to`, `subject` and `body`; false when nothing
  /// took it.
  Future<bool> Function(String method, Map<String, String> mail) handOff =
      (method, mail) async =>
          await const MethodChannel('vartalap/intents')
              .invokeMethod<bool>(method, mail) ??
          false;

  /// The Android version and device model, asked of `MainActivity`.
  Future<Map<String, String>> Function() device =
      () async => Map<String, String>.from(
            await const MethodChannel('vartalap/crash')
                    .invokeMapMethod<String, String>('device') ??
                const {},
          );

  CrashReports(this.dir, {this.build = ''});

  /// The one for this engine, once [install]ed.
  static CrashReports? instance;

  /// A crash loop must not fill the phone.
  static const maxWaiting = 10;

  /// What goes in the mail's body at most, in characters: about 150
  /// stack frames, well inside what mail apps take from an intent.
  static const maxBody = 10000;

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
    final reports = instance = CrashReports(
      Directory('${files.path}/crash_reports'),
      build: build,
    );
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

  /// On the home screen at start: what waits is asked about once. Send
  /// opens an email app with all of it, newest first, else the share
  /// sheet; the phone cannot know whether the user sends it, so a hand-off
  /// counts as sent. Nothing took it: kept for the next start.
  Future<void> offer(BuildContext context) async {
    final reports = waiting();
    if (reports.isEmpty || !context.mounted) return;
    final crashed = reports.any((f) => f.path.endsWith('.android.txt'));
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Text(
          '${crashed ? 'Vartalap closed unexpectedly.' : 'Vartalap ran into a problem.'}'
          ' Send a report to help fix it? It opens your email app, where '
          'you can read the report before you send it.\n\n'
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
    if (ok == true) {
      final device = await this.device().catchError((_) => <String, String>{});
      final mail = this.mail(reports, device);
      var taken = false;
      try {
        taken = await handOff('email', mail) || await handOff('share', mail);
      } catch (_) {}
      if (!taken) return;
    }
    for (final f in reports) {
      f.deleteSync();
    }
  }

  /// One mail for [reports], newest first, its body cut at [maxBody].
  Map<String, String> mail(List<File> reports, Map<String, String> device) {
    var newestBuild = '';
    final body = StringBuffer(
      'Android ${device['android'] ?? '?'}, '
      '${device['model'] ?? '?'}\n',
    );
    for (final file in reports.reversed) {
      final [ms, kind, ...] = file.uri.pathSegments.last.split('.');
      final text = file.readAsStringSync();
      final cut = text.indexOf('\n');
      final made = cut < 0 ? '' : text.substring(0, cut);
      if (newestBuild.isEmpty) newestBuild = made;
      final at = DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(ms) ?? 0,
        isUtc: true,
      );
      body.write(
        '\n${at.toIso8601String()}, build $made, '
        '${kind == 'android' ? 'Android crash' : 'Dart error'}:\n'
        '${text.substring(cut + 1)}\n',
      );
    }
    final text = body.toString();
    return {
      'to': kCrashReportsTo,
      'subject':
          'Vartalap crash report (build ${(newestBuild.isEmpty ? build : newestBuild).split('+').last})',
      'body': text.length > maxBody ? text.substring(0, maxBody) : text,
    };
  }
}
