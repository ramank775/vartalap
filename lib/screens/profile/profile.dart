/// User profile screen — everything inline-editable, no popups.
library vartalap.screens.profile;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/username.dart';
import 'package:vartalap/widgets/avator.dart';

/// What the profile QR encodes — the handle, never the number
/// (AUTH_CONTRACT §2.5, mockup frame h2).
String usernameQrPayload(String username) => 'vartalap://u/$username';

/// AUTH_CONTRACT §4.5 — exactly 4 digits, or empty to clear.
String? _validateUsernameKey(String value) {
  if (value.isEmpty) return null; // empty = clear, allowed
  if (!RegExp(r'^\d{4}$').hasMatch(value)) return 'Exactly 4 digits';
  return null;
}

class ProfileScreen extends StatefulWidget {
  final AuthService authService;
  final ConfigStore config;

  const ProfileScreen({
    super.key,
    required this.authService,
    required this.config,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _qrOpen = false;
  bool _signOutArmed = false;
  Timer? _signOutResetTimer;

  @override
  void initState() {
    super.initState();
    _subs.add(widget.authService.displayNameChange
        .listen((_) => _refreshIfMounted()));
    _subs.add(widget.authService.usernameChange
        .listen((_) => _refreshIfMounted()));
    _subs.add(widget.authService.statusTextChange
        .listen((_) => _refreshIfMounted()));
  }

  void _refreshIfMounted() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _signOutResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = widget.authService;
    final phone = auth.phoneNumber;
    final name = auth.displayName;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: kSpaceXl),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ProfileAvatar(name: name, phone: phone),
              const SizedBox(height: kSpaceSm),
              // The handle, prominent: it is the public identity
              // (AUTH_CONTRACT §2.4), the number below it is not.
              Text(
                auth.username == null ? 'No username yet' : '@${auth.username}',
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.primary,
                  fontStyle: auth.username == null
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
              const SizedBox(height: kSpaceMd),
            ],
          ),
          _InlineEditableRow(
            icon: Icons.badge_outlined,
            label: 'Name',
            value: name,
            placeholder: 'Add your name',
            maxLength: 50,
            textCapitalization: TextCapitalization.words,
            onSave: (v) => auth.setDisplayName(v),
          ),
          const Divider(height: 1, indent: kSpaceMd, endIndent: kSpaceMd),
          _InlineEditableRow(
            icon: Icons.alternate_email_rounded,
            label: 'Username',
            value: auth.username,
            placeholder: 'Add a username',
            maxLength: 30,
            textCapitalization: TextCapitalization.none,
            valuePrefix: '@',
            onSave: (v) => auth.setUsername(v),
            validator: validateUsername,
            // §2.4: clearing re-arms the USERNAME_REQUIRED gate, so the
            // contract says not to offer it as a bare UI action.
            allowEmpty: false,
            unavailableMessage: 'That username is taken',
            availabilityCheck: (candidate) async {
              // Skip the network round-trip when the user retypes
              // their existing handle — own-handle is always
              // "available" to oneself.
              if (candidate == auth.username) {
                return _RowAvailability.available;
              }
              final result =
                  await auth.checkUsernameAvailability(candidate);
              return result.available
                  ? _RowAvailability.available
                  : _RowAvailability.unavailable;
            },
          ),
          const Divider(height: 1, indent: kSpaceMd, endIndent: kSpaceMd),
          _InlineEditableRow(
            icon: Icons.access_time_rounded,
            label: 'Status',
            value: auth.statusText,
            placeholder: 'Hey there, I am using Vartalap',
            maxLength: 140,
            textCapitalization: TextCapitalization.sentences,
            onSave: (v) => auth.setStatusText(v),
          ),
          const Divider(height: 1, indent: kSpaceMd, endIndent: kSpaceMd),
          // Phone — read-only, and private: §2.5 means the server never
          // hands this to anyone but its owner, so say so.
          ListTile(
            leading: Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
            title: const Text('Phone'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatPhone(phone),
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'Only you can see this',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: kSpaceMd, endIndent: kSpaceMd),
          // Optional 4-digit discovery key — AUTH_CONTRACT §4.5 / §7.6.
          _InlineEditableRow(
            icon: Icons.lock_outline,
            label: 'Username key (optional)',
            value: auth.usernameKey,
            placeholder: 'Not set',
            caption: 'People who message you by username must enter this.',
            maxLength: 4,
            textCapitalization: TextCapitalization.none,
            onSave: (v) => auth.setUsernameKey(v),
            validator: _validateUsernameKey,
          ),
          const Divider(height: 1, indent: kSpaceMd, endIndent: kSpaceMd),
          // QR — inline expand/collapse instead of a popup. Hidden
          // entirely until there is a handle to encode: the QR carries
          // the username, never the number (§2.5).
          if (auth.username != null)
            ListTile(
              leading: Icon(Icons.qr_code_2_rounded,
                  color: scheme.onSurfaceVariant),
              title: const Text('QR code'),
              subtitle: Text(
                _qrOpen
                    ? 'Tap to hide'
                    : 'Shares @${auth.username}, not your number',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              trailing: Icon(_qrOpen ? Icons.expand_less : Icons.expand_more),
              onTap: () => setState(() => _qrOpen = !_qrOpen),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: (_qrOpen && auth.username != null)
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kSpaceLg,
                      vertical: kSpaceMd,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        padding: const EdgeInsets.all(kSpaceMd),
                        decoration: BoxDecoration(
                          // Always light behind the modules — a QR on a
                          // dark surface does not scan.
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(kRadiusLg),
                          border: Border.all(
                            color: scheme.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: QrImageView(
                          data: usernameQrPayload(auth.username!),
                          version: QrVersions.auto,
                          backgroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: kSpaceXl),
          // Two-tap inline sign-out — no dialog.
          Center(
            child: TextButton(
              onPressed: _onSignOutPressed,
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                minimumSize: const Size(180, 44),
              ),
              child: Text(
                _signOutArmed ? 'Tap again to confirm' : 'Sign out',
                style: TextStyle(
                  fontWeight:
                      _signOutArmed ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: kSpaceLg),
        ],
      ),
    );
  }

  void _onSignOutPressed() {
    if (_signOutArmed) {
      _signOutResetTimer?.cancel();
      _signOutArmed = false;
      // Fire-and-forget — _AppState's authStateChange listener handles
      // the route teardown; nothing on this screen reads context after.
      widget.authService.logout();
      return;
    }
    setState(() => _signOutArmed = true);
    _signOutResetTimer?.cancel();
    _signOutResetTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _signOutArmed = false);
    });
  }
}

// ---------------------------------------------------------------------------
// Inline-editable row — read mode shows label + value + pencil; tap to
// flip into edit mode (TextField with check / cancel). No dialogs.
// ---------------------------------------------------------------------------

/// Optional validator hook for [_InlineEditableRow]. Returns null when
/// [candidate] is acceptable; returns a short error message ("only
/// a-z, 0-9, _ allowed") to display under the field. Sync — runs on
/// every keystroke before the async availability check fires.
typedef _RowValidator = String? Function(String candidate);

/// Optional async availability check. Hits the network. Result is
/// debounced by the row state so we don't spam the server on every
/// keystroke. Null means "skip the async check entirely" (used for
/// fields that have no uniqueness constraint).
typedef _RowAvailabilityCheck = Future<_RowAvailability> Function(
    String candidate);

enum _RowAvailability { idle, checking, available, unavailable, error }

class _InlineEditableRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String placeholder;
  final int maxLength;
  final TextCapitalization textCapitalization;
  final String? valuePrefix;
  final Future<void> Function(String? value) onSave;
  final _RowValidator? validator;
  final _RowAvailabilityCheck? availabilityCheck;
  final String? unavailableMessage;

  /// Always-on explanatory line under the value in read mode.
  final String? caption;

  /// When false, an empty field is a validation error rather than
  /// "clear this".
  final bool allowEmpty;

  const _InlineEditableRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.maxLength,
    required this.textCapitalization,
    required this.onSave,
    this.valuePrefix,
    this.validator,
    this.availabilityCheck,
    this.unavailableMessage,
    this.caption,
    this.allowEmpty = true,
  });

  @override
  State<_InlineEditableRow> createState() => _InlineEditableRowState();
}

class _InlineEditableRowState extends State<_InlineEditableRow> {
  bool _editing = false;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _saving = false;

  /// Latest sync validator output for the current draft text.
  String? _validationError;

  /// Latest async availability state. `idle` until the user actually
  /// changes the field from the saved value.
  _RowAvailability _availability = _RowAvailability.idle;

  /// Debounce timer for the async availability check — avoids hitting
  /// the server on every keystroke.
  Timer? _availabilityDebounce;

  /// Latest candidate the async check is racing against. We check this
  /// before applying the result so a stale response from a previous
  /// keystroke can't overwrite the current state.
  String _availabilityInFlight = '';

  static const Duration _availabilityDebounceWindow =
      Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _InlineEditableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && widget.value != oldWidget.value) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _availabilityDebounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _enterEdit() {
    setState(() {
      _editing = true;
      _controller.text = widget.value ?? '';
      _validationError = null;
      _availability = _RowAvailability.idle;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onChanged(String raw) {
    final next = raw.trim();
    final unchanged = next == (widget.value ?? '');
    final validator = widget.validator;
    final asyncCheck = widget.availabilityCheck;
    setState(() {
      _validationError = (next.isEmpty && widget.allowEmpty) || validator == null
          ? null
          : validator(next);
      // Don't fire the network check for unchanged or sync-invalid input.
      if (asyncCheck == null || unchanged || _validationError != null) {
        _availability = _RowAvailability.idle;
      } else {
        _availability = _RowAvailability.checking;
      }
    });
    _availabilityDebounce?.cancel();
    if (asyncCheck == null || unchanged || _validationError != null) {
      _availabilityInFlight = '';
      return;
    }
    _availabilityInFlight = next;
    _availabilityDebounce = Timer(_availabilityDebounceWindow, () async {
      if (!mounted || !_editing) return;
      final candidate = _availabilityInFlight;
      if (candidate != next) return; // user kept typing
      try {
        final result = await asyncCheck(candidate);
        if (!mounted || !_editing) return;
        // If the user typed more after we fired, drop this result.
        if (_controller.text.trim() != candidate) return;
        setState(() {
          _availability = result;
        });
      } catch (_) {
        if (!mounted || !_editing) return;
        if (_controller.text.trim() != candidate) return;
        setState(() => _availability = _RowAvailability.error);
      }
    });
  }

  bool get _commitBlocked {
    if (_saving) return true;
    if (_validationError != null) return true;
    if (_availability == _RowAvailability.unavailable) return true;
    if (_availability == _RowAvailability.checking) return true;
    return false;
  }

  Future<void> _commit() async {
    if (_commitBlocked) return;
    final next = _controller.text.trim();
    final unchanged = next == (widget.value ?? '');
    if (unchanged) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(next.isEmpty ? null : next);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _editing = false;
          _availability = _RowAvailability.idle;
          _validationError = null;
        });
      }
    }
  }

  void _cancel() {
    _availabilityDebounce?.cancel();
    setState(() {
      _editing = false;
      _controller.text = widget.value ?? '';
      _validationError = null;
      _availability = _RowAvailability.idle;
    });
  }

  Widget? _buildAvailabilityIcon(ColorScheme scheme) {
    switch (_availability) {
      case _RowAvailability.checking:
        return Padding(
          padding: const EdgeInsets.all(kSpaceSm),
          child: SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onSurfaceVariant,
            ),
          ),
        );
      case _RowAvailability.available:
        return Icon(Icons.check_circle, color: Colors.green[600], size: 20);
      case _RowAvailability.unavailable:
        return Icon(Icons.cancel, color: scheme.error, size: 20);
      case _RowAvailability.error:
        return Icon(Icons.error_outline,
            color: scheme.onSurfaceVariant, size: 20);
      case _RowAvailability.idle:
        return null;
    }
  }

  String? _helperText() {
    if (_validationError != null) return _validationError;
    switch (_availability) {
      case _RowAvailability.unavailable:
        return widget.unavailableMessage ?? 'Not available';
      case _RowAvailability.available:
        return 'Available';
      case _RowAvailability.checking:
      case _RowAvailability.error:
      case _RowAvailability.idle:
        return null;
    }
  }

  Color _helperColor(ColorScheme scheme) {
    if (_validationError != null) return scheme.error;
    switch (_availability) {
      case _RowAvailability.unavailable:
        return scheme.error;
      case _RowAvailability.available:
        return Colors.green[700]!;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasValue = widget.value != null && widget.value!.isNotEmpty;

    if (_editing) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpaceMd,
          vertical: kSpaceSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(widget.icon, color: scheme.primary),
                const SizedBox(width: kSpaceMd),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    maxLength: widget.maxLength,
                    textCapitalization: widget.textCapitalization,
                    enabled: !_saving,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _commit(),
                    decoration: InputDecoration(
                      labelText: widget.label,
                      hintText: widget.placeholder,
                      prefixText: widget.valuePrefix,
                      suffixIcon: _buildAvailabilityIcon(scheme),
                      counterText: '',
                      border: const UnderlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _saving ? null : _cancel,
                  icon: const Icon(Icons.close),
                  color: scheme.onSurfaceVariant,
                  tooltip: 'Cancel',
                ),
                IconButton(
                  onPressed: _commitBlocked ? null : _commit,
                  icon: _saving
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : const Icon(Icons.check),
                  color: scheme.primary,
                  tooltip: 'Save',
                ),
              ],
            ),
            if (_helperText() != null)
              Padding(
                padding: EdgeInsets.only(
                  left: kAvatarSm + kSpaceMd,
                  top: kSpaceXs,
                ),
                child: Text(
                  _helperText()!,
                  style: textTheme.bodySmall?.copyWith(
                    color: _helperColor(scheme),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final displayValue = hasValue
        ? '${widget.valuePrefix ?? ''}${widget.value!}'
        : widget.placeholder;
    return ListTile(
      leading: Icon(widget.icon, color: scheme.onSurfaceVariant),
      title: Text(widget.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            displayValue,
            style: textTheme.bodyMedium?.copyWith(
              color: hasValue ? scheme.onSurface : scheme.onSurfaceVariant,
              fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.caption != null)
            Text(
              widget.caption!,
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
      trailing: Icon(
        Icons.edit_outlined,
        color: scheme.onSurfaceVariant,
        size: 20,
      ),
      onTap: _enterEdit,
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar — monogram from name, person glyph as fallback.
// ---------------------------------------------------------------------------

class _ProfileAvatar extends StatelessWidget {
  final String? name;
  final String? phone;
  const _ProfileAvatar({required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasName = name != null && name!.trim().isNotEmpty;
    if (hasName) {
      return Avator(text: name!, width: kAvatarXl, height: kAvatarXl);
    }
    return Container(
      width: kAvatarXl,
      height: kAvatarXl,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primaryContainer,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        size: kAvatarXl * 0.5,
        color: scheme.onPrimaryContainer,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone formatter
// ---------------------------------------------------------------------------

/// Format a stored E.164 phone (e.g. "+919876543210") as
/// "+91 98765 43210" for display.
String _formatPhone(String? raw) {
  if (raw == null || raw.isEmpty) return 'Unknown';
  if (!raw.startsWith('+')) return raw;
  final digits = raw.substring(1);
  if (digits.length < 7) return raw;
  if (digits.startsWith('91') && digits.length == 12) {
    return '+91 ${digits.substring(2, 7)} ${digits.substring(7)}';
  }
  for (final ccLen in [1, 2, 3]) {
    if (digits.length > ccLen + 6) {
      final cc = digits.substring(0, ccLen);
      final sub = digits.substring(ccLen);
      final buf = StringBuffer();
      for (var i = 0; i < sub.length; i++) {
        final fromEnd = sub.length - i;
        if (i > 0 && fromEnd % 3 == 0) buf.write(' ');
        buf.write(sub[i]);
      }
      return '+$cc $buf';
    }
  }
  return raw;
}
