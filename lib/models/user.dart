enum UserStatus { PLATFORM_USER }

class User {
  String _name;
  String _username;
  String _pic;
  bool hasAccount = false;
  String get name => _name;
  String get username => _username;
  String get pic => _pic;

  User(this._name, this._username, this._pic);
  User.fromMap(Map<String, dynamic> map) {
    this._name = map["name"];
    this._username = map["username"];
    this._pic = map["pic"];
    this.hasAccount = (map["hasAccount"] ?? 0) == 1;
  }
  Map<String, dynamic> toMap() {
    Map<String, dynamic> map = Map();
    map["username"] = this.username;
    map["name"] = this.name;
    map["pic"] = this.pic;
    map["hasAccount"] = this.hasAccount;
    return map;
  }
}
