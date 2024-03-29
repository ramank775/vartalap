import 'package:vartalap/models/dateHeader.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/messageSpacer.dart';
import 'package:vartalap/models/previewImage.dart';
import 'package:vartalap/models/remoteMessage.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/utils/dateTimeFormat.dart';
import 'package:vartalap/utils/enum_helper.dart';

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
      'showName': notMyMessage && showUserNames && showName,
      'showStatus': true,
      'showNip': !nextMessageInGroup,
    });

    if (!nextMessageInGroup) {
      chatMessages.insert(
        0,
        MessageSpacer(
          height: 5,
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
  } else if (msg.head.contentType == MessageType.NOTIFICATION &&
      msg.head.action == "typing") {
    chatMsg = TypingMessage(msg.head.chatid!, msg.head.from, false);
  } else if (msg.head.contentType == MessageType.TEXT) {
    chatMsg = TextMessage(
      msg.id,
      msg.head.chatid!,
      msg.head.from,
    );
  } else {
    chatMsg = CustomMessage(
      msg.id,
      msg.head.chatid!,
      msg.head.from,
    );
  }

  chatMsg.fromRemoteBody(msg.body);
  return chatMsg;
}

ChatMessage buildChatMessage(Map<String, dynamic> map,
    {bool persistent = false}) {
  final type = intToEnum(map["type"], MessageType.values);
  switch (type) {
    case MessageType.TEXT:
      return TextMessage.fromMap(map, persistent: persistent);
    default:
      return CustomMessage.fromMap(map, persistent: persistent);
  }
}
