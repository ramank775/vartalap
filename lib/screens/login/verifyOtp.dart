import 'package:flutter/material.dart';
import 'package:vartalap/screens/keyboard/keyboard.dart';
import 'package:vartalap/services/user_service.dart';

class VerifyOtpWidget extends StatefulWidget {
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
          border: Border.all(color: Colors.black, width: 0),
          borderRadius: const BorderRadius.all(Radius.circular(8))),
      child: (_otp.length < (position + 1))
          ? null
          : Center(
              child: Text(
              _otp[position],
              style: TextStyle(color: Colors.black),
            )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Container(
            padding: EdgeInsets.all(10.0),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(20)),
                color: Theme.of(context).primaryColor.withAlpha(20)),
            child: Icon(
              Icons.arrow_back_ios,
              color: Theme.of(context).primaryColor,
              size: 16,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Enter 6 digits verification code sent to your number',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.clip,
                    ),
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
              flex: 3,
              child: Column(
                children: <Widget>[
                  Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: RaisedButton(
                      onPressed: () async {
                        bool result = await UserService.authenicate(this._otp);
                        if (!result) {
                          showErrorDialog(context,
                              ['Incorrect one time password! Try again']);
                          return;
                        }
                        Navigator.of(context)
                            .pushNamedAndRemoveUntil('/', (route) => false);
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
                              'Confirm',
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
                  ),
                  Expanded(
                    child: NumericKeyboard(
                      onKeyboardTap: _onKeyboardTap,
                      textColor: Theme.of(context).primaryColor,
                      rightIcon: Icon(
                        Icons.backspace,
                        color: Theme.of(context).primaryColor,
                      ),
                      rightButtonFn: () {
                        if (_otp.length > 0) {
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
        FlatButton(
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
