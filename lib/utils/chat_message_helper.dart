import 'package:vartalap/models/dateHeader.dart';
import 'package:vartalap/models/messageSpacer.dart';
import 'package:vartalap/models/previewImage.dart';
import 'package:vartalap/utils/dateTimeFormat.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

List<Object> calculateChatMessages(
  List<ChatMessage> messages,
  Contact user, {
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
              (message.timestamp
                      .difference(previousMessage!.timestamp)
                      .inMinutes >
                  1));

      if (isFirstInGroup) {
        shouldShowName = false;
        if (message.type == MessageType.text) {
          showName = true;
        } else {
          shouldShowName = true;
        }
      }

      if (message.type == MessageType.text && shouldShowName) {
        showName = true;
        shouldShowName = false;
      }
    }

    if (nextMessageHasCreatedAt) {
      nextMessageDifferentDay =
          message.timestamp.day != nextMessage!.timestamp.day;

      nextMessageInGroup = nextMessageSameAuthor &&
          nextMessage.timestamp.difference(message.timestamp).inMinutes <= 1;
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
