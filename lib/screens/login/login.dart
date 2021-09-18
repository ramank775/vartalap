import 'package:flutter/material.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/login/verifyOtp.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/app_logo.dart';

class LoginScreen extends StatelessWidget {
  final TextEditingController _phoneController =
      TextEditingController(text: "+91");
  final config = ConfigStore();
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
                  Container(
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 340),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        child: AppLogo(
                          size: 45,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(top: 10),
                    child: Text(
                      config.packageInfo.appName,
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
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: "+91...",
                          icon: Icon(Icons.phone),
                        ),
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        maxLines: 1,
                        autofocus: true,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 5,
                    ),
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: ElevatedButton(
                      onPressed: () async {
                        List<String> errors = [];
                        if (_phoneController.text.isNotEmpty) {
                          bool status =
                              await UserService.sendOTP(_phoneController.text);
                          if (status) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (ctx) => VerifyOtpWidget(),
                              ),
                            );
                            return;
                          }
                          errors = [
                            'Unable to send one time password.',
                            'Please verify the phone number and try again.'
                          ];
                        } else {
                          errors.add('Plese enter a phone numer.');
                        }
                        showErrorDialog(context, errors);
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
