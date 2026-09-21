/// Phone-number entry → OTP send.
library vartalap.screens.login.login;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/login/verifyOtp.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/phone_number.dart';
import 'package:vartalap/widgets/app_logo.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _countryCodeController =
      TextEditingController(text: kDefaultCountryCode);
  final TextEditingController _phoneController = TextEditingController();
  bool _loading = false;

  /// The E.164 form of the two fields combined — recomputed on every
  /// keystroke to gate the Send OTP button.
  String get _e164 => normalizePhoneNumber(
        _phoneController.text.trim(),
        countryCode: _countryCodeController.text.trim(),
      ) ??
      '';
  bool get _isValid => isValidE164(_e164);

  @override
  void initState() {
    super.initState();
    _loadCountryCode();
    _countryCodeController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
  }

  Future<void> _loadCountryCode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kCountryCodePrefKey);
    if (saved == null || !mounted) return;
    _countryCodeController.text = saved;
  }

  void _onFieldChanged() => setState(() {});

  @override
  void dispose() {
    _countryCodeController.removeListener(_onFieldChanged);
    _phoneController.removeListener(_onFieldChanged);
    _countryCodeController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _onSend() async {
    if (!_isValid) {
      _showError(['Please enter a valid phone number with country code.']);
      return;
    }
    final phone = _e164;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kCountryCodePrefKey, _countryCodeController.text.trim());
    setState(() => _loading = true);
    try {
      await widget.authService.sendOtp(phone);
      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyOtpScreen(authService: widget.authService),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError([
        'Unable to send one-time password.',
        'Please verify the phone number and try again.',
        e.toString(),
      ]);
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
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLogo(size: 40),
                    const SizedBox(height: kSpaceMd),
                    Text(
                      ConfigStore().packageInfo.appName,
                      style: textTheme.headlineMedium?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'We will send you a one-time password on this mobile number',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: kSpaceLg),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 72,
                            child: TextField(
                              key: const Key('countryCodeField'),
                              controller: _countryCodeController,
                              keyboardType: TextInputType.phone,
                              maxLines: 1,
                              style: textTheme.titleLarge,
                              decoration: const InputDecoration(
                                hintText: '+91',
                              ),
                            ),
                          ),
                          const SizedBox(width: kSpaceSm),
                          Expanded(
                            child: TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              maxLines: 1,
                              autofocus: true,
                              style: textTheme.titleLarge,
                              decoration: InputDecoration(
                                prefixIcon: Icon(
                                  Icons.phone_outlined,
                                  color: scheme.onSurfaceVariant,
                                ),
                                hintText: 'Phone number',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: kSpaceLg),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            (_loading || !_isValid) ? null : _onSend,
                        child: _loading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.onPrimary,
                                ),
                              )
                            : const Text('Next'),
                      ),
                    ),
                  ],
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
