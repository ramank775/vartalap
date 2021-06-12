import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/utils/enum_helper.dart';

class SocketMessage {
  String? msgId;
  late String to;
  late String from;
  late MessageType type;
  String? chatId;
  late String text;
  late MessageState state;
  String? module;
  String? action;
  ChatType chatType = ChatType.INDIVIDUAL;

  SocketMessage.fromChatMessage(Message msg, Chat chat) {
    this.msgId = msg.id;
    this.from = msg.senderId;
    this.type = msg.type;
    this.chatId = msg.chatId;
    this.text = msg.text;
    this.state = msg.state;
    this.chatType = chat.type;
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
    this.chatId = map["chatId"];
    this.state = map["state"] != null
        ? stringToEnum(map["state"], MessageState.values)
        : MessageState.NEW;
    this.module = map["module"];
    this.action = map["action"];
    this.chatType = map["chatType"] != null
        ? stringToEnum(map["chatType"], ChatType.values)
        : ChatType.INDIVIDUAL;
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
      "action": this.action,
      "chatType": enumToString(this.chatType)
    };
    return map;
  }

  Message? toMessage() {
    if (this.msgId == null || this.chatId == null) {
      return null;
    }
    Message msg = Message(
      this.msgId!,
      this.chatId!,
      this.from,
      this.text,
      MessageState.NEW,
      this.type,
    );

    return msg;
  }
}
