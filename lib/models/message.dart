import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:vartalap/models/user.dart';
import 'package:vartalap/utils/enum_helper.dart';

enum MessageState {
  NEW,
  SENT,
  DELIVERED,
  READ,
  OTHER,
}

enum MessageType {
  TEXT,
  NOTIFICATION,
  ATTACHMENT,
  IMAGE,
  VIDEO,
  AUDIO,
  OTHER,
}

class NotificationContent {
  bool _showNotification = false;
  String? _text;
  String? get content => this._text;
  bool get show => this._showNotification;

  NotificationContent({String? text, bool show = false}) {
    this._text = text;
    this._showNotification = show;
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
  String get chatId => _chatId;
  String get senderId => _senderId;
  String get action => _action;
  MessageState get state => _state;
  MessageType get type => _type;
  String get category => _category;
  bool get ephemeral => _ephemeral;

  int get timestamp => _ts;
  set timestamp(int ts) {
    this._ts = ts;
  }

  bool isSelected = false;

  final int defaultTime = DateTime.now().millisecondsSinceEpoch;
  User? sender;
  ChatMessage(
    this._id,
    this._chatId,
    this._senderId, [
    this._state = MessageState.NEW,
    this._action = "message",
    this._type = MessageType.OTHER,
    this._category = "message",
    this._ephemeral = false,
  ]);

  ChatMessage.chatMessage(String chatId, String senderId, MessageType type) {
    this._id = _getMsgId(senderId);
    this._chatId = chatId;
    this._senderId = senderId;
    this._state = MessageState.NEW;
    this._type = type;
  }
  ChatMessage.fromMap(Map<String, dynamic> map, {bool persistent = false}) {
    this._id = map["id"];
    this._chatId = map["chatid"];
    this._senderId = map["senderid"];
    this._ts = map["ts"] ?? this._ts;
    this._state = intToEnum(map["state"], MessageState.values);
    this._type = intToEnum(map["type"], MessageType.values);
  }

  Map<String, dynamic> toMap({bool persistent = false}) {
    Map<String, dynamic> map = new Map<String, dynamic>();
    map["id"] = this._id;
    map["chatid"] = this._chatId;
    map["senderid"] = this._senderId;
    map["ts"] = this._ts;
    map["state"] = enumToInt(this._state, MessageState.values);
    map["type"] = enumToInt(this._type, MessageType.values);
    return map;
  }

  Map<String, dynamic> toRemoteBody();

  void fromRemoteBody(Map<String, dynamic> body);

  NotificationContent get notificationContent =>
      NotificationContent(show: false);

  String get previewContent => "";

  String calcContentHash() {
    final map = this.toRemoteBody();
    final text = json.encode(map);
    return this._hash(text);
  }

  bool updateState(MessageState state) {
    if (this._state != MessageState.OTHER) {
      int existingState = enumToInt(this._state, MessageState.values);
      int newState = enumToInt(state, MessageState.values);
      if (existingState > newState) return false;
    }
    this._state = state;
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
    int unixEpoch10 =
        DateTime.now().millisecondsSinceEpoch % (pow(10, 13)) as int;
    if ((++_number) >= 10000) {
      _number %= 10000;
    }
    int rawId = (sender * pow(10, 16) as int) +
        (unixEpoch10 * pow(10, 3) as int) +
        _number;

    return rawId.toRadixString(16);
  }

  int get hashCode => "message_$id".hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}

class ChatMessageNotifier extends ValueNotifier<ChatMessage> {
  late ChatMessage _value;
  ChatMessageNotifier(ChatMessage value) : super(value) {
    this._value = value;
  }
  @override
  ChatMessage get value => this._value;

  update(ChatMessage newValue) {
    this._value = newValue;
    this.notifyListeners();
  }
}

class TextMessage extends ChatMessage {
  String _action = "message";
  late String _text;
  String get text => _text;

  final int defaultTime = DateTime.now().millisecondsSinceEpoch;

  TextMessage(String id, String chatId, String senderId,
      [this._text = '',
      MessageState state = MessageState.NEW,
      MessageType type = MessageType.TEXT,
      String action = "message"])
      : super(id, chatId, senderId, state, action, type);

  TextMessage.chatMessage(
      String chatId, String senderId, String text, MessageType type)
      : super.chatMessage(chatId, senderId, type) {
    this._text = text;
  }

  TextMessage.fromMap(Map<String, dynamic> map, {bool persistent = false})
      : super.fromMap(map, persistent: persistent) {
    this._text = map["text"];
  }

  Map<String, dynamic> toMap({bool persistent = false}) {
    Map<String, dynamic> map = super.toMap(persistent: persistent);
    map["text"] = this._text;
    return map;
  }

  @override
  Map<String, dynamic> toRemoteBody() {
    return {
      "text": this.text,
      "state": enumToString(this.state),
    };
  }

  @override
  void fromRemoteBody(Map<String, dynamic> body) {
    this._text = body["text"];
    this._state = body.containsKey("state")
        ? stringToEnum(
            body["state"],
            MessageState.values,
          )
        : MessageState.NEW;
  }

  @override
  NotificationContent get notificationContent =>
      NotificationContent(text: this._text, show: true);

  @override
  String get previewContent => this._text;

  @override
  String calcContentHash() {
    return this._hash(this.text);
  }
}

class StateMessge extends ChatMessage {
  List<String> msgIds = [];

  StateMessge(String chatId, String senderId,
      [MessageState state = MessageState.OTHER])
      : super('', chatId, senderId, state, "state", MessageType.NOTIFICATION,
            "system", false) {
    this._id = ChatMessage._getMsgId(senderId);
  }

  @override
  void fromRemoteBody(Map<String, dynamic> body) {
    this.msgIds = (body["ids"] as List).map((e) => e.toString()).toList();
    this._state = stringToEnum(body["state"], MessageState.values);
  }

  @override
  Map<String, dynamic> toRemoteBody() {
    return {"ids": this.msgIds, "state": enumToString(this.state)};
  }
}

class CustomMessage extends ChatMessage {
  Map<String, dynamic> _rawbody = {};

  CustomMessage.fromMap(Map<String, dynamic> map, {bool persistent = false})
      : super.fromMap(map, persistent: persistent) {
    if (persistent) {
      final body = map["body"];
      if (body != null) {
        this._rawbody = json.decode(body);
      }
    }
  }

  CustomMessage.chatMessage(String chatId, String senderId, MessageType type)
      : super.chatMessage(chatId, senderId, type);

  CustomMessage(String id, String chatId, String senderId)
      : super(id, chatId, senderId);

  @override
  Map<String, dynamic> toMap({bool persistent = false}) {
    final map = super.toMap(persistent: persistent);
    if (persistent) {
      map["body"] = json.encode(this._rawbody);
    } else {
      map["body"] = this._rawbody;
    }
    return map;
  }

  @override
  void fromRemoteBody(Map<String, dynamic> body) {
    this._rawbody = body;
  }

  @override
  Map<String, dynamic> toRemoteBody() {
    return this._rawbody;
  }
}

class TypingMessage extends ChatMessage {
  bool isTyping = false;

  TypingMessage(String chatId, String senderId, this.isTyping)
      : super('', chatId, senderId, MessageState.OTHER, "typing",
            MessageType.NOTIFICATION, "system", true) {
    this._id = ChatMessage._getMsgId(senderId);
  }

  @override
  void fromRemoteBody(Map<String, dynamic> body) {
    this.isTyping = body['typing'];
  }

  @override
  Map<String, dynamic> toRemoteBody() {
    return {"typing": this.isTyping};
  }
}
