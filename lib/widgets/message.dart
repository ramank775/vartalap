import 'package:bubble/bubble.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/color_helper.dart';
import 'package:vartalap/utils/date_time_format.dart';
import 'package:vartalap/widgets/rich_message.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

class MessageWidget extends StatelessWidget {
  final ChatMessage _msg;
  final bool _isYou;

  final bool isSelected;
  final bool isLoading;
  final Function? onTab;
  final Function? onLongPress;
  final bool showUserInfo;
  final bool showNip;
  MessageWidget(
    this._msg,
    this._isYou, {
    Key? key,
    this.isSelected = false,
    this.isLoading = false,
    this.onTab,
    this.onLongPress,
    this.showUserInfo = false,
    this.showNip = true,
  }) : super(key: Key(_msg.id.toString()));

  @override
  Widget build(BuildContext context) {
    final senderColor = VartalapTheme.theme.senderColor;
    final receiverColor = VartalapTheme.theme.receiverColor;
    final selectedRowColor = VartalapTheme.theme.selectedRowColor;
    return GestureDetector(
      onTap: () {
        onTab!(_msg);
      },
      onLongPress: () {
        onLongPress!(_msg);
      },
      child: Container(
        padding: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: isSelected ? selectedRowColor : Colors.transparent,
        ),
        constraints: BoxConstraints(
          minWidth: double.infinity,
        ),
        child: Stack(
          children: [
            Bubble(
              alignment: _isYou ? Alignment.topRight : Alignment.topLeft,
              color: isSelected
                  ? selectedRowColor
                  : _isYou
                      ? senderColor
                      : receiverColor,
              showNip: showNip,
              nip: _isYou ? BubbleNip.rightBottom : BubbleNip.leftBottom,
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
            if (isLoading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> getMessageComponents(BuildContext context) {
    List<Widget> widgets = [];
    if (showUserInfo) {
      final brightness = Theme.of(context).brightness;
      widgets.add(
        Container(
          margin: EdgeInsets.only(bottom: 4),
          child: Text(
            _msg.sender == null ? '' : _msg.sender!.displayName,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: 12,
              color: getColor(
                _msg.sender!.displayName,
                opacity: 1,
                brightness: brightness,
              ),
            ),
          ),
        ),
      );
    }
    widgets.add(
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
                if (_msg.updatedAt != _msg.timestamp)
                  Container(
                    margin: EdgeInsets.only(right: 4),
                    child: Text(
                      'edited',
                      style: TextStyle(
                        fontSize: 10.0,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                Text(
                  formatMessageTime(_msg.timestamp),
                  style: TextStyle(
                    fontSize: 11.0,
                  ),
                ),
                SizedBox(
                  width: 8.0,
                ),
                _isYou ? _getIcon() : Container()
              ],
            ),
          ),
        ],
      ),
    );
    return widgets;
  }

  Widget getMessageWidget(BuildContext context) {
    final theme = Theme.of(context);
    final TextStyle textStyle = TextStyle(
      fontSize: theme.primaryTextTheme.titleMedium!.fontSize,
      fontWeight: theme.primaryTextTheme.titleMedium!.fontWeight,
      letterSpacing: 0.25,
      color: theme.textTheme.bodyLarge?.color,
    );
    switch (_msg.type) {
      case MessageType.text:
        {
          final msg = _msg as TextMessage;
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
    switch (_msg.state) {
      case MessageState.pending:
        icon = Icons.access_time;
        break;
      case MessageState.sent:
        icon = Icons.check;
        break;
      case MessageState.delivered:
        icon = Icons.done_all;
        break;
      case MessageState.other:
        return Container();
      case MessageState.read:
        icon = Icons.done_all_sharp;
        color = VartalapTheme.theme.readMessage;
        break;
      case MessageState.error:
        icon = Icons.error_outline;
        color = Colors.red;
        break;
    }

    return Icon(
      icon,
      size: 15.0,
      color: color,
    );
  }
}
