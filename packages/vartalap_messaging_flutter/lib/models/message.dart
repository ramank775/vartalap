import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

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
  static int _number = 0;
  String _action = "message";
  late String _id;
  late String _chatId;
  late String _senderId;
  late MessageState _state;
  late MessageType _type;
  late int _ts = DateTime.now().millisecondsSinceEpoch;
  late String _category = "message";
  late bool _ephemeral = false;

  String get id => _id;
  String get senderId => _senderId;
  String get action => _action;
  MessageState get state => _state;
  MessageType get type => _type;
  String get category => _category;
  bool get ephemeral => _ephemeral;

  int get timestamp => _ts;
  set timestamp(int ts) {
    _ts = ts;
  }

  bool isSelected = false;

  final int defaultTime = DateTime.now().millisecondsSinceEpoch;
  Contact? sender;
  ChatMessage(
    this._id,
    this._chatId,
    this._senderId, [
    this._state = MessageState.pending,
    this._action = "message",
    this._type = MessageType.other,
    this._category = "message",
    this._ephemeral = false,
  ]);

  ChatMessage.chatMessage(String chatId, String senderId, MessageType type) {
    _id = _getMsgId(senderId);
    _chatId = chatId;
    _senderId = senderId;
    _state = MessageState.pending;
    _type = type;
  }
  ChatMessage.fromMap(Map<String, dynamic> map, {bool persistent = false}) {
    _id = map["id"];
    _chatId = map["chatid"];
    _senderId = map["senderid"];
    _ts = map["ts"] ?? _ts;
    _state = intToEnum(map["state"]);
    _type = intToEnum(map["type"], MessageType.values);
  }

  Map<String, dynamic> toMap({bool persistent = false}) {
    Map<String, dynamic> map = {};
    map["id"] = _id;
    map["chatid"] = _chatId;
    map["senderid"] = _senderId;
    map["ts"] = _ts;
    map["state"] = enumToInt(_state, MessageState.values);
    map["type"] = enumToInt(_type, MessageType.values);
    return map;
  }

  Map<String, dynamic> toRemoteBody();

  void fromRemoteBody(Map<String, dynamic> body);

  NotificationContent get notificationContent =>
      NotificationContent(show: false);

  String get previewContent => "";

  String calcContentHash() {
    final map = toRemoteBody();
    final text = json.encode(map);
    return _hash(text);
  }

  bool updateState(MessageState state) {
    if (_state != MessageState.other) {
      int existingState = enumToInt(_state, MessageState.values);
      int newState = enumToInt(state, MessageState.values);
      if (existingState > newState) return false;
    }
    _state = state;
    return true;
  }

  String _hash(String s) {
    final bytes = utf8.encode(s);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  static String _getMsgId(String senderId) {
    var number = double.tryParse(senderId);
    int sender;
    if (number != null) {
      sender = number.toInt();
    } else {
      sender = senderId.hashCode;
    }
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    if ((++_number) >= 4096) {
      // 12 bits for sequence
      _number %= 4096;
    }
    int rawId = ((timestamp & 0xFFFFFFFF) << 44) | // 44 bits for timestamp
        ((sender & 0xFFFFFFFFFFFF) << 12) | // 48 bits for sender
        (_number & 0xFFF); // 12 bits for sequence

    return rawId.toRadixString(16);
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

  TextMessage(String id, String chatId, String senderId,
      [this._text = '',
      MessageState state = MessageState.pending,
      MessageType type = MessageType.text,
      String action = "message"])
      : super(id, chatId, senderId, state, action, type);

  TextMessage.chatMessage(
      String chatId, String senderId, String text, MessageType type)
      : super.chatMessage(chatId, senderId, type) {
    _text = text;
  }

  TextMessage.fromMap(Map<String, dynamic> map, {bool persistent = false})
      : super.fromMap(map, persistent: persistent) {
    _text = map["text"];
  }

  @override
  Map<String, dynamic> toMap({bool persistent = false}) {
    Map<String, dynamic> map = super.toMap(persistent: persistent);
    map["text"] = _text;
    return map;
  }

  @override
  Map<String, dynamic> toRemoteBody() {
    return {
      "text": text,
      "state": enumToString(state),
    };
  }

  @override
  void fromRemoteBody(Map<String, dynamic> body) {
    _text = body["text"];
    _state = body.containsKey("state")
        ? stringToEnum(
            body["state"],
            MessageState.values,
          )
        : MessageState.pending;
  }

  @override
  NotificationContent get notificationContent =>
      NotificationContent(text: _text, show: true);

  @override
  String get previewContent => _text;

  @override
  String calcContentHash() {
    return _hash(text);
  }
}

class StateMessge extends ChatMessage {
  List<String> msgIds = [];

  StateMessge(String chatId, String senderId,
      [MessageState state = MessageState.other])
      : super('', chatId, senderId, state, "state", MessageType.notification,
            "system", false) {
    _id = ChatMessage._getMsgId(senderId);
  }

  @override
  void fromRemoteBody(Map<String, dynamic> body) {
    msgIds = (body["ids"] as List).map((e) => e.toString()).toList();
    _state = stringToEnum(body["state"], MessageState.values);
  }

  @override
  Map<String, dynamic> toRemoteBody() {
    return {"ids": msgIds, "state": enumToString(state)};
  }
}

class CustomMessage extends ChatMessage {
  Map<String, dynamic> _rawbody = {};

  CustomMessage.fromMap(Map<String, dynamic> map, {bool persistent = false})
      : super.fromMap(map, persistent: persistent) {
    if (persistent) {
      final body = map["body"];
      if (body != null) {
        _rawbody = json.decode(body);
      }
    }
  }

  CustomMessage.chatMessage(super.chatId, super.senderId, super.type);

  CustomMessage(super.id, super.chatId, super.senderId);

  @override
  Map<String, dynamic> toMap({bool persistent = false}) {
    final map = super.toMap(persistent: persistent);
    if (persistent) {
      map["body"] = json.encode(_rawbody);
    } else {
      map["body"] = _rawbody;
    }
    return map;
  }

  @override
  void fromRemoteBody(Map<String, dynamic> body) {
    _rawbody = body;
  }

  @override
  Map<String, dynamic> toRemoteBody() {
    return _rawbody;
  }
}

class TypingMessage extends ChatMessage {
  bool isTyping = false;

  TypingMessage(String chatId, String senderId, this.isTyping)
      : super('', chatId, senderId, MessageState.other, "typing",
            MessageType.notification, "system", true) {
    _id = ChatMessage._getMsgId(senderId);
  }

  @override
  void fromRemoteBody(Map<String, dynamic> body) {
    isTyping = body['typing'];
  }

  @override
  Map<String, dynamic> toRemoteBody() {
    return {"typing": isTyping};
  }
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
