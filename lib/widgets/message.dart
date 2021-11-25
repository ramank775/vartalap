import 'package:bubble/bubble.dart';
import 'package:vartalap/models/message.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/color_helper.dart';
import 'package:vartalap/utils/dateTimeFormat.dart';
import 'package:vartalap/widgets/rich_message.dart';

class MessageWidget extends StatelessWidget {
  final ChatMessage _msg;
  final bool _isYou;

  final bool isSelected;
  final Function? onTab;
  final Function? onLongPress;
  final bool showUserInfo;
  final bool showNip;
  MessageWidget(
    this._msg,
    this._isYou, {
    Key? key,
    this.isSelected: false,
    this.onTab,
    this.onLongPress,
    this.showUserInfo = false,
    this.showNip = true,
  }) : super(key: Key(_msg.id));

  @override
  Widget build(BuildContext context) {
    final theme = VartalapTheme.theme.appTheme;
    final senderColor = VartalapTheme.theme.senderColor;
    final receiverColor = VartalapTheme.theme.receiverColor;
    final selectedRowColor = theme.selectedRowColor;
    return GestureDetector(
      onTap: () {
        this.onTab!(this._msg);
      },
      onLongPress: () {
        this.onLongPress!(this._msg);
      },
      child: Container(
        padding: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: this.isSelected ? selectedRowColor : Colors.transparent,
        ),
        constraints: BoxConstraints(
          minWidth: double.infinity,
        ),
        child: Bubble(
          alignment: this._isYou ? Alignment.topRight : Alignment.topLeft,
          color: this.isSelected
              ? selectedRowColor
              : this._isYou
                  ? senderColor
                  : receiverColor,
          showNip: this.showNip,
          nip: this._isYou ? BubbleNip.rightBottom : BubbleNip.leftBottom,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              textBaseline: TextBaseline.ideographic,
              children: getMessageComponents(context),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> getMessageComponents(BuildContext context) {
    List<Widget> _widgets = [];
    if (this.showUserInfo) {
      final brightness = Theme.of(context).brightness;
      _widgets.add(
        Container(
          margin: EdgeInsets.only(bottom: 4),
          child: Text(
            this._msg.sender == null ? '' : this._msg.sender!.name,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: 12,
              color: getColor(
                this._msg.sender!.name,
                opacity: 1,
                brightness: brightness,
              ),
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
            child: getMessageWidget(context),
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

  Widget getMessageWidget(BuildContext context) {
    final theme = Theme.of(context);
    final TextStyle textStyle = TextStyle(
      fontSize: theme.primaryTextTheme.subtitle1!.fontSize,
      fontWeight: theme.primaryTextTheme.subtitle1!.fontWeight,
      letterSpacing: 0.25,
      color: theme.textTheme.bodyText1?.color,
    );
    switch (this._msg.type) {
      case MessageType.TEXT:
        {
          final msg = this._msg as TextMessage;
          return RichMessage(
            msg.text,
            textStyle,
          );
        }
      default:
        return SizedBox();
    }
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
        break;
      case MessageState.OTHER:
        return Container();
      case MessageState.READ:
        icon = Icons.done_all_sharp;
        color = VartalapTheme.theme.readMessage;
        break;
    }

    return Icon(
      icon,
      size: 15.0,
      color: color,
    );
  }
}
