import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vartalap_messaging_flutter/repository/auth_repository.dart';
import 'package:vartalap/widgets/keyboard.dart';

class VerifyOtpWidget extends StatefulWidget {
  const VerifyOtpWidget({super.key});

  @override
  State<StatefulWidget> createState() => _VerifyOtpState();
}

class _VerifyOtpState extends State<VerifyOtpWidget> {
  String _otp = '';
  Widget otpNumberWidget(int position) {
    return Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        border: Border.all(
          width: 1,
          color: Theme.of(context).iconTheme.color!,
        ),
        borderRadius: const BorderRadius.all(
          Radius.circular(8),
        ),
      ),
      child: (_otp.length < (position + 1))
          ? null
          : Center(
              child: Text(
              _otp[position],
            )),
    );
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
        padding: const EdgeInsets.all(10.0),
        child: Column(
          children: <Widget>[
            Expanded(
              flex: 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    'Enter 6 digits verification code sent to your number',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.clip,
                  ),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        otpNumberWidget(0),
                        otpNumberWidget(1),
                        otpNumberWidget(2),
                        otpNumberWidget(3),
                        otpNumberWidget(4),
                        otpNumberWidget(5),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                children: <Widget>[
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Consumer<AuthRepository>(
                      builder: (context, auth, _) {
                        return ElevatedButton(
                          onPressed: auth.state == AuthState.verifyingOTP
                            ? null
                            : _authenticate,
                          style: ElevatedButton.styleFrom(
                            shape: const RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(14))),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  'Confirm',
                                  style: TextStyle(color: Colors.white),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        const BorderRadius.all(Radius.circular(20)),
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
                  Expanded(
                    child: NumericKeyboard(
                      onKeyboardTap: _onKeyboardTap,
                      textColor: Theme.of(context).iconTheme.color!,
                      rightIcon: Icon(
                        Icons.backspace,
                      ),
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
            )
          ],
        ),
      ),
    );
  }

  void _onKeyboardTap(String value) {
    if (_otp.length == 6) return;
    setState(() {
      _otp = _otp + value;
    });
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

  void _authenticate() async {
    final auth = Provider.of<AuthRepository>(context, listen: false);

    try {
      debugPrint('[UI] Starting OTP verification with: $_otp');
      await auth.verifyOTP(_otp);
      debugPrint('[UI] OTP verification completed successfully');
      debugPrint('[UI] Auth state is now: ${auth.state}');

      // The navigation will be handled by the main app based on authentication state
      // No need for manual navigation here since VartalapApp will automatically
      // navigate to StartupScreen when auth.state becomes authenticated

    } catch (e) {
      debugPrint('[UI] OTP verification failed: $e');
      if (mounted) {
        showErrorDialog(context, [
          auth.lastError ?? 'Incorrect one time password! Try again'
        ]);
        // AuthRepository doesn't need clearError() as setState clears it automatically 
        // when transitioning, but if it stays in error state, we might need a way to clear.
        // However, user can just try again which calls verifyOTP and clears error.
      }
    }
  }
}
