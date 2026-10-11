/// Phone-number entry → OTP send.
library vartalap.screens.login.login;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/login/verifyOtp.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/countries.dart';
import 'package:vartalap/utils/phone_number.dart';
import 'package:vartalap/widgets/app_logo.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Dial code digits, no `+`. Kept in sync with [_country] both ways:
  /// picking a country fills it, typing a code picks the country.
  final TextEditingController _countryCodeController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  Country? _country;
  bool _loading = false;

  /// The E.164 form of the two fields combined — recomputed on every
  /// keystroke to gate the Send OTP button.
  String get _e164 =>
      normalizePhoneNumber(
        _phoneController.text.trim(),
        countryCode: '+${_countryCodeController.text}',
      ) ??
      '';
  bool get _isValid => _country != null && isValidE164(_e164);

  @override
  void initState() {
    super.initState();
    _loadCountry();
    _countryCodeController.addListener(_onCodeChanged);
    _phoneController.addListener(_onFieldChanged);
  }

  Future<void> _loadCountry() async {
    final country = await defaultCountry();
    // Don't clobber a code the user already started typing.
    if (!mounted || _countryCodeController.text.isNotEmpty) return;
    _setCountry(country);
  }

  void _setCountry(Country country) {
    _country = country;
    _countryCodeController.text = country.dialCode;
  }

  void _onCodeChanged() => setState(() {
        _country = countryForDialCode(
          _countryCodeController.text,
          current: _country,
        );
      });

  void _onFieldChanged() => setState(() {});

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CountrySheet(),
    );
    if (picked != null) setState(() => _setCountry(picked));
  }

  @override
  void dispose() {
    _countryCodeController.removeListener(_onCodeChanged);
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
    await prefs.setString(kCountryIsoPrefKey, _country!.iso);
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
        // The theme's app bar is primary-coloured with light icons; on a
        // transparent bar over the surface they would be invisible.
        foregroundColor: scheme.onSurface,
        systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        elevation: 0,
      ),
      body: SafeArea(
        // Scrolls instead of overflowing when the keyboard leaves less
        // room than the logo and form halves need.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(kSpaceLg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 2 * kSpaceLg,
              ),
              child: IntrinsicHeight(
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
                            child: InkWell(
                              key: const Key('countryPicker'),
                              borderRadius: BorderRadius.circular(kRadiusMd),
                              onTap: _pickCountry,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  suffixIcon: Icon(Icons.arrow_drop_down),
                                ),
                                child: Text(
                                  _country == null
                                      ? 'Invalid country code'
                                      : '${_country!.flag}  ${_country!.name}',
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleMedium?.copyWith(
                                    color: _country == null
                                        ? scheme.error
                                        : scheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: kSpaceSm),
                          Container(
                            constraints: const BoxConstraints(maxWidth: 500),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 96,
                                  child: TextField(
                                    key: const Key('countryCodeField'),
                                    controller: _countryCodeController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(4),
                                    ],
                                    maxLines: 1,
                                    style: textTheme.titleLarge,
                                    decoration: InputDecoration(
                                      prefixText: '+',
                                      prefixStyle: textTheme.titleLarge,
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
                                    onSubmitted: (_) {
                                      if (!_loading) _onSend();
                                    },
                                    style: textTheme.titleLarge,
                                    decoration: const InputDecoration(
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

/// Searchable country list, returned to the phone screen on tap.
class _CountrySheet extends StatefulWidget {
  const _CountrySheet();

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().replaceAll('+', '');
    final matches = kCountries
        .where(
            (c) => c.name.toLowerCase().contains(q) || c.dialCode.startsWith(q))
        .toList();
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(kSpaceMd),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search country or code',
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              // Keep the last rows reachable above the keyboard.
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              itemCount: matches.length,
              itemBuilder: (_, i) {
                final c = matches[i];
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(c.name),
                  trailing: Text('+${c.dialCode}'),
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
