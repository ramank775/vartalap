/// OTP entry screen — uses a standard 6-digit PIN input.
library vartalap.screens.login.verify_otp;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';

class VerifyOtpScreen extends StatefulWidget {
  final AuthService authService;

  /// The E.164 number the code was just sent to; only the phone screen
  /// opens this one, right after a successful send.
  final String phone;

  /// How long the server wants before another send (its `retryAfter`).
  final Duration retryAfter;

  const VerifyOtpScreen({
    super.key,
    required this.authService,
    required this.phone,
    required this.retryAfter,
  });

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _working = false;
  bool _resending = false;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendCountdown(widget.retryAfter);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  // ponytail: ticks a counter rather than comparing wall-clock deadlines,
  // so it can run late if Android stalls the timer in the background; the
  // server still enforces the real limit.
  void _startResendCountdown(Duration wait) {
    _resendTimer?.cancel();
    _resendIn = wait.inSeconds;
    if (_resendIn <= 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _onResend() async {
    setState(() => _resending = true);
    try {
      final sent = await widget.authService.sendOtp(widget.phone);
      if (!mounted) return;
      _otpController.clear();
      setState(() => _startResendCountdown(sent.retryAfter));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New code sent to ${widget.phone}')),
      );
    } catch (e) {
      _showError(['Unable to resend the code.', e.toString()]);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _onConfirm() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) return;
    setState(() => _working = true);
    try {
      await widget.authService.verifyOtp(widget.phone, otp);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    } catch (e) {
      _showError(['Incorrect or expired OTP. Try again.', e.toString()]);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        // The theme's app bar is primary-coloured with light icons; on a
        // transparent bar over the surface they would be invisible.
        foregroundColor: scheme.onSurface,
        systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        elevation: 0,
      ),
      body: SafeArea(
        // Scrolls so Confirm stays reachable above the keyboard.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(kSpaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            // Spacing is sized so Confirm and the Resend row stay above the
            // keyboard on a 360x760dp phone.
            children: [
              Text(
                'Verification',
                style: textTheme.headlineMedium,
              ),
              const SizedBox(height: kSpaceSm),
              Text(
                'Enter the 6-digit code sent to ${widget.phone}',
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: kSpaceLg),
              // OTP input with individual character display
              _OtpInput(
                controller: _otpController,
                onCompleted: _onConfirm,
              ),
              const SizedBox(height: kSpaceLg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _working ? null : _onConfirm,
                  child: _working
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Text('Confirm'),
                ),
              ),
              const SizedBox(height: kSpaceSm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Change number'),
                  ),
                  TextButton(
                    key: const Key('resendButton'),
                    onPressed: _resendIn > 0 || _resending ? null : _onResend,
                    child: Text(
                      _resendIn > 0
                          ? 'Resend code in ${_resendIn ~/ 60}:'
                              '${(_resendIn % 60).toString().padLeft(2, '0')}'
                          : 'Resend code',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(List<String> messages) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: SingleChildScrollView(
          child: ListBody(children: messages.map((m) => Text(m)).toList()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Individual OTP digit display backed by a hidden TextField.
class _OtpInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onCompleted;

  const _OtpInput({required this.controller, required this.onCompleted});

  @override
  State<_OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<_OtpInput> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    if (widget.controller.text.length == 6) {
      widget.onCompleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final otp = widget.controller.text;

    // Boxes share the width (a 360dp phone has ~312dp to give), capped at
    // 56dp each so they don't balloon on tablets.
    final boxes = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 6 * 56),
      child: Row(
        children: List.generate(6, (i) {
          final filled = i < otp.length;
          final active = i == otp.length && _focusNode.hasFocus;
          return Expanded(
              child: Container(
            height: 56,
            margin: const EdgeInsets.symmetric(horizontal: kSpaceXs),
            decoration: BoxDecoration(
              color: filled
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(kRadiusSm),
              border: Border.all(
                color: active
                    ? scheme.primary
                    : filled
                        ? scheme.primary.withValues(alpha: 0.5)
                        : scheme.outlineVariant,
                width: active ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: filled
                ? Text(
                    otp[i],
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ));
        }),
      ),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        // Real, sized, but fully transparent TextField — owns input + IME.
        // Sized to match the boxes so it can actually receive focus and the
        // soft keyboard. Tap-through is handled by the GestureDetector below.
        Opacity(
          opacity: 0,
          child: SizedBox(
            height: 56,
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              onSubmitted: (_) => widget.onCompleted(),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
              ),
            ),
          ),
        ),
        // Visual digit boxes painted on top; tap routes focus to the field.
        GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: boxes,
        ),
      ],
    );
  }
}
