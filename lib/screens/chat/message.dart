import 'package:vartalap/models/message.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/color_helper.dart';
import 'package:vartalap/utils/dateTimeFormat.dart';
import 'package:vartalap/widgets/rich_message.dart';

class MessageWidget extends StatelessWidget {
  final Message _msg;
  final bool _isYou;

  final bool isSelected;
  final Function? onTab;
  final Function? onLongPress;
  final bool showUserInfo;

  MessageWidget(this._msg, this._isYou,
      {Key? key,
      this.isSelected: false,
      this.onTab,
      this.onLongPress,
      this.showUserInfo = false})
      : super(key: Key(_msg.id));

  @override
  Widget build(BuildContext context) {
    final theme = VartalapTheme.theme.appTheme;
    final senderColor = VartalapTheme.theme.senderColor;
    final receiverColor = VartalapTheme.theme.receiverColor;
    return GestureDetector(
        onTap: () {
          this.onTab!(this._msg);
        },
        onLongPress: () {
          this.onLongPress!(this._msg);
        },
        child: Container(
          decoration: BoxDecoration(
              color: this.isSelected
                  ? theme.selectedRowColor
                  : Colors.transparent),
          constraints: BoxConstraints(
            minWidth: double.infinity,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment:
                _isYou ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: <Widget>[
              ...!_isYou
                  ? [
                      Container(
                        child: this.isSelected
                            ? Checkbox(
                                shape: CircleBorder(),
                                value: this.isSelected,
                                onChanged: (_) => this.onTab,
                              )
                            : null,
                      )
                    ]
                  : [],
              Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    new BoxShadow(
                      color: theme.backgroundColor,
                      offset: new Offset(1.0, 1.0),
                      blurRadius: 0.5,
                    )
                  ],
                  color: _isYou ? senderColor : receiverColor,
                  borderRadius: _isYou
                      ? BorderRadius.only(
                          topLeft: Radius.circular(15.0),
                          bottomLeft: Radius.circular(15.0),
                        )
                      : BorderRadius.only(
                          topRight: Radius.circular(15.0),
                          bottomRight: Radius.circular(15.0),
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
                  textBaseline: TextBaseline.ideographic,
                  children: getMessageComponents(context),
                ),
              ),
              ..._isYou
                  ? [
                      Container(
                        child: this.isSelected
                            ? Checkbox(
                                shape: CircleBorder(),
                                value: this.isSelected,
                                onChanged: (_) => this.onTab,
                              )
                            : null,
                      )
                    ]
                  : []
            ],
          ),
        ));
  }

  List<Widget> getMessageComponents(BuildContext context) {
    var theme = Theme.of(context);
    final TextStyle textStyle = TextStyle(
      fontSize: 18.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      color: theme.textTheme.bodyText1?.color,
    );
    List<Widget> _widgets = [];
    if (this.showUserInfo) {
      _widgets.add(
        Container(
          margin: EdgeInsets.only(bottom: 4),
          child: Text(
            this._msg.sender == null ? '' : this._msg.sender!.name,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: 12,
              color: getColor(this._msg.sender!.name, opacity: 1),
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
              this._msg.text,
              textStyle,
            ),
          ),
          Container(
            margin: EdgeInsets.only(left: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.ideographic,
              children: <Widget>[
                Text(
                  formatMessageTime(this._msg.timestamp),
                  style: TextStyle(
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
        break;
      case MessageState.OTHER:
        return Container();
    }

    return Icon(
      icon,
      size: 15.0,
      color: color,
    );
  }
}
