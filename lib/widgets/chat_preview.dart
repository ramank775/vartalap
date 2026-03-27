import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/date_time_format.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:provider/provider.dart';
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
                    text: _chat.displayName,
                    image: _chat.displayImage,
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
                  _chat.displayName,
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
                  child: Row(
                    children: [
                      if (_chat.lastMessageIsFromMe) ...[
                        _buildMessageStatus(),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final currentUserIdStr = CurrentUser.of(context).user?.id.toString();
                            return StreamBuilder<Map<String, dynamic>>(
                              stream: context.read<VartalapChatClientFlutter>()
                                  .watchTypingEvents()
                                  .where((event) {
                                if (_chat.channel.type == ChannelType.individual) {
                                  return event['from'] != currentUserIdStr;
                                } else {
                                  return event['to'] == _chat.channel.cid &&
                                      event['from'] != currentUserIdStr;
                                }
                              }),
                              builder: (context, snapshot) {
                                final isTyping = snapshot.data?['typing'] == true;
                                if (isTyping) {
                                  return Text(
                                    "Typing...",
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15.0,
                                      color: Theme.of(context).primaryColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  );
                                }
                                return Text(
                                  _chat.previewContent,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15.0),
                                );
                              },
                            );
                          }
                        ),
                      ),
                    ],
                  ),
                ),
                if (_chat.isPinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0, left: 4.0),
                    child: Icon(Icons.push_pin, size: 16, color: Colors.grey),
                  ),
                getWidget(context),
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

  Widget _buildMessageStatus() {
    IconData icon;
    Color color = Colors.grey;

    switch (_chat.lastMessageState) {
      case MessageState.pending:
        icon = Icons.access_time;
        break;
      case MessageState.sent:
        icon = Icons.check;
        break;
      case MessageState.delivered:
        icon = Icons.done_all;
        break;
      case MessageState.read:
        icon = Icons.done_all;
        color = Colors.blue;
        break;
      case MessageState.error:
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Icon(
      icon,
      size: 16,
      color: color,
    );
  }
}
