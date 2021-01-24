import 'package:flutter/material.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/contactPreviewItem.dart';

class CreateGroup extends StatelessWidget {
  final List<User> _members;
  CreateGroup(this._members);
  @override
  Widget build(BuildContext context) {
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
                  onConfirm: this.onGroupNameConfirm,
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

  onGroupNameConfirm(String name) {
    print(name);
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
              text: value.isEmpty ? "G I" : value,
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
