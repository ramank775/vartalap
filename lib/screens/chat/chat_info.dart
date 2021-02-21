import 'package:flutter/material.dart';
import 'package:vartalap/models/chat.dart';
import 'package:vartalap/screens/new_chat/contact.dart';
import 'package:vartalap/widgets/avator.dart';

class ChatInfo extends StatelessWidget {
  final Chat _chat;

  const ChatInfo(this._chat, {Key key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    var users = this._chat.users;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 80,
              color: Theme.of(context).primaryColor,
              child: ListTile(
                leading: CircleAvatar(
                  radius: 30,
                  child: Avator(
                    height: 50,
                    width: 50,
                    text: this._chat.title,
                  ),
                ),
                title: Text(
                  this._chat.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  "${users.length} members",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Card(
              elevation: 5,
              child: FlatButton(
                child: ListTile(
                  leading: Icon(
                    Icons.group_add,
                    size: 30,
                    color: Theme.of(context).primaryColor,
                  ),
                  title: Text(
                    "Add members",
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                onPressed: () {},
              ),
            ),
            Card(
              elevation: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: MediaQuery.of(context).size.width,
                    margin: EdgeInsets.only(left: 25, top: 10, bottom: 5),
                    child: Text(
                      "Members",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).primaryColor,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                  Divider(
                    thickness: 2,
                  ),
                  ...users.map((u) => ContactItem(user: u)).toList(),
                ],
              ),
            ),
            Card(
              elevation: 5,
              child: FlatButton(
                child: ListTile(
                  leading: Icon(
                    Icons.exit_to_app_outlined,
                    color: Colors.red,
                  ),
                  title: Text(
                    "Exit group",
                    style: TextStyle(
                      color: Colors.red,
                    ),
                  ),
                ),
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}
