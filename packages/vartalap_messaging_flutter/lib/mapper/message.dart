import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

extension MessageEntityX on MessageEntity {
  /// Converts a [MessageEntity] to a [ChatMessage].
  ChatMessage toModel({
    Contact? sender,
  }) {
    return _buildChatMessage(sender: sender);
  }

  ChatMessage _buildChatMessage({Contact? sender}) {
    switch (type) {
      case MessageType.text:
        return TextMessage(
          id: id,
          senderId: senderId,
          state: state,
          ts: localCreatedAt,
          updatedAt: updatedAt,
          payload: payload,
          sender: sender,
        );
      default:
        return CustomMessage(
          id: id,
          senderId: senderId,
          state: state,
          ts: localCreatedAt,
          updatedAt: updatedAt,
          payload: payload,
          sender: sender,
          type: type,
        );
    }
  }
}
