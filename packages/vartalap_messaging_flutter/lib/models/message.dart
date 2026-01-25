import 'package:flutter/foundation.dart';
import 'package:vartalap_messaging_flutter/models/attachment.dart';
import 'contact.dart';

enum MessageState {
  pending,
  sent,
  delivered,
  read,
  error,
  other,
}

enum MessageType {
  text,
  notification,
  attachment,
  image,
  video,
  audio,
  other,
}

class NotificationContent {
  final String? text;
  final bool show;

  NotificationContent({this.text, this.show = false});

  String? get content => text;
}

class ChatMessage {
  final int id;
  final String? rid;
  final MessageType type;
  MessageState state;
  final Map<String, dynamic> payload;
  final int channelId;
  final int senderId;
  final DateTime localCreatedAt;
  final DateTime? remoteCreatedAt;
  DateTime updatedAt;

  // Extra fields NOT in DB but used in UI
  final Contact? sender;
  final List<Attachment> attachments;

  ChatMessage({
    required this.id,
    this.rid,
    required this.type,
    required this.state,
    required this.payload,
    required this.channelId,
    required this.senderId,
    required this.localCreatedAt,
    this.remoteCreatedAt,
    required this.updatedAt,
    this.sender,
    this.attachments = const [],
  });

  bool updateState(MessageState newState) {
    if (state != MessageState.other && newState != MessageState.error) {
      if (state.index > newState.index) return false;
    }
    state = newState;
    updatedAt = DateTime.now();
    return true;
  }

  factory ChatMessage.text({
    required int channelId,
    required int senderId,
    required String text,
    int id = 0,
    MessageState state = MessageState.pending,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id,
      type: MessageType.text,
      state: state,
      payload: {'text': text},
      channelId: channelId,
      senderId: senderId,
      localCreatedAt: timestamp ?? DateTime.now(),
      updatedAt: timestamp ?? DateTime.now(),
    );
  }

  factory ChatMessage.image({
    required int channelId,
    required int senderId,
    required String path,
    String name = '',
    int id = 0,
    MessageState state = MessageState.pending,
    DateTime? timestamp,
    List<Attachment> attachments = const [],
  }) {
    return ChatMessage(
      id: id,
      type: MessageType.image,
      state: state,
      payload: {'path': path, 'name': name},
      channelId: channelId,
      senderId: senderId,
      localCreatedAt: timestamp ?? DateTime.now(),
      updatedAt: timestamp ?? DateTime.now(),
      attachments: attachments,
    );
  }

  ChatMessage copyWith({
    Contact? sender,
    List<Attachment>? attachments,
    MessageState? state,
    Map<String, dynamic>? payload,
  }) {
    return ChatMessage(
      id: id,
      rid: rid,
      type: type,
      state: state ?? this.state,
      payload: payload ?? this.payload,
      channelId: channelId,
      senderId: senderId,
      localCreatedAt: localCreatedAt,
      remoteCreatedAt: remoteCreatedAt,
      updatedAt: updatedAt,
      sender: sender ?? this.sender,
      attachments: attachments ?? this.attachments,
    );
  }

  DateTime get timestamp => localCreatedAt;

  NotificationContent get notificationContent {
    switch (type) {
      case MessageType.text:
        return NotificationContent(text: payload['text'] ?? '', show: true);
      case MessageType.image:
        return NotificationContent(text: "Sent an image", show: true);
      default:
        return NotificationContent(show: false);
    }
  }

  String get previewContent {
    switch (type) {
      case MessageType.text:
        return text;
      case MessageType.image:
        return 'Image';
      default:
        return '';
    }
  }

  String get text => payload['text'] ?? '';
  String get assetPath => payload['path'] ?? '';
  String get assetName => payload['name'] ?? '';

  // UI helper
  bool isSelected = false;

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(Object other) {
    return other is ChatMessage && other.id == id;
  }
}

class ChatMessageNotifier extends ValueNotifier<ChatMessage> {
  late ChatMessage _value;
  ChatMessageNotifier(ChatMessage value) : super(value) {
    _value = value;
  }
  @override
  ChatMessage get value => _value;

  void update(ChatMessage newValue) {
    _value = newValue;
    notifyListeners();
  }
}

class MessageFilter {
  final MessageType? type;
  final MessageState? state;
  final int? senderId;
  final int? messageId;

  const MessageFilter({
    this.type,
    this.state,
    this.senderId,
    this.messageId,
  });
}