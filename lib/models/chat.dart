import 'package:vartalap/utils/enum_helper.dart';

import 'package:vartalap/models/user.dart';

enum ChatType {
  NONE,
  INDIVIDUAL,
  GROUP,
  OTHER,
}

enum UserRole {
  USER,
  ADMIN,
  EX_USER,
  OTHER,
}

class ChatUser extends User {
  UserRole role = UserRole.USER;
  ChatUser(String name, String username, String? pic,
      [this.role = UserRole.USER])
      : super(name, username, pic);

  ChatUser.fromMap(Map<String, dynamic> map) : super.fromMap(map) {
    this.role = intToEnum(map["role"], UserRole.values);
  }

  ChatUser.fromUser(User user) : super(user.name, user.username, user.pic);

  Map<String, dynamic> toMap({bool persistent = false}) {
    Map<String, dynamic> map = super.toMap(persistent: persistent);
    if (persistent) return map;
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
  late String _id;
  late String _title;
  String? _pic;
  ChatType type = ChatType.INDIVIDUAL;
  Set<ChatUser> _users = new Set();

  Chat(this._id, this._title, this._pic, {this.type = ChatType.INDIVIDUAL});

  String get id => _id;
  String get title => _title;
  String? get pic => _pic;
  List<ChatUser> get users => _users.toList();

  Chat.fromMap(Map<String, dynamic> map) {
    this._id = map["id"];
    this._title = map["title"];
    this._pic = map["pic"];
    this.type = intToEnum(map["type"] ?? 1, ChatType.values);
  }

  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = Map();
    map["id"] = this.id;
    map["title"] = this.title;
    map["pic"] = this.pic;
    map["type"] = enumToInt(this.type, ChatType.values);
    return map;
  }

  int get hashCode => "chat_$id".hashCode;

  void addUser(ChatUser user) {
    this._users.add(user);
  }

  void resetUsers() {
    this._users.clear();
  }

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}

class ChatPreview extends Chat {
  String _content = '';
  int _ts = 0;
  int _unread = 0;
  ChatPreview(String id, String title, String? pic, this._content, this._ts,
      this._unread)
      : super(id, title, pic);

  ChatPreview.fromMap(Map<String, dynamic> map) : super.fromMap(map) {
    this._content = map["text"] ?? '';
    this._ts = map["ts"] ?? 0;
    this._unread = map["unread"] == null ? 0 : map["unread"];
  }

  String get content => this._content;
  int get ts => this._ts;
  int get unread => this._unread;
}
