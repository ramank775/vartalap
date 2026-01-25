import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/utils/chat_message_helper.dart';
import 'package:vartalap/models/date_header.dart';
import 'package:vartalap/models/message_spacer.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

void main() {
  const currentUser = Contact(
    id: 1,
    username: 'me',
    uid: 'uid_me',
    status: ContactStatus.active,
  );

  const otherUser = Contact(
    id: 2,
    name: 'Alice',
    username: 'alice',
    uid: 'uid_alice',
    status: ContactStatus.active,
  );

  group('ChatMessageHelper Tests', () {
    test('calculateChatMessages - adds date header for first message', () {
      final now = DateTime.now();
      final messages = [
        ChatMessage.text(
          id: 1,
          channelId: 1,
          senderId: otherUser.id,
          text: 'Hello',
          timestamp: now,
        ).copyWith(sender: otherUser),
      ];

      final result = calculateChatMessages(messages, currentUser, showUserNames: false);
      final displayList = result[0] as List<Object>;

      // Expected for 1 message: [DateHeader, MessageSpacer, Map(message)]
      expect(displayList.any((e) => e is DateHeader), true);
      expect(displayList.any((e) => e is Map), true);
      
      final msgMap = displayList.firstWhere((e) => e is Map) as Map;
      expect((msgMap['message'] as ChatMessage).id, 1);
    });

    test('calculateChatMessages - groups consecutive messages from same user', () {
      final now = DateTime.now();
      final messages = [
        ChatMessage.text(
          id: 1,
          channelId: 1,
          senderId: otherUser.id,
          text: 'Hi',
          timestamp: now.subtract(const Duration(seconds: 30)),
        ).copyWith(sender: otherUser),
        ChatMessage.text(
          id: 2,
          channelId: 1,
          senderId: otherUser.id,
          text: 'How are you?',
          timestamp: now,
        ).copyWith(sender: otherUser),
      ];

      final result = calculateChatMessages(messages, currentUser, showUserNames: false);
      final displayList = result[0] as List<Object>;

      // Find the map for message 2
      final msg2Map = displayList.firstWhere(
        (e) => e is Map && (e['message'] as ChatMessage).id == 2
      ) as Map;
      
      expect(msg2Map['nextMessageInGroup'], true);
      expect(msg2Map['showNip'], false); // Grouped messages don't show nip
    });

    test('calculateChatMessages - adds spacer between different users', () {
      final now = DateTime.now();
      final messages = [
        ChatMessage.text(
          id: 1,
          channelId: 1,
          senderId: otherUser.id,
          text: 'Alice message',
          timestamp: now.subtract(const Duration(minutes: 5)),
        ).copyWith(sender: otherUser),
        ChatMessage.text(
          id: 2,
          channelId: 1,
          senderId: currentUser.id,
          text: 'My response',
          timestamp: now,
        ).copyWith(sender: currentUser),
      ];

      final result = calculateChatMessages(messages, currentUser, showUserNames: false);
      final displayList = result[0] as List<Object>;

      // Verify that there is a MessageSpacer
      final hasSpacer = displayList.any((obj) => obj is MessageSpacer);
      expect(hasSpacer, true);
    });

    test('calculateChatMessages - shows name for messages from others when enabled', () {
      final now = DateTime.now();
      final messages = [
        ChatMessage.text(
          id: 1,
          channelId: 1,
          senderId: otherUser.id,
          text: 'Msg from Alice',
          timestamp: now,
        ).copyWith(sender: otherUser),
      ];

      final result = calculateChatMessages(messages, currentUser, showUserNames: true);
      final displayList = result[0] as List<Object>;

      final msg1Map = displayList.firstWhere((m) => m is Map && (m['message'] as ChatMessage).id == 1) as Map;

      // Alice is not currentUser, showUserNames is true, and it's the first in group (only message)
      expect(msg1Map['showName'], true);
    });
  });
}
