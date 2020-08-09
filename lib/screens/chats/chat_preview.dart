import 'package:chat_flutter_app/models/chat.dart';
import 'package:chat_flutter_app/screens/profile_img/profile_img.dart';
import 'package:flutter/material.dart';

class ChatPreviewWidget extends StatelessWidget {
  final Chat _chat;

  const ChatPreviewWidget(this._chat, {Key key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return new Column(
      children: [
        new Divider(
          height: 5.0,
        ),
        new ListTile(
          leading: new ProfileImg(
              this._chat.pic ?? 'assets/images/default-user.png',
              ProfileImgSize.MD),
          title: new Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              new Text(
                this._chat.title,
                style: new TextStyle(fontWeight: FontWeight.bold),
              ),
              new Text(
                'Today',
                style: new TextStyle(color: Colors.grey, fontSize: 14.0),
              ),
            ],
          ),
          subtitle: new Container(
            padding: const EdgeInsets.only(top: 5.0),
            child: new Text(
              'This is a test message',
              style: new TextStyle(color: Colors.grey, fontSize: 15.0),
            ),
          ),
          onTap: () {
            Navigator.pushNamed(context, '/chat', arguments: _chat);
          },
        )
      ],
    );
  }
}
