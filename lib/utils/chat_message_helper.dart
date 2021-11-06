import 'package:vartalap/models/dateHeader.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/messageSpacer.dart';
import 'package:vartalap/models/previewImage.dart';
import 'package:vartalap/models/remoteMessage.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/utils/dateTimeFormat.dart';

List<Object> calculateChatMessages(
  List<ChatMessage> messages,
  User user, {
  String Function(DateTime)? customDateHeaderText,
  required bool showUserNames,
}) {
  final chatMessages = <Object>[];
  final gallery = <PreviewImage>[];

  var shouldShowName = false;

  for (var i = messages.length - 1; i >= 0; i--) {
    final isFirst = i == messages.length - 1;
    final isLast = i == 0;
    final message = messages[i];
    final nextMessage = isLast ? null : messages[i - 1];
    final nextMessageHasCreatedAt = nextMessage?.timestamp != null;
    final nextMessageSameAuthor = message.senderId == nextMessage?.senderId;
    final notMyMessage = message.senderId != user.username;

    var nextMessageDateThreshold = false;
    var nextMessageDifferentDay = false;
    var nextMessageInGroup = false;
    var showName = false;

    if (showUserNames) {
      final previousMessage = isFirst ? null : messages[i + 1];

      final isFirstInGroup = notMyMessage &&
          ((message.senderId != previousMessage?.senderId) ||
              (message.timestamp - previousMessage!.timestamp > 60000));

      if (isFirstInGroup) {
        shouldShowName = false;
        if (message.type == MessageType.TEXT) {
          showName = true;
        } else {
          shouldShowName = true;
        }
      }

      if (message.type == MessageType.TEXT && shouldShowName) {
        showName = true;
        shouldShowName = false;
      }
    }

    if (nextMessageHasCreatedAt) {
      // nextMessageDateThreshold =
      //     nextMessage!.timestamp - message.timestamp >= 900000;

      nextMessageDifferentDay =
          DateTime.fromMillisecondsSinceEpoch(message.timestamp).day !=
              DateTime.fromMillisecondsSinceEpoch(nextMessage!.timestamp).day;

      nextMessageInGroup = nextMessageSameAuthor &&
          nextMessage.timestamp - message.timestamp <= 60000;
    }

    if (isFirst) {
      chatMessages.insert(
        0,
        DateHeader(
          date: formatMessageDate(message.timestamp),
        ),
      );
    }

    chatMessages.insert(0, {
      'message': message,
      'nextMessageInGroup': nextMessageInGroup,
      'showName':
          notMyMessage && showUserNames && showName && message.sender != null,
      'showStatus': true,
    });

    if (!nextMessageInGroup) {
      chatMessages.insert(
        0,
        MessageSpacer(
          height: 12,
          id: message.id,
        ),
      );
    }

    if (nextMessageDifferentDay || nextMessageDateThreshold) {
      chatMessages.insert(
        0,
        DateHeader(
          date: formatMessageDate(nextMessage!.timestamp),
        ),
      );
    }

    // if (message.type == MessageType.IMAGE) {
    //   gallery.add(PreviewImage(id: message.id, uri: message.uri));
    // }
  }

  return [chatMessages, gallery];
}

ChatMessage toChatMessage(RemoteMessage msg) {
  ChatMessage chatMsg;
  if (msg.head.contentType == MessageType.NOTIFICATION &&
      msg.head.action == "state") {
    chatMsg = StateMessge(
      msg.head.chatid!,
      msg.head.from,
      MessageState.OTHER,
    );
  } else {
    chatMsg = TextMessage(
      msg.id,
      msg.head.chatid!,
      msg.head.from,
    );
  }

  chatMsg.fromRemoteBody(msg.body);
  return chatMsg;
}
