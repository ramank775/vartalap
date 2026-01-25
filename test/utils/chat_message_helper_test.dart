import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/utils/chat_message_helper.dart';
import 'package:vartalap/models/date_header.dart';
import 'package:vartalap/models/message_spacer.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

void main() {
  final currentUser = const Contact(
    id: 1,
    username: 'me',
    uid: 'uid_me',
    status: ContactStatus.active,
  );

  final otherUser = const Contact(
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
        TextMessage(
          id: 1,
          senderId: otherUser.id,
          payload: {'text': 'Hello'},
          ts: now,
          sender: otherUser,
        ),
      ];

      final result = calculateChatMessages(messages, currentUser, showUserNames: false);
      final displayList = result[0] as List<Object>;

      // Expected for 1 message: [DateHeader, MessageSpacer, Map(message)]
      // (Order might vary depending on exact loop logic, let's check existence)
      expect(displayList.any((e) => e is DateHeader), true);
      expect(displayList.any((e) => e is Map), true);
      
      final msgMap = displayList.firstWhere((e) => e is Map) as Map;
      expect((msgMap['message'] as ChatMessage).id, 1);
    });

    test('calculateChatMessages - groups consecutive messages from same user', () {
      final now = DateTime.now();
      final messages = [
        TextMessage(
          id: 1,
          senderId: otherUser.id,
          payload: {'text': 'Hi'},
          ts: now.subtract(const Duration(seconds: 30)),
          sender: otherUser,
        ),
        TextMessage(
          id: 2,
          senderId: otherUser.id,
          payload: {'text': 'How are you?'},
          ts: now,
          sender: otherUser,
        ),
      ];

      final result = calculateChatMessages(messages, currentUser, showUserNames: false);
      final displayList = result[0] as List<Object>;

      // Find the map for message 2
      final msg2Map = displayList.firstWhere(
        (e) => e is Map && (e['message'] as ChatMessage).id == 2
      ) as Map;
      
      // Since messages are ordered Old -> New (index 0 is Old), and loop runs New -> Old.
      // For Msg2 (New), nextMessage is Msg1 (Old).
      // Since they are from same author and close in time, nextMessageInGroup is true.
      expect(msg2Map['nextMessageInGroup'], true);
      expect(msg2Map['showNip'], false); // Grouped messages don't show nip
    });

    test('calculateChatMessages - adds spacer between different users', () {
      final now = DateTime.now();
      final messages = [
        TextMessage(
          id: 1,
          senderId: otherUser.id,
          payload: {'text': 'Alice message'},
          ts: now.subtract(const Duration(minutes: 5)),
          sender: otherUser,
        ),
        TextMessage(
          id: 2,
          senderId: currentUser.id,
          payload: {'text': 'My response'},
          ts: now,
          sender: currentUser,
        ),
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
        TextMessage(
          id: 1,
          senderId: otherUser.id,
          payload: {'text': 'Msg from Alice'},
          ts: now,
          sender: otherUser,
        ),
      ];

      final result = calculateChatMessages(messages, currentUser, showUserNames: true);
      final displayList = result[0] as List<Object>;

      final msg1Map = displayList.firstWhere((m) => m is Map && (m['message'] as ChatMessage).id == 1) as Map;

      // Alice is not currentUser, showUserNames is true, and it's the first in group (only message)
      expect(msg1Map['showName'], true);
    });
  });
}