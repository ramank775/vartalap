import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

extension MessageEntityX on MessageEntity {
  /// Converts a [MessageEntity] to a [ChatMessage].
  ChatMessage toModel({
    Contact? sender,
    List<Attachment>? attachments,
  }) {
    return _buildChatMessage(sender: sender);
  }

  ChatMessage _buildChatMessage({
    Contact? sender,
    List<Attachment>? attachments,
  }) {
    switch (type) {
      case MessageType.text:
        return TextMessage(
          id: id,
          rid: rid,
          senderId: senderId,
          state: state,
          ts: localCreatedAt,
          updatedAt: updatedAt,
          payload: payload,
          sender: sender,
        );
      case MessageType.image:
        return ImageMessage(
          id: id,
          rid: rid,
          senderId: senderId,
          state: state,
          ts: localCreatedAt,
          updatedAt: updatedAt,
          payload: payload,
          sender: sender,
          attachments: attachments ?? [],
        );
      default:
        return CustomMessage(
          id: id,
          rid: rid,
          senderId: senderId,
          state: state,
          ts: localCreatedAt,
          updatedAt: updatedAt,
          payload: payload,
          sender: sender,
          type: type,
          attachments: attachments ?? [],
        );
    }
  }
}

extension ChatMessageX on ChatMessage {
  /// Converts a [ChatMessage] to a [MessageEntity].
  MessageEntity toEntity({required int channelId}) {
    return MessageEntity(
      id: id,
      channelId: channelId,
      senderId: senderId,
      state: state,
      type: type,
      localCreatedAt: timestamp,
      updatedAt: updatedAt,
      payload: payload,
    );
  }

  List<AssestEntity> toAssets() {
    return attachments
        .map((attachment) => AssestEntity(
              id: attachment.id,
              type: 'message',
              path: attachment.path,
              mimeType: attachment.type,
              createdAt: attachment.createdAt,
              updatedAt: attachment.updatedAt,
            ))
        .toList();
  }
}
