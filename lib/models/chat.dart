import 'package:vartalap/utils/enum_helper.dart';

import 'user.dart';

enum ChatType {
  INDIVIDUAL,
  GROUP,
}

enum UserRole {
  MEMBER,
  ADMIN,
}

class ChatUser extends User {
  UserRole _role = UserRole.MEMBER;
  ChatUser(String name, String username, String pic, [this._role])
      : super(name, username, pic);

  UserRole get role => _role;

  ChatUser.fromMap(Map<String, dynamic> map) : super.fromMap(map) {
    this._role = intToEnum(map["role"], UserRole.values);
  }

  ChatUser.fromUser(User user) : super(user.name, user.username, user.pic);

  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = new Map();
    map["name"] = this.name;
    map["username"] = this.username;
    map["pic"] = this.pic;
    map["role"] = enumToInt(this.role, UserRole.values);
    return map;
  }

  int get hashCode => "user_$username".hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}

class Chat {
  String _id;
  String _title;
  String _pic;
  Set<ChatUser> _users = new Set();

  Chat(this._id, this._title, this._pic);

  String get id => _id;
  String get title => _title;
  String get pic => _pic;
  List<ChatUser> get users => _users.toList();

  Chat.fromMap(Map<String, dynamic> map) {
    this._id = map["id"];
    this._title = map["title"];
    this._pic = map["pic"];
  }

  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = Map();
    map["id"] = this.id;
    map["title"] = this.title;
    map["pic"] = this.pic;
    return map;
  }

  int get hashCode => "chat_$id".hashCode;

  void addUser(ChatUser user) {
    this._users.add(user);
  }

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}

class ChatPreview extends Chat {
  String _content;
  int _ts;
  int _unread;
  ChatPreview(String id, String title, String pic, this._content, this._ts,
      this._unread)
      : super(id, title, pic);

  ChatPreview.fromMap(Map<String, dynamic> map) : super.fromMap(map) {
    this._content = map["text"];
    this._ts = map["ts"];
    this._unread = map["unread"] == null ? 0 : map["unread"];
  }

  String get content => this._content;
  int get ts => this._ts;
  int get unread => this._unread;
}
