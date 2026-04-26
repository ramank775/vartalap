/// Vartalap v3 design system — Material 3.
///
/// Single seed color (teal) adapted for light and dark via
/// [ColorScheme.fromSeed]. All screens inherit from this; no hardcoded
/// colors in widget code.
library vartalap.theme;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Design tokens
// ---------------------------------------------------------------------------

/// The brand's seed color. Every surface, accent, and tint derives from this.
const Color kSeedColor = Color(0xFF009978);

/// Spacing scale (8px grid).
const double kSpaceXs = 4;
const double kSpaceSm = 8;
const double kSpaceMd = 16;
const double kSpaceLg = 24;
const double kSpaceXl = 32;
const double kSpaceXxl = 48;

/// Border radii.
const double kRadiusSm = 8;
const double kRadiusMd = 12;
const double kRadiusLg = 16;
const double kRadiusXl = 24;
const double kRadiusFull = 999;

/// Avatar sizes.
const double kAvatarSm = 32;
const double kAvatarMd = 42;
const double kAvatarLg = 56;
const double kAvatarXl = 80;

// ---------------------------------------------------------------------------
// Color scheme
// ---------------------------------------------------------------------------

final ColorScheme _lightScheme = ColorScheme.fromSeed(
  seedColor: kSeedColor,
  brightness: Brightness.light,
);

final ColorScheme _darkScheme = ColorScheme.fromSeed(
  seedColor: kSeedColor,
  brightness: Brightness.dark,
);

// ---------------------------------------------------------------------------
// Text theme
// ---------------------------------------------------------------------------

const String _fontFamily = 'sofia';

TextTheme _buildTextTheme(TextTheme base) {
  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontFamily: _fontFamily),
    displayMedium: base.displayMedium?.copyWith(fontFamily: _fontFamily),
    displaySmall: base.displaySmall?.copyWith(fontFamily: _fontFamily),
    headlineLarge: base.headlineLarge?.copyWith(fontFamily: _fontFamily),
    headlineMedium: base.headlineMedium?.copyWith(
      fontFamily: _fontFamily,
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: base.headlineSmall?.copyWith(fontFamily: _fontFamily),
    titleLarge: base.titleLarge?.copyWith(
      fontFamily: _fontFamily,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: base.titleMedium?.copyWith(fontFamily: _fontFamily),
    titleSmall: base.titleSmall?.copyWith(fontFamily: _fontFamily),
    bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(height: 1.5),
    bodySmall: base.bodySmall?.copyWith(height: 1.4),
    labelLarge: base.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );
}

// ---------------------------------------------------------------------------
// ThemeData builders
// ---------------------------------------------------------------------------

final ThemeData lightThemeData = ThemeData(
  useMaterial3: true,
  colorScheme: _lightScheme,
  textTheme: _buildTextTheme(ThemeData.light().textTheme),
  scaffoldBackgroundColor: _lightScheme.surface,
  appBarTheme: AppBarTheme(
    backgroundColor: _lightScheme.primary,
    foregroundColor: _lightScheme.onPrimary,
    elevation: 0,
    centerTitle: false,
    systemOverlayStyle: SystemUiOverlayStyle.light,
    titleTextStyle: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: _lightScheme.onPrimary,
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: _lightScheme.primaryContainer,
    foregroundColor: _lightScheme.onPrimaryContainer,
    elevation: 2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(kRadiusLg)),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _lightScheme.primary,
      foregroundColor: _lightScheme.onPrimary,
      padding: const EdgeInsets.symmetric(
        horizontal: kSpaceLg,
        vertical: kSpaceMd,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusMd)),
      ),
      textStyle: const TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _lightScheme.surfaceContainerHighest,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusMd),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: kSpaceMd,
      vertical: kSpaceMd,
    ),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kRadiusMd),
    ),
    color: _lightScheme.surfaceContainerLow,
  ),
  dividerTheme: DividerThemeData(
    color: _lightScheme.outlineVariant.withValues(alpha: 0.3),
    thickness: 0.5,
    indent: 72, // aligned past avatar
  ),
  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(
      horizontal: kSpaceMd,
      vertical: kSpaceXs,
    ),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: _lightScheme.surfaceContainer,
    surfaceTintColor: _lightScheme.surfaceTint,
    elevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kRadiusMd),
    ),
    textStyle: TextStyle(
      fontFamily: _fontFamily,
      color: _lightScheme.onSurface,
      fontSize: 16,
      height: 1.5,
    ),
    iconColor: _lightScheme.onSurface,
    iconSize: 20,
    labelTextStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: _fontFamily,
        color: _lightScheme.onSurface,
        fontSize: 16,
        height: 1.5,
      ),
    ),
    menuPadding: const EdgeInsets.symmetric(vertical: kSpaceSm),
  ),
  tabBarTheme: TabBarThemeData(
    labelColor: _lightScheme.onPrimary,
    unselectedLabelColor: _lightScheme.onPrimary.withValues(alpha: 0.7),
    indicatorColor: _lightScheme.onPrimary,
    dividerColor: Colors.transparent,
  ),
);

final ThemeData darkThemeData = ThemeData(
  useMaterial3: true,
  colorScheme: _darkScheme,
  textTheme: _buildTextTheme(ThemeData.dark().textTheme),
  scaffoldBackgroundColor: _darkScheme.surface,
  appBarTheme: AppBarTheme(
    backgroundColor: _darkScheme.surface,
    foregroundColor: _darkScheme.onSurface,
    elevation: 0,
    centerTitle: false,
    systemOverlayStyle: SystemUiOverlayStyle.light,
    titleTextStyle: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: _darkScheme.onSurface,
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: _darkScheme.primaryContainer,
    foregroundColor: _darkScheme.onPrimaryContainer,
    elevation: 2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(kRadiusLg)),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _darkScheme.primary,
      foregroundColor: _darkScheme.onPrimary,
      padding: const EdgeInsets.symmetric(
        horizontal: kSpaceLg,
        vertical: kSpaceMd,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusMd)),
      ),
      textStyle: const TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _darkScheme.surfaceContainerHighest,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusMd),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: kSpaceMd,
      vertical: kSpaceMd,
    ),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kRadiusMd),
    ),
    color: _darkScheme.surfaceContainerLow,
  ),
  dividerTheme: DividerThemeData(
    color: _darkScheme.outlineVariant.withValues(alpha: 0.3),
    thickness: 0.5,
    indent: 72,
  ),
  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(
      horizontal: kSpaceMd,
      vertical: kSpaceXs,
    ),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: _darkScheme.surfaceContainer,
    surfaceTintColor: _darkScheme.surfaceTint,
    elevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kRadiusMd),
    ),
    textStyle: TextStyle(
      fontFamily: _fontFamily,
      color: _darkScheme.onSurface,
      fontSize: 16,
      height: 1.5,
    ),
    iconColor: _darkScheme.onSurface,
    iconSize: 20,
    labelTextStyle: WidgetStatePropertyAll(
      TextStyle(
        fontFamily: _fontFamily,
        color: _darkScheme.onSurface,
        fontSize: 16,
        height: 1.5,
      ),
    ),
    menuPadding: const EdgeInsets.symmetric(vertical: kSpaceSm),
  ),
  tabBarTheme: TabBarThemeData(
    labelColor: _darkScheme.onSurface,
    unselectedLabelColor: _darkScheme.onSurface.withValues(alpha: 0.7),
    indicatorColor: _darkScheme.primary,
    dividerColor: Colors.transparent,
  ),
);

// ---------------------------------------------------------------------------
// App-specific semantic colors
// ---------------------------------------------------------------------------

/// Chat-specific colors that Material's ColorScheme doesn't cover.
@immutable
class ChatColors {
  final Color senderBubble;
  final Color senderText;
  final Color receiverBubble;
  final Color receiverText;
  final Color statusConnected;
  final Color statusConnecting;
  final Color statusDisconnected;
  final Color linkText;
  final Color unreadBadge;
  final Color unreadBadgeText;
  final Color messageTimestamp;

  const ChatColors({
    required this.senderBubble,
    required this.senderText,
    required this.receiverBubble,
    required this.receiverText,
    required this.statusConnected,
    required this.statusConnecting,
    required this.statusDisconnected,
    required this.linkText,
    required this.unreadBadge,
    required this.unreadBadgeText,
    required this.messageTimestamp,
  });
}

final ChatColors lightChatColors = ChatColors(
  senderBubble: const Color(0xFFD9F5EC), // soft teal tint
  senderText: const Color(0xFF1A3C34),
  receiverBubble: const Color(0xFFFFFFFF),
  receiverText: const Color(0xFF1C1C1E),
  statusConnected: const Color(0xFF4CAF50),
  statusConnecting: const Color(0xFFFFA726),
  statusDisconnected: const Color(0xFFEF5350),
  linkText: _lightScheme.primary,
  unreadBadge: _lightScheme.primary,
  unreadBadgeText: _lightScheme.onPrimary,
  messageTimestamp: const Color(0xFF8E8E93),
);

final ChatColors darkChatColors = ChatColors(
  senderBubble: const Color(0xFF005C4B), // deep teal, like WhatsApp dark
  senderText: const Color(0xFFE9EDEF),
  receiverBubble: const Color(0xFF263238), // neutral slate, lighter than bg
  receiverText: const Color(0xFFE9EDEF),
  statusConnected: const Color(0xFF66BB6A),
  statusConnecting: const Color(0xFFFFCA28),
  statusDisconnected: const Color(0xFFEF5350),
  linkText: const Color(0xFF53BDEB),
  unreadBadge: const Color(0xFF00A884),
  unreadBadgeText: const Color(0xFF111B21),
  messageTimestamp: const Color(0xFF8696A0),
);

// ---------------------------------------------------------------------------
// VartalapTheme — the public API screens use
// ---------------------------------------------------------------------------

@immutable
class VartalapTheme {
  const VartalapTheme._({
    required this.data,
    required this.chatColors,
  });

  final ThemeData data;
  final ChatColors chatColors;

  /// Live theme mode. Wrap the root `MaterialApp` in a
  /// `ValueListenableBuilder` over this notifier so calls to
  /// [setThemeMode] take effect without an app restart.
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static ThemeMode get themeMode => themeModeNotifier.value;

  static set themeMode(ThemeMode value) {
    themeModeNotifier.value = value;
  }

  static VartalapTheme get light =>
      VartalapTheme._(data: lightThemeData, chatColors: lightChatColors);

  static VartalapTheme get dark =>
      VartalapTheme._(data: darkThemeData, chatColors: darkChatColors);

  /// Resolve the chat colors from the current [BuildContext].
  static ChatColors chatColorsOf(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? darkChatColors : lightChatColors;
  }
}
