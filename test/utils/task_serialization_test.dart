import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap_messaging_flutter/events/message_task.dart';

void main() {
  group('Task Serialization Tests', () {
    test('SendMessage serialization - round trip', () {
      final original = SendMessage(10, [101, 102, 103]);
      
      // Serialize
      final jsonMap = original.toJson();
      final jsonString = json.encode(jsonMap);
      
      // Deserialize
      final decodedMap = json.decode(jsonString) as Map<String, dynamic>;
      final reconstructed = SendMessage.fromJson(decodedMap);
      
      expect(reconstructed.channelId, original.channelId);
      expect(reconstructed.messageIds, original.messageIds);
      expect(reconstructed.messageIds.length, 3);
    });
  });
}
