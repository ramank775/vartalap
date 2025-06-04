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
  String _action = "message";
  late int _id;
  late int _channelId;
  late String _senderId;
  late MessageState _state;
  late MessageType _type;
  late DateTime _ts = DateTime.now();
  late String _category = "message";
  late bool _ephemeral = false;

  int get id => _id;
  String get senderId => _senderId;
  String get action => _action;
  MessageState get state => _state;
  MessageType get type => _type;
  String get category => _category;
  bool get ephemeral => _ephemeral;

  DateTime get timestamp => _ts;
  set timestamp(DateTime ts) {
    _ts = ts;
  }

  Map<String, dynamic> get payload;

  bool isSelected = false;

  final int defaultTime = DateTime.now().millisecondsSinceEpoch;
  Contact? sender;
  ChatMessage(
    this._id,
    this._channelId,
    this._senderId, [
    this._state = MessageState.pending,
    this._action = "message",
    this._type = MessageType.other,
    this._category = "message",
    this._ephemeral = false,
  ]);

  ChatMessage.chatMessage(
    int channelId,
    String senderId,
    MessageType type, {
    int id = 0,
  }) {
    _id = id;
    _channelId = channelId;
    _senderId = senderId;
    _state = MessageState.pending;
    _type = type;
  }
  ChatMessage.fromDb({
    required int id,
    required int channelId,
    required String senderId,
    required MessageState state,
    required MessageType type,
    required DateTime ts,
  }) {
    _id = id;
    _channelId = channelId;
    _senderId = senderId;
    _state = state;
    _type = type;
    _ts = ts;
  }

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
  String _action = "message";
  late String _text;
  String get text => _text;

  TextMessage(int id, int chatId, String senderId,
      [this._text = '',
      MessageState state = MessageState.pending,
      MessageType type = MessageType.text,
      String action = "message"])
      : super(id, chatId, senderId, state, action, type);

  TextMessage.chatMessage(
      int chatId, String senderId, String text, MessageType type)
      : super.chatMessage(chatId, senderId, type) {
    _text = text;
  }

  TextMessage.fromDb({
    required super.id,
    required super.channelId,
    required super.senderId,
    required super.state,
    required super.type,
    required super.ts,
    required Map<String, dynamic> payload,
  }) : super.fromDb() {
    _text = payload["text"];
  }

  @override
  NotificationContent get notificationContent =>
      NotificationContent(text: _text, show: true);

  @override
  String get previewContent => _text;

  @override
  Map<String, dynamic> get payload => {"text": _text};
}

class StateMessge extends ChatMessage {
  List<String> msgIds = [];

  StateMessge(int chatId, String senderId,
      [MessageState state = MessageState.other, int id = 0])
      : super(
          id,
          chatId,
          senderId,
          state,
          "state",
          MessageType.notification,
          "system",
          false,
        );

  @override
  Map<String, dynamic> get payload => {"msgIds": msgIds};
}

class CustomMessage extends ChatMessage {
  Map<String, dynamic> _rawbody = {};

  CustomMessage.chatMessage(super.chatId, super.senderId, super.type);

  CustomMessage(super.id, super.chatId, super.senderId);

  CustomMessage.fromDb({
    required super.id,
    required super.channelId,
    required super.senderId,
    required super.state,
    required super.type,
    required super.ts,
    required Map<String, dynamic> payload,
  }) : super.fromDb() {
    _rawbody = payload;
  }

  @override
  Map<String, dynamic> get payload => _rawbody;
}

class TypingMessage extends ChatMessage {
  bool isTyping = false;

  TypingMessage(int chatId, String senderId, this.isTyping, {int id = 0})
      : super(id, chatId, senderId, MessageState.other, "typing",
            MessageType.notification, "system", true);

  @override
  Map<String, dynamic> get payload => {"isTyping": isTyping};
}

class MessageFilter {
  final MessageType? type;
  final MessageState? state;
  final String? senderId;

  const MessageFilter({
    this.type,
    this.state,
    this.senderId,
  });
}

ChatMessage buildChatMessage({
  required int id,
  required MessageType type,
  required int channelId,
  required String senderId,
  required MessageState state,
  required DateTime ts,
  required Map<String, dynamic> payload,
}) {
  switch (type) {
    case MessageType.text:
      return TextMessage.fromDb(
        id: id,
        channelId: channelId,
        senderId: senderId,
        state: state,
        type: type,
        ts: ts,
        payload: payload,
      );
    default:
      return CustomMessage.fromDb(
        id: id,
        channelId: channelId,
        senderId: senderId,
        state: state,
        type: type,
        ts: ts,
        payload: payload,
      );
  }
}
