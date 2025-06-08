import 'package:flutter/foundation.dart';
import 'package:vartalap_messaging_flutter/utils/utils.dart';

import 'contact.dart';

enum MessageState {
  pending,
  sent,
  delivered,
  read,
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
  bool _showNotification = false;
  String? _text;
  String? get content => _text;
  bool get show => _showNotification;

  NotificationContent({String? text, bool show = false}) {
    _text = text;
    _showNotification = show;
  }
}

abstract class ChatMessage {
  final int _id;
  final int _senderId;
  Contact? _sender;
  MessageState _state;
  final MessageType _type;
  final DateTime _ts;
  final DateTime _updatedAt;

  int get id => _id;
  int get senderId => _senderId;
  Contact? get sender => _sender;

  MessageState get state => _state;
  MessageType get type => _type;

  DateTime get timestamp => _ts;

  DateTime get updatedAt => _updatedAt;

  Map<String, dynamic> get payload;

  bool isSelected = false;

  ChatMessage({
    required int senderId,
    required MessageType type,
    MessageState state = MessageState.pending,
    int id = 0,
    DateTime? ts,
    DateTime? updatedAt,
    Contact? sender,
  })  : _id = id,
        _senderId = senderId,
        _state = state,
        _type = type,
        _updatedAt = updatedAt ?? DateTime.now(),
        _ts = ts ?? DateTime.now();

  NotificationContent get notificationContent =>
      NotificationContent(show: false);

  String get previewContent => "";

  bool updateState(MessageState state) {
    if (_state != MessageState.other) {
      int existingState = enumToInt(_state, MessageState.values);
      int newState = enumToInt(state, MessageState.values);
      if (existingState > newState) return false;
    }
    _state = state;
    return true;
  }

  @override
  int get hashCode => "message_$id".hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}

class ChatMessageNotifier extends ValueNotifier<ChatMessage> {
  late ChatMessage _value;
  ChatMessageNotifier(ChatMessage value) : super(value) {
    _value = value;
  }
  @override
  ChatMessage get value => _value;

  update(ChatMessage newValue) {
    _value = newValue;
    notifyListeners();
  }
}

class TextMessage extends ChatMessage {
  final String _text;
  String get text => _text;

  TextMessage({
    required super.senderId,
    required Map<String, dynamic> payload,
    super.id,
    super.state,
    super.ts,
    super.updatedAt,
    super.sender,
  })  : _text = payload["text"] ?? "",
        super(
          type: MessageType.text,
        );

  @override
  NotificationContent get notificationContent =>
      NotificationContent(text: _text, show: true);

  @override
  String get previewContent => _text;

  @override
  Map<String, dynamic> get payload => {"text": _text};
}

class CustomMessage extends ChatMessage {
  final Map<String, dynamic> _rawbody;

  CustomMessage({
    required super.senderId,
    required super.id,
    required super.state,
    required super.type,
    required super.ts,
    required super.updatedAt,
    super.sender,
    Map<String, dynamic> payload = const {},
  }) : _rawbody = payload;

  @override
  Map<String, dynamic> get payload => _rawbody;
}

class MessageFilter {
  final MessageType? type;
  final MessageState? state;
  final int? senderId;

  const MessageFilter({
    this.type,
    this.state,
    this.senderId,
  });
}
