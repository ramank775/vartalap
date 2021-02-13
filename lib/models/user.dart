import 'package:vartalap/utils/enum_helper.dart';

enum UserStatus {
  ACTIVE,
  DELETED,
  UNKNOWN,
}

class User {
  String _name;
  String _username;
  String _pic;
  UserStatus status = UserStatus.ACTIVE;
  bool hasAccount = false;
  String get name => _name;
  String get username => _username;
  String get pic => _pic;

  User(this._name, this._username, this._pic,
      {this.status = UserStatus.ACTIVE, this.hasAccount = false});
  User.fromMap(Map<String, dynamic> map) {
    this._name = map["name"];
    this._username = map["username"];
    this._pic = map["pic"];
    this.hasAccount = (map["hasAccount"] ?? 0) == 1;
    this.status = map.containsKey('status')
        ? intToEnum(map['status'], UserStatus.values)
        : UserStatus.ACTIVE;
  }
  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = Map();
    map["username"] = this.username;
    map["name"] = this.name;
    map["pic"] = this.pic;
    map["hasAccount"] = this.hasAccount;
    map["status"] = enumToInt(this.status, UserStatus.values);
    return map;
  }

  int get hashCode => "user_$username".hashCode;

  @override
  bool operator ==(Object other) {
    return hashCode == other.hashCode;
  }
}
