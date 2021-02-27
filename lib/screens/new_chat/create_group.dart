import 'package:flutter/material.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/contactPreviewItem.dart';
import 'package:vartalap/widgets/loadingIndicator.dart';

class CreateGroup extends StatelessWidget {
  final List<User> _members;
  CreateGroup(this._members);
  @override
  Widget build(BuildContext context) {
    onGroupNameConfirm(String name) async {
      if (name.isNotEmpty) {
        try {
          showLoadingIndicator(context);
          var chat = await ChatService.newGroupChat(name, this._members);
          Navigator.of(context).pop();
          Navigator.of(context).pop(chat);
        } on Exception catch (e) {
          showErrorDialog(context, [
            'Error while creating new group.',
            'Make sure you are connected to internet.'
          ]);
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 2.0),
              child: Text(
                'New Group',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Container(
          margin: EdgeInsets.only(left: 20, top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                child: _CreateGroupForm(
                  onConfirm: onGroupNameConfirm,
                ),
              ),
              Container(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(context).textTheme.bodyText1.color),
                    children: [
                      TextSpan(text: "Members:"),
                      TextSpan(
                        text: _members.length.toString(),
                      )
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 10,
                child: GridView.count(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  crossAxisCount: 5,
                  childAspectRatio: 0.5,
                  children:
                      _members.map((e) => ContactPreviewItem(user: e)).toList(),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void showLoadingIndicator(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            content: LoadingIndicator(
              text: "While we are creating group for you.",
            ),
          ),
        );
      },
    );
  }

  void showErrorDialog(BuildContext context, List<String> error) {
    var dialog = AlertDialog(
      title: Text('Error'),
      content: SingleChildScrollView(
        child: ListBody(
          children: error.map((err) => Text(err)).toList(),
        ),
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

class _CreateGroupForm extends StatefulWidget {
  final Function(String) onConfirm;
  _CreateGroupForm({Key key, @required this.onConfirm}) : super(key: key);

  @override
  __CreateGroupFormState createState() => __CreateGroupFormState();
}

class __CreateGroupFormState extends State<_CreateGroupForm> {
  String value = "";
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.rectangle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ListTile(
            leading: Avator(
              width: 55,
              height: 55,
              text: value.isEmpty ? "Group Icon" : value,
            ),
            title: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                maxLines: 1,
                autofocus: true,
                style: TextStyle(
                  fontSize: 18,
                ),
                onChanged: (val) {
                  setState(() {
                    this.value = val;
                  });
                },
              ),
            ),
            subtitle: Container(),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                RaisedButton(
                  onPressed: () async {
                    if (value.isNotEmpty) {
                      if (this.widget.onConfirm != null) {
                        this.widget.onConfirm(value);
                      }
                    } else {
                      final snackBar = SnackBar(
                          content: Text('Group name can\'t be empty!'));

                      Scaffold.of(context).showSnackBar(snackBar);
                    }
                  },
                  color: Theme.of(context).primaryColor,
                  shape: const CircleBorder(side: BorderSide.none),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: Icon(
                      Icons.done,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
