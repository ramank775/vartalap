import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:vartalap/widgets/location_map.dart';

/// Runs before every test file under test/: maps draw a blank layer in
/// place of OpenStreetMap's tiles, so no test touches the network.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  mapTiles = () => const SizedBox.shrink(key: Key('map-tiles'));
  await testMain();
}
