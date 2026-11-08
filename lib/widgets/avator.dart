import 'package:flutter/material.dart';
import 'package:vartalap/services/asset_cache.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/color_helper.dart';
import 'package:vartalap/widgets/Inherited/app_services.dart';
import 'package:vartalap/widgets/asset_image.dart';
import 'package:vartalap_sync/vartalap_sync.dart' show dmChannelId;

/// The big photo at the top of Profile, Contact info and Chat info
/// (WhatsApp's is about this size).
const double kAvatarHeader = 120;

/// Colour seed for a person: the id of your DM with them. The chat list
/// and chat header seed a DM by its channel id, so seeding people the
/// same way gives one person one colour on every screen.
String personSeed(BuildContext context, String userId) {
  final me = AppServicesProvider.maybeOf(context)?.authService.currentUserId;
  return me == null ? userId : dmChannelId(me, userId);
}

/// One avatar for people and groups alike.
///
/// Photo when [avatarUrl] is set, otherwise the generated fallback:
/// initials for a person, the group glyph for a group (frame a1 —
/// "groups get the filled glyph avatar", so a group row reads as a
/// group before you read its name). Both sit on a colour seeded from
/// [seed], which should be the stable channel or user id: renaming a
/// group or saving a contact must not change its colour.
class Avator extends StatelessWidget {
  final String text;
  final double width;
  final double height;

  /// The stored photo pointer: a media-ms fileId, an http url, or a
  /// local path for one we have picked but not uploaded yet. All three
  /// resolve through [AssetCache]. Null or empty falls straight through
  /// to the generated avatar; a load error or a slow load shows it too,
  /// so there is never a blank hole in a list row.
  final String? avatarUrl;

  /// Injected by tests; null uses [AssetCache.instance].
  final AssetCache? cache;

  /// Colour seed. Defaults to [text] for callers that have no id.
  final String? seed;

  /// Renders the group glyph instead of initials when there is no
  /// photo.
  final bool isGroup;

  const Avator({
    super.key,
    required this.text,
    required this.width,
    required this.height,
    this.avatarUrl,
    this.seed,
    this.isGroup = false,
    this.cache,
  });

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final fallback = _generated(context);
    if (url == null || url.isEmpty) return fallback;

    return ClipOval(
      child: AssetImageView(
        uri: url,
        cache: cache,
        width: width,
        height: height,
        // Both the in-flight and the failed case land on the generated
        // avatar rather than a spinner or a broken-image glyph.
        placeholder: fallback,
      ),
    );
  }

  Widget _generated(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // Pre-blended onto the page surface so the avatar is opaque: a
    // translucent one took on the green app bar behind it and looked a
    // different colour in the chat header than in lists.
    final bgColor = Color.alphaBlend(
      getColor(seed ?? text, opacity: 0.8, brightness: brightness),
      Theme.of(context).colorScheme.surface,
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
      ),
      alignment: Alignment.center,
      child: isGroup
          ? Icon(
              Icons.groups_rounded,
              // Slightly larger than the text cap-height so the glyph
              // reads at 32px as well as at 80px.
              size: width * 0.55,
              color: Colors.white,
            )
          : Text(
              _initials(text),
              style: TextStyle(
                color: Colors.white,
                // Scale font to ~40% of avatar size for readability.
                fontSize: width * 0.4,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
    );
  }

  /// Whole characters (grapheme clusters), never a lone UTF-16 unit: half
  /// an emoji is malformed text, and laying it out throws, which took down
  /// whole lists on a phone (a contact named "Ravi 🙏 Kumar").
  String _initials(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '?';
    final firsts = [
      for (final part in trimmed.split(RegExp(r'[\s_]+')))
        if (part.isNotEmpty) part.characters.first,
    ];
    if (firsts.length >= 2 &&
        _isLetterOrDigit(firsts[0]) &&
        _isLetterOrDigit(firsts[1])) {
      return '${firsts[0]}${firsts[1]}'.toUpperCase();
    }
    // Find the first letter or digit; skips leading symbols like
    // "+" on phone numbers so "+919876543210" becomes "9", not "+".
    for (final ch in trimmed.characters) {
      if (_isLetterOrDigit(ch)) return ch.toUpperCase();
    }
    return trimmed.characters.first;
  }

  static bool _isLetterOrDigit(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    // 0-9
    if (code >= 0x30 && code <= 0x39) return true;
    // A-Z
    if (code >= 0x41 && code <= 0x5A) return true;
    // a-z
    if (code >= 0x61 && code <= 0x7A) return true;
    // Letters outside ASCII (broad approximation): anything above 0x7F
    // that isn't a common ASCII symbol is probably a letter (e.g. á, ñ,
    // 你). Good enough for an avatar initial. Not a surrogate pair: those
    // are mostly emoji, which make a poor initial.
    return code > 0x7F && (code < 0xD800 || code > 0xDFFF);
  }
}

/// [Avator] with the camera affordance from mockup frames e (group
/// photo) and h2 (own photo). The badge runs [onTap]; so does the photo
/// itself, unless [onView] is set (WhatsApp: a photo opens full screen
/// first, and the badge goes straight to changing it).
class EditableAvator extends StatelessWidget {
  final Widget avatar;
  final VoidCallback onTap;
  final VoidCallback? onView;

  /// Shown instead of the badge while an upload is being prepared.
  final bool busy;

  const EditableAvator({
    super.key,
    required this.avatar,
    required this.onTap,
    this.onView,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(onTap: busy ? null : onView ?? onTap, child: avatar),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: busy ? null : onTap,
            child: Container(
              padding: const EdgeInsets.all(kSpaceSm),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary,
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Icon(Icons.photo_camera,
                      size: 20,
                      color: scheme.onPrimary,
                      semanticLabel: 'Change photo'),
            ),
          ),
        ),
      ],
    );
  }
}
