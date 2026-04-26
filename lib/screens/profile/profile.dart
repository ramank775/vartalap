/// User profile screen — everything inline-editable, no popups.
library vartalap.screens.profile;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/avator.dart';

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
          // Phone — read-only.
          ListTile(
            leading: Icon(Icons.phone_outlined, color: scheme.onSurfaceVariant),
            title: const Text('Phone'),
            subtitle: Text(
              _formatPhone(phone),
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Divider(height: 1, indent: kSpaceMd, endIndent: kSpaceMd),
          // QR — inline expand/collapse instead of a popup.
          ListTile(
            leading: Icon(Icons.qr_code_2_rounded,
                color: scheme.onSurfaceVariant),
            title: const Text('QR code'),
            subtitle: Text(
              _qrOpen ? 'Tap to hide' : 'Scan to add me',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            trailing: Icon(_qrOpen ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _qrOpen = !_qrOpen),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _qrOpen
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kSpaceLg,
                      vertical: kSpaceMd,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(kRadiusLg),
                          border: Border.all(
                            color: scheme.outlineVariant,
                            width: 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.qr_code_2_rounded,
                              size: 96,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: kSpaceSm),
                            Text(
                              'QR sharing coming soon',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
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

class _InlineEditableRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? value;
  final String placeholder;
  final int maxLength;
  final TextCapitalization textCapitalization;
  final String? valuePrefix;
  final Future<void> Function(String? value) onSave;

  const _InlineEditableRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.maxLength,
    required this.textCapitalization,
    required this.onSave,
    this.valuePrefix,
  });

  @override
  State<_InlineEditableRow> createState() => _InlineEditableRowState();
}

class _InlineEditableRowState extends State<_InlineEditableRow> {
  bool _editing = false;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _saving = false;

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
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _enterEdit() {
    setState(() {
      _editing = true;
      _controller.text = widget.value ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _commit() async {
    if (_saving) return;
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
        });
      }
    }
  }

  void _cancel() {
    setState(() {
      _editing = false;
      _controller.text = widget.value ?? '';
    });
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
        child: Row(
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
                onSubmitted: (_) => _commit(),
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: widget.placeholder,
                  prefixText: widget.valuePrefix,
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
              onPressed: _saving ? null : _commit,
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
      );
    }

    final displayValue = hasValue
        ? '${widget.valuePrefix ?? ''}${widget.value!}'
        : widget.placeholder;
    return ListTile(
      leading: Icon(widget.icon, color: scheme.onSurfaceVariant),
      title: Text(widget.label),
      subtitle: Text(
        displayValue,
        style: textTheme.bodyMedium?.copyWith(
          color: hasValue ? scheme.onSurface : scheme.onSurfaceVariant,
          fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
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
