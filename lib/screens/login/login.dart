/// Phone-number entry → OTP send.
///
/// Keeps the visual shape of v2. Wiring swapped to
/// [AuthService.sendOtp] (AUTH_CONTRACT §3.1). While the server-side
/// OTP provider is unwired (step 7), sendOtp throws
/// `UnimplementedError`; the catch block surfaces it as a network
/// failure dialog, which is the exact UX we want once the server is
/// online but temporarily unreachable. No code changes needed when
/// step 7 lands.
library vartalap.screens.login.login;

import 'package:flutter/material.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/login/verifyOtp.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/widgets/loadingIndicator.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController =
      TextEditingController(text: '+91');
  final ConfigStore _config = ConfigStore();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _onSend() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError(['Please enter a phone number.']);
      return;
    }
    _showLoading('While we send you a one-time password');
    try {
      await widget.authService.sendOtp(phone);
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loader
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyOtpScreen(authService: widget.authService),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loader
      _showError([
        'Unable to send one-time password.',
        'Please verify the phone number and try again.',
        e.toString(),
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AppLogo(size: 45),
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    child: Text(
                      _config.packageInfo.appName,
                      style: VartalapTheme.theme.appTitleStyle.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          color: Theme.of(context).iconTheme.color,
                        ),
                        children: const [
                          TextSpan(text: 'We will send you a '),
                          TextSpan(
                            text: 'One Time Password ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: 'on this mobile number'),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: TextField(
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '+91...',
                        icon: Icon(Icons.phone),
                      ),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLines: 1,
                      autofocus: true,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 5,
                    ),
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: ElevatedButton(
                      onPressed: _onSend,
                      style: ElevatedButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Next'),
                            Icon(Icons.arrow_forward_ios, size: 16),
                          ],
                        ),
                      ),
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

  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(content: LoadingIndicator(text: message)),
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
