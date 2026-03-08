import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'channel.dart';
import 'message.dart';

class ChatPreview {
  final ChannelModel channel;
  ChatMessage? lastMessage;
  int unreadCount;

  final String? _displayImage;
  final bool _isMe;

  ChatPreview({
    required this.channel,
    this.lastMessage,
    this.unreadCount = 0,
    String? displayImage,
    bool isMe = false,
  })  : _displayImage = displayImage,
        _isMe = isMe;

  DateTime get lastMessageTimestamp => lastMessage?.timestamp ?? DateTime.now();
  String get previewContent => lastMessage?.previewContent ?? ' ';
  String get displayName => channel.displayName;
  String? get displayImage => _displayImage ?? channel.displayImage;
  bool get isIndividual => channel.type == ChannelType.individual;
  MessageState? get lastMessageState => lastMessage?.state;
  bool get lastMessageIsFromMe => _isMe;
  bool get isPinned => channel.isPinned;
  bool get isArchived => channel.isArchived;
}
