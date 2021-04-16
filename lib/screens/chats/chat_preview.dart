import 'package:vartalap/models/chat.dart';
// import 'package:vartalap/screens/profile_img/profile_img.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/utils/dateTimeFormat.dart';
import 'package:vartalap/widgets/avator.dart';

class ChatPreviewWidget extends StatelessWidget {
  final ChatPreview _chat;
  final Function _onTap;
  final Function _onLongPress;
  final bool isSelected;
  ChatPreviewWidget(this._chat, this._onTap, this._onLongPress,
      {this.isSelected: false})
      : super(key: Key(_chat.id));
  @override
  Widget build(BuildContext context) {
    return new Column(
      children: [
        new Divider(
          height: 5.0,
        ),
        new ListTile(
          leading: Container(
            width: 42,
            height: 42,
            child: Stack(
              children: [
                Avator(
                  width: 42.0,
                  height: 42.0,
                  text: this._chat.title,
                ),
                this.isSelected
                    ? Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          radius: 10,
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      )
                    : Container()
              ],
            ),
          ),
          // leading: new ProfileImg(
          //     this._chat.pic ?? 'assets/images/default-user.png',
          //     ProfileImgSize.MD),
          title: new Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              new Text(
                this._chat.title,
                style: new TextStyle(fontWeight: FontWeight.bold),
              ),
              new Text(
                (this._chat.ts) != 0
                    ? formatMessageDateTime(this._chat.ts)
                    : '',
                style: new TextStyle(color: Colors.grey, fontSize: 14.0),
              ),
            ],
          ),
          subtitle: new Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  this.getDisplayContext(),
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: new TextStyle(color: Colors.grey[700], fontSize: 15.0),
                ),
              ),
              getWidget()
            ],
          ),
          onTap: () => this._onTap(this._chat),
          onLongPress: () => this._onLongPress(this._chat),
          selected: this.isSelected,
        )
      ],
    );
  }

  Widget getWidget() {
    return this._chat.unread > 0
        ? Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.greenAccent,
            ),
            child: Center(
                child: Text(
              getUnreadCountText(),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11),
            )),
          )
        : Text("");
  }

  String getDisplayContext() {
    String content = this._chat.content;
    // if (content.length > 30) {
    //   return content.substring(0, 26) + "...";
    // }
    return content;
  }

  String getUnreadCountText() {
    if (this._chat.unread > 9) {
      return "9+";
    }
    return this._chat.unread.toString();
  }
}
