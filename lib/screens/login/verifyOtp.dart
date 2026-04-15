/// OTP entry screen — keeps the v2 visual shape, rewires submit to
/// [AuthService.verifyOtp] (AUTH_CONTRACT §3.2).
///
/// Step 7 lands the real `verifyOtp` body; until then the call throws
/// and this screen shows an error dialog. `main.dart` listens on
/// `AuthService.authStateChange` and swaps the root widget as soon as
/// [AuthService.verifyOtp] emits `true`, so this screen just calls
/// it and lets `main.dart` handle navigation.
library vartalap.screens.login.verify_otp;

import 'package:flutter/material.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/widgets/keyboard.dart';

class VerifyOtpScreen extends StatefulWidget {
  final AuthService authService;
  const VerifyOtpScreen({super.key, required this.authService});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  String _otp = '';
  bool _working = false;

  Widget _otpSlot(int position) {
    return Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        border: Border.all(
          width: 1,
          color: Theme.of(context).iconTheme.color!,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: (_otp.length < position + 1)
          ? null
          : Center(child: Text(_otp[position])),
    );
  }

  Future<void> _onConfirm() async {
    if (_otp.length < 6) return;
    final phone = widget.authService.phoneNumber;
    if (phone == null) {
      _showError(['No pending OTP flow — go back and re-enter your phone.']);
      return;
    }
    setState(() => _working = true);
    try {
      await widget.authService.verifyOtp(phone, _otp);
      // Root-level auth listener in main.dart handles the route swap
      // on success. No navigation needed here.
    } catch (e) {
      _showError(['Incorrect or expired OTP. Try again.', e.toString()]);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: Theme.of(context).iconTheme,
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(
              flex: 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const Text(
                    'Enter 6 digits verification code sent to your number',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.clip,
                  ),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(6, _otpSlot),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: ElevatedButton(
                      onPressed: _working ? null : _onConfirm,
                      style: ElevatedButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(14)),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _working ? 'Verifying...' : 'Confirm',
                              style: const TextStyle(color: Colors.white),
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: NumericKeyboard(
                      onKeyboardTap: _onKeyboardTap,
                      textColor: Theme.of(context).iconTheme.color!,
                      rightIcon: const Icon(Icons.backspace),
                      rightButtonFn: () {
                        if (_otp.isNotEmpty) {
                          setState(() {
                            _otp = _otp.substring(0, _otp.length - 1);
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onKeyboardTap(String value) {
    if (_otp.length == 6) return;
    setState(() => _otp = _otp + value);
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
