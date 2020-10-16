import 'package:vartalap/models/message.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/utils/dateTimeFormat.dart';

class MessageWidget extends StatelessWidget {
  static final RegExp emojiRegex = RegExp(
      r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])');
  final Message _msg;
  final bool _isYou;

  final bool isSelected;
  final Function onTab;
  final Function onLongPress;

  final TextStyle textStyle = TextStyle(
    color: Colors.black,
    fontSize: 16.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
  );

  MessageWidget(this._msg, this._isYou,
      {Key key, this.isSelected: false, this.onTab, this.onLongPress})
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Container(
                      constraints: BoxConstraints(
                        minWidth: MediaQuery.of(context).size.width * 0.25,
                      ),
                      child: RichText(
                        text: TextSpan(
                          children:
                              generateMessageTextSpans(this._msg.text ?? ''),
                          style: textStyle,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
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
                  ],
                ),
              ),
            ],
          ),
        ));
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

  List<TextSpan> generateMessageTextSpans(String text) {
    List<TextSpan> spans = [];
    final TextStyle emojiStyle = textStyle.copyWith(
      fontSize: (textStyle.fontSize * 1.3),
      letterSpacing: 2,
    );

    text.splitMapJoin(
      emojiRegex,
      onMatch: (m) {
        spans.add(
          TextSpan(
            text: m.group(0),
            style: emojiStyle,
          ),
        );
        return "";
      },
      onNonMatch: (s) {
        spans.add(TextSpan(text: s));
        return "";
      },
    );
    return spans;
  }
}
