/// Settings-style rows at WhatsApp's density: a two-line row about 60dp,
/// a one-line row 56 (the theme's list rows are 72/56, sized for the
/// chat list's avatars). A screen-level override, so the theme stays
/// where it is.
library vartalap.widgets.compact_tiles;

import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';

Widget compactTiles(Widget child) => ListTileTheme.merge(
      minVerticalPadding: kSpaceSm,
      minTileHeight: 56,
      child: child,
    );
