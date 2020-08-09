import 'package:chat_flutter_app/dataAccessLayer/db.dart';
import 'package:chat_flutter_app/models/chat.dart';
import 'package:chat_flutter_app/models/message.dart';
import 'package:chat_flutter_app/models/user.dart';
import 'package:chat_flutter_app/services/user_service.dart';

class ChatService {
  static Future<Chat> newIndiviualChat(User user) async {
    var db = await DB().getDb();
    var result =
        await db.query("chat", where: "id=?", whereArgs: [user.username]);
    Chat chat;
    if (result == null || result.length == 0) {
      chat = Chat(user.username, user.name, user.pic);

      chat.addUser(ChatUser.fromUser(user));
      var currentUser = ChatUser.fromUser(UserService.getLoggedInUser());
      chat.addUser(currentUser);
    } else {
      chat = Chat.fromMap(result[0]);
      var chatUsers = await _getChatUser(chat.id);
      chatUsers.forEach((u) {
        chat.addUser(u);
      });
    }
    return chat;
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

  static Future<List<User>> _getChatUser(String chatId) async {
    var db = await DB().getDb();
    var result =
        await db.query("chat_user", where: "chatid=?", whereArgs: [chatId]);
    var users = result.map((e) => User.fromMap(e)).toList();
    return users;
  }
}
