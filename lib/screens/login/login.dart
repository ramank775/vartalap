import 'package:country_codes/country_codes.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/models/auth_models.dart';
import 'package:vartalap/screens/login/verify_otp.dart';
import 'package:vartalap/services/vartalap_authenticated_client.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/widgets/loading_indicator.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _completePhoneNumber = '';
  String? _initialCountryCode;

  @override
  void initState() {
    super.initState();
    _loadDeviceCountryCode();
  }

  Future<void> _loadDeviceCountryCode() async {
    try {
      await CountryCodes.init();
      final locale = CountryCodes.getDeviceLocale();
      setState(() {
        _initialCountryCode = locale?.countryCode ?? 'IN';
      });
    } catch (e) {
      // Fallback to India if country detection fails
      setState(() {
        _initialCountryCode = 'IN';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          children: <Widget>[
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 340),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: AppLogo(
                        size: 45,
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(top: 10),
                    child: Text(
                      AppConfig.packageInfo.appName,
                      style: VartalapTheme.theme.appTitleStyle.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: <TextSpan>[
                          TextSpan(
                            text: 'We will send you an ',
                          ),
                          TextSpan(
                            text: 'One Time Password ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: 'on this mobile number',
                          ),
                        ],
                        style: TextStyle(
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _initialCountryCode == null
                        ? const SizedBox.shrink()
                        : IntlPhoneField(
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Phone Number',
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                              counterText: '',
                              isDense: true,
                            ),
                            dropdownIconPosition: IconPosition.trailing,
                            flagsButtonPadding: const EdgeInsets.symmetric(horizontal: 8),
                            initialCountryCode: _initialCountryCode,
                            showCountryFlag: true,
                            disableLengthCheck: true,
                            onChanged: (phone) {
                              setState(() {
                                _completePhoneNumber = phone.completeNumber;
                              });
                            },
                            autofocus: true,
                          ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 5,
                    ),
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Consumer<VartalapAuthenticatedClient>(
                      builder: (context, authClient, _) {
                        return ElevatedButton(
                          onPressed: authClient.state == AuthState.sendingOTP
                            ? null
                            : () async {
                              List<String> errors = [];
                              if (_completePhoneNumber.isNotEmpty) {
                                try {
                                  showLoadingIndicator(
                                      context, "While we send you one time password");

                                  await authClient.sendOTP(_completePhoneNumber);

                                  if (context.mounted) {
                                    Navigator.of(context).pop(); // close the loader

                                    if (authClient.state == AuthState.otpSent) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (ctx) => VerifyOtpWidget(),
                                        ),
                                      );
                                      return;
                                    } else if (authClient.state == AuthState.error) {
                                      errors = [
                                        authClient.lastError ?? 'Unable to send one time password.',
                                        'Please verify the phone number and try again.'
                                      ];
                                    }
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    Navigator.of(context).pop(); // close the loader
                                    errors = [
                                      'Unable to send one time password.',
                                      'Please verify the phone number and try again.'
                                    ];
                                  }
                                }
                              } else {
                                errors.add('Please enter a phone number.');
                              }
                              if (context.mounted && errors.isNotEmpty) {
                                showErrorDialog(context, errors);
                              }
                            },
                          style: ElevatedButton.styleFrom(
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(14),
                              ),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 8,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  'Next',
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(16),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void showLoadingIndicator(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: LoadingIndicator(
              text: message,
            ),
          ),
        );
      },
    );
  }

  void showErrorDialog(BuildContext context, List<String> messages) {
    var contents = messages.map((e) => Text(e)).toList();
    var dialog = AlertDialog(
      title: Text("Error"),
      content: SingleChildScrollView(
        child: ListBody(children: contents),
      ),
      actions: [
        TextButton(
          child: Text('OK'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );

    showDialog(
      context: context,
      builder: (context) => dialog,
    );
  }
}
