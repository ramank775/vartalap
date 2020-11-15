import 'package:vartalap/models/user.dart';
import 'package:vartalap/dataAccessLayer/db.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:vartalap/services/api_service.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/crashanalystics.dart';
import 'package:vartalap/services/performance_metric.dart';
import 'package:vartalap/utils/enum_helper.dart';
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
    var userMap = await db.query('user',
        where: "hasAccount=? and status=?",
        whereArgs: [1, enumToInt(UserStatus.ACTIVE, UserStatus.values)]);
    var users = userMap.map((e) => User.fromMap(e)).toList();
    return users;
  }

  static Future<void> addUser(User user) async {
    var db = await DB().getDb();
    await db.insert("user", user.toMap());
  }

  static Future<void> syncContacts() async {
    var syncContactTrace = PerformanceMetric.newTrace('sync-contact');
    await syncContactTrace.start();
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
    } catch (e, stack) {
      Crashlytics.recordError(e, stack, reason: "Contact sync api error");
      syncContactTrace.putAttribute('error', e);
      syncContactTrace.stop();
      return;
    }
    Database db = await DB().getDb();
    var dbUsers = (await db.query('user')).map((e) => User.fromMap(e)).toList();
    var contactDiff = _getContactDiff(dbUsers, users);

    Batch batch = db.batch();
    contactDiff[0].forEach((user) {
      batch.rawInsert("""INSERT OR REPLACE INTO user (
        username,
        name,
        pic,
        hasAccount,
        status
      ) values(?,?,?,?,?);""", user.toMap().values.toList());
    });
    contactDiff[1].forEach((user) {
      batch.rawUpdate("""UPDATE user SET name=?, 
        pic=?,
        hasAccount=?,
        status=?
        WHERE username=?;
      """, [
        user.name,
        user.pic,
        user.hasAccount ? 1 : 0,
        enumToInt(user.status, UserStatus.values),
        user.username
      ]);
      batch.rawUpdate("""UPDATE chat SET title=?, pic=?
        WHERE type=1 and id in (
          SELECT chatid FROM chat_user
          WHERE userid=?
        );
      """, [user.name, user.pic, user.username]);
    });
    contactDiff[2].forEach((user) {
      batch.rawUpdate("""UPDATE user SET name=?, 
        pic=?,
        hasAccount=?,
        status=?
        WHERE username=?;
      """, [
        user.name,
        user.pic,
        user.hasAccount ? 1 : 0,
        enumToInt(UserStatus.DELETED, UserStatus.values),
        user.username
      ]);
      batch.rawUpdate("""UPDATE chat SET title=?, pic=?
        WHERE type=1 and id in (
          SELECT chatid FROM chat_user
          WHERE userid=?
        );
      """, [user.username, user.pic, user.username]);
    });
    await batch.commit();
    syncContactTrace.stop();
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

  static List<List<User>> _getContactDiff(
      List<User> dbUsers, List<User> users) {
    List<User> userToUpdate = [];
    List<User> userToDelete = [];
    List<User> userToInsert = [];
    dbUsers.forEach((u) {
      var user = users.firstWhere((e) => u == e);
      if (user == null) {
        userToDelete.add(user);
      } else if (user.name != u.name ||
          user.pic != u.pic ||
          user.hasAccount != u.hasAccount) {
        userToUpdate.add(user);
      } else {
        userToInsert.add(user);
      }
    });
    return [userToInsert, userToUpdate, userToDelete];
  }
}
