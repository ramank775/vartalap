import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/date_time_format.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ChatPreviewWidget extends StatelessWidget {
  final ChatPreview _chat;
  final Function _onTap;
  final Function _onLongPress;
  final bool isSelected;
  ChatPreviewWidget(
    this._chat,
    this._onTap,
    this._onLongPress, {
    this.isSelected = false,
  }) : super(
          key: Key(_chat.channel.id.toString()),
        );
  @override
  Widget build(BuildContext context) {
    final vtheme = VartalapTheme.theme;
    return Column(
      children: [
        ListTileTheme(
          selectedColor: vtheme.selectedRowColor,
          child: ListTile(
            leading: SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                children: [
                  Avator(
                    width: 42.0,
                    height: 42.0,
                    text: _chat.channel.displayName,
                  ),
                  isSelected
                      ? Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            backgroundColor: vtheme.selectedRowColor,
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
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  _chat.channel.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formatMessageTimestamp(_chat.lastMessageTimestamp),
                  style: TextStyle(fontSize: 12.0),
                ),
              ],
            ),
            subtitle: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _chat.previewContent,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15.0),
                  ),
                ),
                getWidget(context)
              ],
            ),
            onTap: () => _onTap(_chat),
            onLongPress: () => _onLongPress(_chat),
            selected: isSelected,
          ),
        ),
        Divider(
          height: 5.0,
        ),
      ],
    );
  }

  Widget getWidget(BuildContext context) {
    final vtheme = VartalapTheme.theme;
    return _chat.unreadCount > 0
        ? Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: vtheme.selectedRowColor,
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
    if (_chat.unreadCount > 9) {
      return "9+";
    }
    return _chat.unreadCount.toString();
  }
}
