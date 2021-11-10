import 'dart:math';

import 'user.dart';
import '../utils/enum_helper.dart';

enum MessageState {
  NEW,
  SENT,
  DELIVERED,
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

class Message {
  static int _number = 0;
  late String _id;
  late String _chatId;
  late String _text;
  late String _senderId;
  late MessageState _state;
  late MessageType _type = MessageType.TEXT;
  late int _ts = DateTime.now().millisecondsSinceEpoch;
  User? sender;
  String get id => _id;
  String get chatId => _chatId;
  String get senderId => _senderId;
  String get text => _text;
  MessageState get state => _state;
  MessageType get type => _type;
  int get timestamp => _ts;
  set timestamp(int ts) {
    this._ts = ts;
  }

  final int defaultTime = DateTime.now().millisecondsSinceEpoch;
  Message(this._id, this._chatId, this._senderId, this._text, this._state,
      [this._type = MessageType.TEXT]);

  Message.chatMessage(
      String chatId, String senderId, String text, MessageType type) {
    this._id = _getMsgId(senderId);
    this._chatId = chatId;
    this._senderId = senderId;
    this._state = MessageState.NEW;
    this._type = type;
    this._text = text;
  }

  Message.fromMap(Map<String, dynamic> map) {
    this._id = map["id"];
    this._chatId = map["chatid"];
    this._senderId = map["senderid"];
    this._text = map["text"];
    this._ts = map["ts"] ?? this._ts;
    this._state = intToEnum(map["state"], MessageState.values);
    this._type = intToEnum(map["type"], MessageType.values);
  }

  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = new Map<String, dynamic>();
    map["id"] = this._id;
    map["chatid"] = this._chatId;
    map["senderid"] = this._senderId;
    map["text"] = this._text;
    map["ts"] = this._ts;
    map["state"] = enumToInt(this._state, MessageState.values);
    map["type"] = enumToInt(this._type, MessageType.values);
    return map;
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

  void updateState(MessageState state) {
    this._state = state;
  }

  int get hashCode => "message_$id".hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}
