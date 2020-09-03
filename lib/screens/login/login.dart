import 'package:flutter/material.dart';
import 'package:vartalap/screens/login/verifyOtp.dart';
import 'package:vartalap/services/user_service.dart';

class LoginScreen extends StatelessWidget {
  final TextEditingController _phoneController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    child: Stack(
                      children: <Widget>[
                        Container(
                          decoration: BoxDecoration(color: Colors.blueAccent),
                        ),
                        Center(
                          child: Container(
                            constraints: const BoxConstraints(maxHeight: 340),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            child: CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 50.0,
                              child: Icon(Icons.chat_bubble_outline,
                                  color: Colors.blueAccent, size: 50.0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text("Vartalap",
                          style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontSize: 30,
                              fontWeight: FontWeight.w800)))
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Column(
                children: <Widget>[
                  Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(children: <TextSpan>[
                          TextSpan(
                              text: 'We will send you an ',
                              style: TextStyle(
                                  color: Theme.of(context).primaryColor)),
                          TextSpan(
                              text: 'One Time Password ',
                              style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.bold)),
                          TextSpan(
                              text: 'on this mobile number',
                              style: TextStyle(
                                  color: Theme.of(context).primaryColor)),
                        ]),
                      )),
                  Container(
                    height: 40,
                    constraints: const BoxConstraints(maxWidth: 500),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
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
                        horizontal: 20, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: RaisedButton(
                      onPressed: () async {
                        if (_phoneController.text.isNotEmpty) {
                          bool status =
                              await UserService.sendOTP(_phoneController.text);
                          if (status) {
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (ctx) => VerifyOtpWidget()));
                            return;
                          }
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.red,
                            content: Text(
                              'Unable to send one time password. Please try again after sometime',
                              style: TextStyle(color: Colors.white),
                            ),
                          );
                        } else {
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.red,
                            content: Text(
                              'Please enter a phone number',
                              style: TextStyle(color: Colors.white),
                            ),
                          );
                        }
                      },
                      color: Theme.of(context).primaryColor,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14))),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              'Next',
                              style: TextStyle(color: Colors.white),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(20)),
                                color: Theme.of(context).primaryColorLight,
                              ),
                              child: Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.white,
                                size: 16,
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
