import 'package:vartalap/models/user.dart';
import 'package:vartalap/dataAccessLayer/db.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:vartalap/services/api_service.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/utils/phone_number.dart';

class UserService {
  static User _user;
  static AuthService _authService = AuthService.instance;
  static Future<bool> sendOTP(String phoneNumber) {
    return _authService.sendOtp(phoneNumber);
  }

  static Future<bool> authenicate(String otp) async {
    AuthResponse result = await _authService.verify(otp);
    if (result.status) {
      getLoggedInUser();
    }
    return result.status;
  }

  static Future<bool> isAuth() {
    return Future<bool>(() => _authService.isLoggedIn());
  }

  static User getLoggedInUser() {
    if (_user == null) {
      // fetch the current user
      _user = User("Myself", _authService.phoneNumber, null);
    }
    return _user;
  }

  static Future<User> getUserById(String username) async {
    var db = await DB().getDb();
    var userMap =
        await db.query('user', where: "username=?", whereArgs: [username]);
    if (userMap.length == 0) {
      return null;
    }
    return User.fromMap(userMap[0]);
  }

  static Future<List<User>> getUsers({bool sync: false}) async {
    if (sync) {
      await syncContacts();
    }
    Database db = await DB().getDb();
    var userMap = await db.query('user', where: "hasAccount=?", whereArgs: [1]);
    var users = userMap.map((e) => User.fromMap(e)).toList();
    return users;
  }

  static Future<void> addUser(User user) async {
    var db = await DB().getDb();
    await db.insert("user", user.toMap());
  }

  static Future<void> syncContacts() async {
    var users = await _getContacts();
    var currentUser = UserService.getLoggedInUser();
    if (!users.any((user) => user.username == currentUser.username)) {
      users.add(currentUser);
    }
    try {
      var result =
          await ApiService.syncContact(users.map((e) => e.username).toList());
      users.forEach((user) {
        user.hasAccount =
            result.containsKey(user.username) ? result[user.username] : false;
      });
    } catch (e) {
      print(e);
      return;
    }
    Database db = await DB().getDb();
    Batch batch = db.batch();
    users.forEach((user) {
      batch.rawInsert("""INSERT OR REPLACE INTO user (
        username,
        name,
        pic,
        hasAccount
      ) values(?,?,?,?);""", user.toMap().values.toList());
    });
    await batch.commit();
  }

  static Future<List<User>> _getContacts() async {
    Iterable<Contact> contacts = await ContactsService.getContacts(
        withThumbnails: false, photoHighResolution: false);
    List<User> users = [];
    contacts.forEach((contact) {
      contact.phones.forEach((phone) {
        String phoneNumber = normalizePhoneNumber(phone.value);
        if (phoneNumber != null) {
          users.add(User(contact.displayName, phoneNumber, null));
        }
      });
    });
    return users;
  }
}
