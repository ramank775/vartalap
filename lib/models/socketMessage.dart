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
  String module;
  String action;

  SocketMessage.fromChatMessage(Message msg, Chat chat) {
    this.msgId = msg.id;
    this.from = msg.senderId;
    this.type = msg.type;
    this.chatId = msg.chatId;
    this.text = msg.text;
    this.state = msg.state;
    if (chat.type == ChatType.GROUP) {
      this.to = chat.id;
    } else {
      this.to = chat.users
          .singleWhere((element) => element.username != msg.senderId)
          .username;
    }
  }

  SocketMessage.fromMap(Map<String, dynamic> map) {
    this.msgId = map["msgId"];
    this.to = map["to"];
    this.from = map["from"];
    this.type = stringToEnum(map["type"], MessageType.values);
    this.text = map["text"];
    this.chatId = map["chatId"] != null ? map["chatId"] : this.from;
    this.state = map["state"] != null
        ? stringToEnum(map["state"], MessageState.values)
        : MessageState.NEW;
    this.module = map["module"];
    this.action = map["action"];
  }

  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = {
      "msgId": this.msgId,
      "to": this.to,
      "from": this.from,
      "type": enumToString(this.type),
      "chatId": this.chatId,
      "text": this.text,
      "state": enumToString(this.state),
      "module": this.module,
      "action": this.action
    };
    return map;
  }

  Message toMessage() {
    Message msg = Message(this.msgId, this.chatId, this.from, this.text,
        MessageState.NEW, DateTime.now().millisecondsSinceEpoch, this.type);

    return msg;
  }
}
