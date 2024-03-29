import 'package:permission_handler/permission_handler.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/dataAccessLayer/db.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:vartalap/services/api_service.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/crashlystics.dart';
import 'package:vartalap/services/performance_metric.dart';
import 'package:vartalap/utils/enum_helper.dart';
import 'package:vartalap/utils/find.dart';
import 'package:vartalap/utils/phone_number.dart';

class UserService {
  static bool _syncInProgress = false;
  static bool _syncOnInit = false;
  static User? _user;
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
      _user = User("Myself", _authService.phoneNumber!, null);
    }
    return _user!;
  }

  static Future<User?> getUserById(String username) async {
    var db = await DB().getDb();
    var userMap =
        await db.query('user', where: "username=?", whereArgs: [username]);
    if (userMap.length == 0) {
      return null;
    }
    return User.fromMap(userMap[0]);
  }

  static Future<List<User>> getUsers({String? search, bool sync = false}) async {
    if (sync) {
      await syncContacts();
    }
    String where = "hasAccount=? and status=?";
    List<dynamic> whereArgs = [
      1,
      enumToInt(UserStatus.ACTIVE, UserStatus.values)
    ];
    if (search != null && search.isNotEmpty) {
      where += " and (name like ? or username like ?)";
      whereArgs.add("%" + search + "%");
      whereArgs.add("%" + search + "%");
    }
    Database db = await DB().getDb();
    var userMap = await db.query('user',
        where: where, whereArgs: whereArgs, orderBy: 'name');
    var users = userMap.map((e) => User.fromMap(e)).toList();
    return users;
  }

  static Future<void> addUser(User user) async {
    var db = await DB().getDb();
    await db.insert("user", user.toMap(persistent: true));
  }

  static Future<bool> addUnknowUser(List<User> users) async {
    List<User> result = [];
    for (final user in users) {
      final u = await getUserById(user.username);
      if (u == null) result.add(user);
    }
    final db = await DB().getDb();
    Batch batch = db.batch();
    result.forEach((user) {
      batch.insert("user", user.toMap(persistent: true));
    });
    await batch.commit();
    return true;
  }

  static Future<void> syncContacts({bool onInit = false}) async {
    if (onInit && _syncOnInit) return;
    if (onInit) {
      _syncOnInit = true;
    }
    if (_syncInProgress) return;
    _syncInProgress = true;
    var syncContactTrace = PerformanceMetric.newTrace('sync-contact');
    await syncContactTrace.start();
    var users = await _getContacts();
    if (users.isEmpty) {
      syncContactTrace.putAttribute("nocontacts", true);
      syncContactTrace.stop();
      _syncInProgress = false;
      return;
    }
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
      ) values(?,?,?,?,?);""", user.toMap(persistent: true).values.toList());
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
      if (user.username != currentUser.username) {
        batch.rawUpdate("""UPDATE chat SET title=?, pic=?
        WHERE type=1 and id in (
          SELECT chatid FROM chat_user
          WHERE userid=?
        );
      """, [user.name, user.pic, user.username]);
      }
    });
    contactDiff[2].forEach((user) {
      batch.rawUpdate("""UPDATE user SET name=?, 
        pic=?,
        hasAccount=?,
        status=?
        WHERE username=?;
      """, [
        user.username, // Set name as username or phone number for deleted user
        user.pic,
        user.hasAccount ? 1 : 0,
        enumToInt(UserStatus.DELETED, UserStatus.values),
        user.username
      ]);
      if (user.username != currentUser.username) {
        batch.rawUpdate("""UPDATE chat SET title=?, pic=?
        WHERE type=1 and id in (
          SELECT chatid FROM chat_user
          WHERE userid=?
        );
      """, [user.username, user.pic, user.username]);
      }
    });
    await batch.commit();
    syncContactTrace.stop();
    _syncInProgress = false;
  }

  static Future<List<User>> _getContacts() async {
    final permission = await Permission.contacts.status;
    if (!permission.isGranted) return [];
    Iterable<Contact> contacts = await FlutterContacts.getContacts(
        withProperties: true, withThumbnail: false, withPhoto: false);
    List<User> users = [];
    contacts.forEach((contact) {
      (contact.phones).forEach((phone) {
        String? phoneNumber = normalizePhoneNumber(phone.normalizedNumber);
        if (phoneNumber != null) {
          users.add(User(
              contact.displayName.isNotEmpty
                  ? contact.displayName
                  : phoneNumber,
              phoneNumber,
              null));
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
    userToDelete = dbUsers
        .where((u) => (u.status != UserStatus.UNKNOWN && !users.contains(u)))
        .toList();
    users.forEach((u) {
      User? user = find(dbUsers, (e) => u == e);
      if (user == null) {
        userToInsert.add(u);
      } else if (user.name != u.name ||
          user.pic != u.pic ||
          user.hasAccount != u.hasAccount ||
          user.status != u.status) {
        userToUpdate.add(u);
      } else {
        userToInsert.add(u);
      }
    });
    return [userToInsert, userToUpdate, userToDelete];
  }
}
