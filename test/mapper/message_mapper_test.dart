import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/db/chat_db.dart';
import 'package:vartalap_messaging_flutter/mapper/message.dart';
import 'package:vartalap_messaging_flutter/models/models.dart';

void main() {
  group('Message Mapper Tests', () {
    test('MessageEntity toModel - TextMessage mapping', () {
      final entity = MessageEntity(
        id: 1,
        rid: 'remote_id_123',
        type: MessageType.text,
        state: MessageState.sent,
        payload: {'text': 'Hello world'},
        channelId: 10,
        senderId: 20,
        localCreatedAt: DateTime(2024, 1, 1, 10, 0),
        updatedAt: DateTime(2024, 1, 1, 10, 5),
      );

      final model = entity.toModel();

      expect(model, isA<TextMessage>());
      expect(model.id, 1);
      expect(model.rid, 'remote_id_123');
      expect((model as TextMessage).text, 'Hello world');
      expect(model.state, MessageState.sent);
      expect(model.timestamp, DateTime(2024, 1, 1, 10, 0));
    });

    test('MessageEntity toModel - ImageMessage mapping', () {
      final entity = MessageEntity(
        id: 2,
        rid: 'img_remote_id',
        type: MessageType.image,
        state: MessageState.delivered,
        payload: {'name': 'test.jpg', 'path': '/local/path/test.jpg'},
        channelId: 10,
        senderId: 20,
        localCreatedAt: DateTime(2024, 1, 1, 11, 0),
        updatedAt: DateTime(2024, 1, 1, 11, 0),
      );

      final model = entity.toModel();

      expect(model, isA<ImageMessage>());
      expect(model.id, 2);
      expect(model.rid, 'img_remote_id');
      expect(model.type, MessageType.image);
    });

    test('ChatMessage toEntity mapping', () {
      final now = DateTime.now();
      final model = TextMessage(
        id: 1,
        rid: 'remote_123',
        senderId: 20,
        payload: {'text': 'Mapped text'},
        ts: now,
        state: MessageState.pending,
      );

      final entity = model.toEntity(channelId: 10);

      expect(entity.id, 1);
      expect(entity.rid, 'remote_123');
      expect(entity.channelId, 10);
      expect(entity.senderId, 20);
      expect(entity.payload['text'], 'Mapped text');
      expect(entity.localCreatedAt, now);
    });
  });
}
