/// OTP entry screen — uses a standard 6-digit PIN input.
library vartalap.screens.login.verify_otp;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';

class VerifyOtpScreen extends StatefulWidget {
  final AuthService authService;
  const VerifyOtpScreen({super.key, required this.authService});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) return;
    final phone = widget.authService.phoneNumber;
    if (phone == null) {
      _showError(['No pending OTP flow — go back and re-enter your phone.']);
      return;
    }
    setState(() => _working = true);
    try {
      await widget.authService.verifyOtp(phone, otp);
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
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kSpaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: kSpaceXl),
              Text(
                'Verification',
                style: textTheme.headlineMedium,
              ),
              const SizedBox(height: kSpaceSm),
              Text(
                'Enter the 6-digit code sent to your number',
                style: textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: kSpaceXl),
              // OTP input with individual character display
              _OtpInput(
                controller: _otpController,
                onCompleted: _onConfirm,
              ),
              const SizedBox(height: kSpaceXl),
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
              const SizedBox(height: kSpaceMd),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Change phone number',
                    style: TextStyle(color: scheme.primary),
                  ),
                ),
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

    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: Column(
        children: [
          // Hidden TextField that captures input
          SizedBox(
            height: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
              ),
              style: const TextStyle(color: Colors.transparent),
            ),
          ),
          // Visual digit boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              final filled = i < otp.length;
              final active = i == otp.length && _focusNode.hasFocus;
              return Container(
                width: 48,
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
              );
            }),
          ),
        ],
      ),
    );
  }
}
