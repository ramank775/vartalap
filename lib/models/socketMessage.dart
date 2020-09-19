import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/utils/enum_helper.dart';

class SocketMessage {
  String msgId;
  String to;
  String from;
  MessageType type;
  String chatId;
  String text;
  MessageState state;

  SocketMessage.fromChatMessage(Message msg, Chat chat) {
    this.msgId = msg.id;
    this.from = msg.senderId;
    this.type = msg.type;
    this.chatId = msg.chatId;
    this.text = msg.text;
    this.state = msg.state;
    this.to = chat.users
        .singleWhere((element) => element.username != msg.senderId)
        .username;
  }

  SocketMessage.fromMap(Map<String, dynamic> map) {
    this.msgId = map["msgId"];
    this.to = map["to"];
    this.from = map["from"];
    this.type = stringToEnum(map["type"], MessageType.values);
    this.chatId = map["chatId"];
    this.text = map["text"];
    this.state = stringToEnum(map["state"], MessageState.values);
  }

  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = {
      "msgId": this.msgId,
      "to": this.to,
      "from": this.from,
      "type": enumToString(this.type),
      "chatId": this.chatId,
      "text": this.text,
      "state": enumToString(this.state)
    };
    return map;
  }
}
