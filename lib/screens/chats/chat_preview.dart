import 'package:chat_flutter_app/screens/profile_img/profile_img.dart';
import 'package:flutter/material.dart';

class ChatPreviewWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new Column(
      children: [
        new Divider(
          height: 5.0,
        ),
        new ListTile(
          leading: new ProfileImg(
              'assets/images/default-user.png', ProfileImgSize.MD),
          title: new Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              new Text(
                'Raman Kumar',
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
          onTap: () => Navigator.pushNamed(context, '/chat'),
        )
      ],
    );
  }
}
