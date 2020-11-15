import 'dart:async';

import 'package:vartalap/dataAccessLayer/db.dart';
import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/socketMessage.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/services/socket_service.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:vartalap/utils/enum_helper.dart';

class ChatService {
  static Stream<SocketMessage> onNewMessageStream;
  static Stream<SocketMessage> onNotificationMessagStream;
  static StreamSubscription<SocketMessage> _newMessageSub$;
  static StreamSubscription<SocketMessage> _notificationSub$;
  static Future<void> init() async {
    onNewMessageStream = SocketService.instance.stream
        .where((msg) => msg.type != MessageType.NOTIFICATION)
        .asyncMap(_onNewMessage)
        .asBroadcastStream();
    onNotificationMessagStream = SocketService.instance.stream
        .where((msg) => msg.type == MessageType.NOTIFICATION)
        .asyncMap(_onNotificationMsg)
        .asBroadcastStream();
    _newMessageSub$ = onNewMessageStream.listen((event) {});
    _notificationSub$ = onNotificationMessagStream.listen((event) {});
    await SocketService.instance.init();
  }

  static void dispose() {
    SocketService.instance.dispose();
    _newMessageSub$.cancel();
    _notificationSub$.cancel();
  }

  static Future<List<ChatPreview>> getChats() async {
    var db = await DB().getDb();
    var currentUser = UserService.getLoggedInUser();
    var sql = """Select chat.*, 
    message.senderid, message.text, message.state, message.ts ,
    ( select count(*) 
      from message 
      where chatid == chat.id and senderid !=? and state == 0
    ) unread
    from chat
    inner join message on message.id in (
      select id 
      from message
      where chatid == chat.id
      order by ts desc
      Limit 1
    )
    order by message.ts desc;""";
    var result = await db.rawQuery(sql, [currentUser.username]);
    return result.map((e) => ChatPreview.fromMap(e)).toList();
  }

  static Future<ChatPreview> getChatById(String chatid) async {
    var db = await DB().getDb();
    var currentUser = UserService.getLoggedInUser();
    var sql = """Select chat.*, 
    message.senderid, message.text, message.text, message.state, message.ts ,
    ( select count(*) 
      from message 
      where message.chatid == chat.id and message.senderid !=? and message.state = 0
    ) unread
    from chat
    inner join message on message.id in (
      select id 
      from message
      where chatid == chat.id
      order by ts desc
      Limit 1
    )
    where chat.id=?
    order by message.ts desc;""";
    var result = await db.rawQuery(sql, [currentUser.username, chatid]);
    return ChatPreview.fromMap(result[0]);
  }

  static Future<List<ChatUser>> getChatUserByid(String chatid) async {
    List<ChatUser> users = await _getChatUser(chatid);
    return users;
  }

  static Future<bool> deleteChats(List<Chat> chats) async {
    var db = await DB().getDb();
    var batch = db.batch();
    for (var chat in chats) {
      batch.delete("message", where: "chatid=?", whereArgs: [chat.id]);
      batch.delete("chat", where: "id=?", whereArgs: [chat.id]);
    }
    var result = await batch.commit();
    return result.length > 0;
  }

  static Future<Chat> newIndiviualChat(User user) async {
    var chatid = _createIndiviualChatId(user);
    Chat chat = await _getChatById(chatid);
    if (chat == null) {
      chat = Chat(chatid, user.name, user.pic);
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
    if (_isSelfChat(chat)) return;
    SocketMessage smsg = SocketMessage.fromChatMessage(msg, chat);
    await SocketService.instance.send(smsg);
  }

  static Future<List<Message>> getChatMessages(String chatid) async {
    var db = await DB().getDb();
    var result = await db.query("message",
        where: "chatid=?", whereArgs: [chatid], orderBy: "ts");
    var userResult = (await _getChatUser(chatid)).toSet();
    List<Message> msgs = [];
    var currentUser = UserService.getLoggedInUser();
    result.forEach((msgMap) {
      var msg = Message.fromMap(msgMap);
      var user = userResult.singleWhere((u) => u.username == msg.senderId,
          orElse: () => currentUser.username == msg.senderId
              ? ChatUser.fromUser(currentUser)
              : null);
      msg.sender = user;
      msgs.add(msg);
    });
    return msgs.reversed.toList();
  }

  static Future<bool> deleteMessages(List<Message> msgs) async {
    var db = await DB().getDb();
    var batch = db.batch();
    for (var msg in msgs) {
      batch.delete("message", where: "id=?", whereArgs: [msg.id]);
    }
    var result = await batch.commit();
    return result.length > 0;
  }

  static Future markAsDelivered(List<String> msgIds) async {
    var db = await DB().getDb();
    var batch = db.batch();
    msgIds.forEach((id) {
      batch.update(
          "message",
          {
            "state": enumToInt(MessageState.DELIVERED, MessageState.values),
          },
          where: "id=?",
          whereArgs: [id]);
    });
    await batch.commit();
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

  static Future<SocketMessage> _onNewMessage(SocketMessage msg) async {
    print('new message ${msg.msgId}');
    Chat chat = await _getChatById(msg.chatId);
    if (chat == null) {
      User user = await UserService.getUserById(msg.from);
      if (user == null) {
        user = User(msg.from, msg.from, null);
        user.hasAccount = true;
        await UserService.addUser(user);
      }
      var self = UserService.getLoggedInUser();
      User currentUser = await UserService.getUserById(self.username);
      if (currentUser == null) {
        await UserService.addUser(self);
      }
      chat = Chat(msg.chatId, user.name, user.pic);
      chat.addUser(ChatUser.fromUser(user));

      chat.addUser(ChatUser.fromUser(self));
      await _saveChat(chat);
    }
    Message _msg = Message(msg.msgId, chat.id, msg.from, msg.text,
        MessageState.NEW, DateTime.now().millisecondsSinceEpoch, msg.type);
    await _saveMessage(_msg);
    return msg;
  }

  static Future<SocketMessage> _onNotificationMsg(SocketMessage msg) async {
    if (msg.from == SocketService.name) {
      var db = await DB().getDb();
      await db.update(
          "message",
          {
            "state": enumToInt(msg.state, MessageState.values),
          },
          where: "id=?",
          whereArgs: [msg.msgId]);
    }
    return msg;
  }

  static String _createIndiviualChatId(User user) {
    var currentUser = UserService.getLoggedInUser();
    var users = [user.username, currentUser.username];
    users.sort();
    users = users.map((e) => e.replaceAll('+', '')).toList();
    return users.join();
  }

  static bool _isSelfChat(Chat chat) {
    var currentUser = UserService.getLoggedInUser();
    return (chat.users.length == 1 && chat.users.first == currentUser);
  }
}
