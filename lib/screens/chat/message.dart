import 'package:vartalap/models/message.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/utils/dateTimeFormat.dart';
import 'package:vartalap/widgets/rich_message.dart';

class MessageWidget extends StatelessWidget {
  final Message _msg;
  final bool _isYou;

  final bool isSelected;
  final Function onTab;
  final Function onLongPress;
  final bool showUserInfo;

  final TextStyle textStyle = TextStyle(
    color: Colors.black,
    fontSize: 16.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
  );

  MessageWidget(this._msg, this._isYou,
      {Key key,
      this.isSelected: false,
      this.onTab,
      this.onLongPress,
      this.showUserInfo = false})
      : super(key: Key(_msg.id));

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () {
          if (this.onTab != null) {
            this.onTab(this._msg);
          }
        },
        onLongPress: () {
          if (this.onLongPress != null) {
            this.onLongPress(this._msg);
          }
        },
        child: Container(
          color: this.isSelected ? Colors.lightBlue[200] : Colors.transparent,
          constraints: BoxConstraints(
            minWidth: double.infinity,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment:
                _isYou ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    new BoxShadow(
                      color: Colors.grey[300],
                      offset: new Offset(1.0, 1.0),
                      blurRadius: 0.5,
                    )
                  ],
                  color: _isYou ? Colors.lightBlueAccent[100] : Colors.white38,
                  borderRadius: _isYou
                      ? BorderRadius.only(
                          topLeft: Radius.circular(8.0),
                          bottomLeft: Radius.circular(8.0),
                        )
                      : BorderRadius.only(
                          topRight: Radius.circular(8.0),
                          bottomRight: Radius.circular(8.0),
                        ),
                ),
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width * 0.25,
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 6.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: getMessageComponents(context),
                ),
              ),
            ],
          ),
        ));
  }

  List<Widget> getMessageComponents(BuildContext context) {
    List<Widget> _widgets = [];
    if (this.showUserInfo) {
      _widgets.add(
        Container(
          margin: EdgeInsets.only(bottom: 4),
          child: Text(
            this._msg.sender.name,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue,
            ),
          ),
        ),
      );
    }
    _widgets.add(
      Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width * 0.25,
            ),
            child: RichMessage(
              (this._msg.text ?? ''),
              textStyle,
            ),
          ),
          Container(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              children: <Widget>[
                Text(
                  formatMessageDateTime(this._msg.timestamp),
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 11.0,
                  ),
                ),
                SizedBox(
                  width: 4.0,
                ),
                _isYou ? _getIcon() : Container()
              ],
            ),
          ),
        ],
      ),
    );
    return _widgets;
  }

  Widget _getIcon() {
    IconData icon = Icons.access_time;
    Color color = Colors.white;
    switch (this._msg.state) {
      case MessageState.NEW:
        icon = Icons.access_time;
        break;
      case MessageState.SENT:
        icon = Icons.check;
        break;
      case MessageState.DELIVERED:
        icon = Icons.done_all;
        color = Colors.blueAccent;
    }

    return Icon(
      icon,
      size: 15.0,
      color: color,
    );
  }
}
