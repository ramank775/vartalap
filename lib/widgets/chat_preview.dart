import 'package:vartalap/models/chat.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
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
    final vtheme = VartalapTheme.theme;
    final theme = vtheme.appTheme;
    return new Column(
      children: [
        ListTileTheme(
          selectedColor: theme.selectedRowColor,
          child: ListTile(
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
                            backgroundColor: theme.selectedRowColor,
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
                  style: new TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                new Text(
                  (this._chat.ts) != 0
                      ? formatMessageTimestamp(this._chat.ts)
                      : '',
                  style: new TextStyle(fontSize: 12.0),
                ),
              ],
            ),
            subtitle: new Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    this._chat.content,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: new TextStyle(fontSize: 15.0),
                  ),
                ),
                getWidget(context)
              ],
            ),
            onTap: () => this._onTap(this._chat),
            onLongPress: () => this._onLongPress(this._chat),
            selected: this.isSelected,
          ),
        ),
        new Divider(
          height: 5.0,
        ),
      ],
    );
  }

  Widget getWidget(BuildContext context) {
    return this._chat.unread > 0
        ? Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).selectedRowColor,
            ),
            child: Center(
                child: Text(
              _getUnreadCountText(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: Colors.white,
              ),
            )),
          )
        : Text("");
  }

  String _getUnreadCountText() {
    if (this._chat.unread > 9) {
      return "9+";
    }
    return this._chat.unread.toString();
  }
}
