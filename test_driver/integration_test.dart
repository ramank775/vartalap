/// Driver half of the L3 emulator run — exists only to write the
/// screenshots `integration_test/smoke_test.dart` takes to disk.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
      onScreenshot: (String name, List<int> bytes,
          [Map<String, Object?>? args]) async {
        final out = Directory(
          Platform.environment['VARTALAP_SHOT_DIR'] ??
              '/home/raman/git/vartalap-workspace/design/screens',
        );
        await out.create(recursive: true);
        await File('${out.path}/$name.png').writeAsBytes(bytes);
        return true;
      },
    );
