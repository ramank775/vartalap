import 'package:vartalap/models/message.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/utils/dateTimeFormat.dart';

const messageBubbleColor = Colors.lightBlue;

class MessageWidget extends StatelessWidget {
  final Message _msg;
  final bool _isYou;
  final double fontSize = 14.0;
  final bool isSelected;
  final Function onTab;
  final Function onLongPress;
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        new BoxShadow(
                            color: Colors.grey,
                            offset: new Offset(1.0, 1.0),
                            blurRadius: 1.0)
                      ],
                      color: _isYou ? messageBubbleColor : Colors.white,
                      borderRadius: BorderRadius.all(Radius.circular(5.0)),
                    ),
                    constraints: BoxConstraints(
                      minWidth: 100.0,
                      maxWidth: 280.0,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Container(
                          constraints: BoxConstraints(
                            minWidth: 100.0,
                          ),
                          child: Text(
                            this._msg.text ?? '',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: fontSize,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 100.0,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: <Widget>[
                                  Text(
                                    formatMessageDateTime(this._msg.timestamp),
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 12.0,
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
                        )
                      ],
                    )),
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
}
