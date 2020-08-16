import 'package:vartalap/models/user.dart';
import 'package:vartalap/dataAccessLayer/db.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:sqflite/sqflite.dart';

class UserService {
  static User _user;
  static User getLoggedInUser() {
    if (_user == null) {
      // fetch the current user
      _user = User("Raman", "8684892130", null);
    }
    return _user;
  }

  static Future<User> getUserById(String username) async {
    var db = await DB().getDb();
    var userMap = await db.query('user', where: "id=?", whereArgs: [username]);
    return User.fromMap(userMap[0]);
  }

  static Future<List<User>> getUsers({bool sync: false}) async {
    if (sync) {
      await syncContacts();
    }
    Database db = await DB().getDb();
    var userMap = await db.query('user');
    var users = userMap.map((e) => User.fromMap(e)).toList();
    return users;
  }

  static Future<void> syncContacts() async {
    var users = await _getContacts();
    // verify with the service with the users has account or not
    Database db = await DB().getDb();
    Batch batch = db.batch();
    users.forEach((user) {
      batch.rawInsert("""INSERT OR IGNORE INTO user (
        username,
        name,
        pic,
        hasAccount
      ) values(?,?,?,?);""", user.toMap().values.toList());
    });
    await batch.commit();
  }

  static Future<List<User>> _getContacts() async {
    Iterable<Contact> contacts = await ContactsService.getContacts();
    List<User> users = [];
    contacts.forEach((contact) {
      contact.phones.forEach((phone) {
        users.add(User(contact.displayName, phone.value, null));
      });
    });
    return users;
  }
}
