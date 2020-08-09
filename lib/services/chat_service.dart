import 'package:chat_flutter_app/dataAccessLayer/db.dart';
import 'package:chat_flutter_app/models/chat.dart';
import 'package:chat_flutter_app/models/message.dart';
import 'package:chat_flutter_app/models/user.dart';
import 'package:chat_flutter_app/services/user_service.dart';
import 'package:chat_flutter_app/utils/enum_helper.dart';

class ChatService {
  static Future<List<Chat>> getChats() async {
    var db = await DB().getDb();
    var sql = """Select chat.*, message.* 
    from chat
    inner join message on message.id in (
      select id 
      from message
      where chatid == chat.id
      order by ts desc
      Limit 1
    )
    order by message.ts desc;""";
    var result = await db.rawQuery(sql);
    print(result);
    return result.map((e) => Chat.fromMap(e)).toList();
  }

  static Future<Chat> newIndiviualChat(User user) async {
    Chat chat = await _getChatById(user.username);
    if (chat == null) {
      chat = Chat(user.username, user.name, user.pic);
      chat.addUser(ChatUser.fromUser(user));
      var currentUser = ChatUser.fromUser(UserService.getLoggedInUser());
      chat.addUser(currentUser);
    } else {
      var chatUsers = await _getChatUser(chat.id);
      chatUsers.forEach((u) {
        chat.addUser(u);
      });
    }
    return chat;
  }

  static Future<void> sendMessage(Message msg, Chat chat) async {
    var _isNew = (await _getChatById(chat.id)) == null;
    if (_isNew) {
      await _saveChat(chat);
    }
    await _saveMessage(msg);
  }

  static Future<List<Message>> getChatMessage(String chatid) async {
    var db = await DB().getDb();
    var result = await db.query("message",
        where: "chatid=?", whereArgs: [chatid], orderBy: "ts");
    var userResult = await _getChatUser(chatid);
    List<Message> msgs = [];
    result.forEach((msgMap) {
      var msg = Message.fromMap(msgMap);
      var user = userResult.singleWhere((u) => u.username == msg.senderId);
      msg.sender = user;
      msgs.add(msg);
    });
    return msgs;
  }

  static Future<Chat> _getChatById(String chatid) async {
    var db = await DB().getDb();
    var result = await db.query("chat", where: "id=?", whereArgs: [chatid]);
    if (result != null && result.length > 0) {
      return Chat.fromMap(result[0]);
    }
    return null;
  }

  static Future<List<ChatUser>> _getChatUser(String chatid) async {
    var db = await DB().getDb();
    var sql = """Select user.*, chat_user.role
    From chat_user
    INNER JOIN user ON user.username = chat_user.userid
    WHERE chatid=?
    """;
    var result = await db.rawQuery(sql, [chatid]);
    var users = result.map((e) => ChatUser.fromMap(e)).toList();
    return users;
  }

  static Future<bool> _saveChat(Chat chat) async {
    var db = await DB().getDb();
    var map = chat.toMap();
    map["createdOn"] = DateTime.now().toUtc().millisecond;
    var result = await db.insert("chat", map);
    await _saveChatUser(chat.id, chat.users);
    return result > 0;
  }

  static Future<bool> _saveChatUser(String chatid, List<ChatUser> users) async {
    var db = await DB().getDb();
    var batch = db.batch();
    users.forEach((user) {
      Map<String, dynamic> map = Map();
      map["userid"] = user.username;
      map["chatid"] = chatid;
      map["role"] = enumToInt(user.role, UserRole.values);
      batch.insert("chat_user", map);
    });
    var result = await batch.commit();
    return result.length == users.length;
  }

  static Future<bool> _saveMessage(Message msg) async {
    var db = await DB().getDb();
    var result = await db.insert("message", msg.toMap());
    print("Save Msg Result : $result");
    return result > 0;
  }
}
