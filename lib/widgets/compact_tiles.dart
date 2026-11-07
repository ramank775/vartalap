/// WhatsApp's list density for a screen's rows: no vertical padding on
/// top of the theme's, 56dp unless the words need more (a two-line row
/// comes to about 60dp, a 52dp avatar fits). A screen-level override, so
/// the theme's own ListTile defaults stay where they are.
library vartalap.widgets.compact_tiles;

import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';

Widget compactTiles(Widget child) => ListTileTheme.merge(
      contentPadding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
      minTileHeight: 56,
      child: child,
    );
