import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/utils/enum_helper.dart';

class Head {
  Head({
    required this.type,
    required this.to,
    required this.from,
    required this.chatid,
    required this.contentType,
    required this.action,
    this.category = 'message',
    this.ephemeral = false,
  });

  late ChatType type;
  late String to;
  late String from;
  late String? chatid;
  late MessageType contentType;
  late String action;
  late String category;
  late bool ephemeral;

  Head.fromMap(Map<String, dynamic> map) {
    this.type = stringToEnum(map["type"], ChatType.values);
    this.to = map["to"];
    this.from = map["from"];
    this.action = map["action"];
    this.contentType = stringToEnum(map["contentType"], MessageType.values);
    this.chatid = map["chatid"];
    this.category = map.containsKey("category") ? map["category"] : 'message';
    this.ephemeral = map.containsKey("ephemeral") ? map["ephemeral"] : false;
  }

  Map<String, dynamic> toMap() {
    return {
      "to": this.to,
      "from": this.from,
      "action": this.action,
      "chatid": this.chatid,
      "type": enumToString(this.type),
      "contentType": enumToString(this.contentType),
      "category": this.category,
      "ephemeral": this.ephemeral,
    };
  }
}

class Meta {
  Map<String, dynamic> raw = {};
  String get hash => raw['hash'];
  String get contentHash => raw['contentHash'];
  int get createdAt => raw.containsKey('createdAt')
      ? raw['createdAt']
      : DateTime.now().millisecondsSinceEpoch;

  Meta({String? hash, String? contentHash, int? createdAt}) {
    if (hash != null) {
      this.raw['hash'] = hash;
    }
    if (contentHash != null) {
      this.raw['contentHash'] = contentHash;
    }
    this.raw['createdAt'] =
        createdAt == null ? DateTime.now().millisecondsSinceEpoch : createdAt;
  }

  Meta.fromMap(Map<String, dynamic> map) {
    this.raw = map;
  }

  Map<String, dynamic> toMap() {
    return this.raw;
  }
}

class RemoteMessage {
  double _v = 2.1;
  double get ver => _v;
  late String id;
  late Head head;
  late Meta meta;
  late Map<String, dynamic> body;

  RemoteMessage.fromMessage(ChatMessage stateMsg, String to, ChatType type) {
    this.id = stateMsg.id;
    this.head = Head(
      action: stateMsg.action,
      contentType: stateMsg.type,
      chatid: stateMsg.chatId,
      from: stateMsg.senderId,
      type: type,
      to: to,
      category: stateMsg.category,
      ephemeral: stateMsg.ephemeral,
    );

    this.meta = Meta(
      createdAt: stateMsg.timestamp,
      contentHash: stateMsg.calcContentHash(),
    );

    this.body = stateMsg.toRemoteBody();
  }

  RemoteMessage.fromMap(Map<String, dynamic> map, {bool ignoreError = false}) {
    if (!map.containsKey("_v") && ignoreError) {
      // If the message doesn't counts version
      // It's probably an older message stuck in pending queue
      // If Ignore Error flag is set, Simply create a dummy Remote message
      this._v = 1.0;
      this.id = map.containsKey("id") ? map["id"] : "";
      this.head = Head(
        type: ChatType.OTHER,
        to: "",
        from: "",
        chatid: "",
        contentType: MessageType.OTHER,
        action: "",
      );
      this.meta = Meta();
      this.body = {};
      return;
    }
    this._v = map["_v"] + .0;
    this.id = map["id"];
    this.head = Head.fromMap(map["head"]);
    this.meta = map.containsKey("meta") ? Meta.fromMap(map["meta"]) : Meta();
    this.body = map["body"];
  }

  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = {
      "_v": this.ver,
      "id": this.id,
      "head": this.head.toMap(),
      "meta": this.meta.toMap(),
      "body": this.body
    };
    return map;
  }
}
