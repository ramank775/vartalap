/// The mandatory "choose your username" step — AUTH_CONTRACT §2.4,
/// mockup frame h.
///
/// Shown right after OTP verify whenever the account has no handle
/// (`isNew: true`, or any restored session whose stored profile has
/// `username == null`). There is no skip and no back: every other
/// authenticated route answers `403 USERNAME_REQUIRED` until this
/// lands, so the app has nothing to show behind it anyway.
library vartalap.screens.login.choose_username;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/username.dart';

enum _Availability { idle, checking, available, taken, error }

class ChooseUsernameScreen extends StatefulWidget {
  final AuthService authService;

  /// Called after the handle is accepted by the server. Optional — the
  /// root widget re-routes off `authService.usernameChange` on its own;
  /// this is for callers that pushed the screen themselves.
  final VoidCallback? onDone;

  const ChooseUsernameScreen({
    super.key,
    required this.authService,
    this.onDone,
  });

  @override
  State<ChooseUsernameScreen> createState() => _ChooseUsernameScreenState();
}

class _ChooseUsernameScreenState extends State<ChooseUsernameScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _inFlight = '';
  String? _validationError;
  _Availability _availability = _Availability.idle;
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ponytail: an 8-line debounce, not a shared widget. The part that
  // must not drift — the rules and the check itself — already lives in
  // utils/username.dart and AuthService.checkUsernameAvailability.
  void _onChanged(String raw) {
    final next = raw.trim().toLowerCase();
    setState(() {
      _saveError = null;
      _validationError = validateUsername(next);
      _availability = _validationError == null
          ? _Availability.checking
          : _Availability.idle;
    });
    _debounce?.cancel();
    if (_validationError != null) {
      _inFlight = '';
      return;
    }
    _inFlight = next;
    _debounce = Timer(kUsernameCheckDebounce, () async {
      if (!mounted || _inFlight != next) return;
      try {
        final result =
            await widget.authService.checkUsernameAvailability(next);
        if (!mounted || _controller.text.trim().toLowerCase() != next) return;
        setState(() => _availability =
            result.available ? _Availability.available : _Availability.taken);
      } catch (_) {
        if (!mounted || _controller.text.trim().toLowerCase() != next) return;
        setState(() => _availability = _Availability.error);
      }
    });
  }

  bool get _canContinue =>
      !_saving && _availability == _Availability.available;

  Future<void> _onContinue() async {
    if (!_canContinue) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.authService.setUsername(_controller.text.trim().toLowerCase());
      widget.onDone?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          // A PATCH can still lose the uniqueness race (§4.5) after a
          // clean availability check.
          _availability = _Availability.taken;
          _saveError = 'Could not claim that username. Try another.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _helper() {
    if (_saveError != null) return _saveError;
    if (_validationError != null) return _validationError;
    final handle = _controller.text.trim().toLowerCase();
    return switch (_availability) {
      _Availability.available => '@$handle is available',
      _Availability.taken => '@$handle is taken. Try another.',
      _Availability.checking => 'Checking availability…',
      _Availability.error => 'Could not check right now.',
      _Availability.idle => null,
    };
  }

  Color _helperColor(ColorScheme scheme) {
    if (_saveError != null || _validationError != null) return scheme.error;
    return switch (_availability) {
      _Availability.available => Colors.green[700]!,
      _Availability.taken => scheme.error,
      _ => scheme.onSurfaceVariant,
    };
  }

  Widget? _suffix(ColorScheme scheme) => switch (_availability) {
        _Availability.checking => Padding(
            padding: const EdgeInsets.all(kSpaceMd),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        _Availability.available =>
          Icon(Icons.check_circle, color: Colors.green[600]),
        _Availability.taken => Icon(Icons.cancel, color: scheme.error),
        _Availability.error =>
          Icon(Icons.error_outline, color: scheme.onSurfaceVariant),
        _Availability.idle => null,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final helper = _helper();

    // Non-dismissible: no back button, and the system back gesture is
    // swallowed. §2.4 has no skip.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(kSpaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: kSpaceLg),
                Text('Choose your username', style: text.headlineMedium),
                const SizedBox(height: kSpaceSm),
                Text(
                  'A username lets people reach you without knowing your '
                  'number, and is how you appear to anyone who has not '
                  'saved you.',
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: kSpaceXl),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_saving,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._]')),
                  ],
                  onChanged: _onChanged,
                  onSubmitted: (_) => _onContinue(),
                  decoration: InputDecoration(
                    prefixText: '@',
                    hintText: 'username',
                    counterText: '',
                    suffixIcon: _suffix(scheme),
                  ),
                ),
                if (helper != null)
                  Padding(
                    padding: const EdgeInsets.only(top: kSpaceSm),
                    child: Text(
                      helper,
                      style: text.bodySmall
                          ?.copyWith(color: _helperColor(scheme)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: kSpaceXs),
                  child: Text(
                    kUsernameRulesHint,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _canContinue ? _onContinue : null,
                  child: _saving
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Text('Continue'),
                ),
                const SizedBox(height: kSpaceSm),
                Text(
                  'Your username is how people find you. '
                  'Your phone number stays private.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
