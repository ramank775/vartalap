import 'channel.dart';
import 'message.dart';

class ChatPreview {
  final ChannelModel channel;
  ChatMessage? lastMessage;
  int unreadCount;

  ChatPreview({
    required this.channel,
    this.lastMessage,
    this.unreadCount = 0,
  });

  DateTime get lastMessageTimestamp => lastMessage?.timestamp ?? DateTime.now();
  String get previewContent => lastMessage?.previewContent ?? ' ';
  String get displayName => channel.displayName;
}
