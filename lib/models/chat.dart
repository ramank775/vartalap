import 'package:chat_flutter_app/utils/enum_helper.dart';

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
}

class Chat {
  String _id;
  String _title;
  String _pic;
  List<ChatUser> _users = [];

  Chat(this._id, this._title, this._pic);

  String get id => _id;
  String get title => _title;
  String get pic => _pic;
  List<ChatUser> get users => _users;

  Chat.fromMap(Map<String, dynamic> map) {
    this._id = map["id"];
    this._title = map["title"];
    this._pic = map["pic"];
  }

  int get hashCode => "chat_$id".hashCode;

  void addUser(ChatUser user) {
    for (var _user in this._users) {
      if (_user.username == user.username) {
        return;
      }
    }
    this._users.add(user);
  }

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}
