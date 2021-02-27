import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:vartalap/dataAccessLayer/db.dart';
import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/socketMessage.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/services/api_service.dart';
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
        .where((msg) => msg != null)
        .asBroadcastStream();
    onNotificationMessagStream = SocketService.instance.stream
        .where((msg) => msg.type == MessageType.NOTIFICATION)
        .asyncMap(_onNotificationMsg)
        .where((msg) => msg != null)
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

  static Future<Chat> getChatInfo(String chatid) async {
    var db = await DB().getDb();
    var result = await db.query("chat", where: "id = ?", whereArgs: [chatid]);
    if (result.isNotEmpty) {
      return Chat.fromMap(result.first);
    }
    return null;
  }

  static Future<List<Chat>> getGroups({String search = ""}) async {
    var db = await DB().getDb();
    var sql = """Select chat.* 
    from chat 
    INNER JOIN chat_user ON chat.id = chat_user.chatid
    where chat.type ==? and chat.title like ? and chat_user.userid = ?
    order by createdOn DESC;
    """;

    var currentUser = UserService.getLoggedInUser();
    var chats = await db.rawQuery(sql, [
      enumToInt(ChatType.GROUP, ChatType.values),
      "%$search%",
      currentUser.username,
    ]);

    return chats.map((c) => Chat.fromMap(c)).toList();
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
      if (chat.type != ChatType.GROUP)
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

  static Future<Chat> newGroupChat(String title, List<User> members) async {
    var memberIds = members.map((user) => user.username).toList();
    var groupId = await ApiService.createGroup(title, memberIds, null);
    Chat newChat = Chat(groupId, title, null, type: ChatType.GROUP);
    members.forEach((member) {
      newChat.addUser(ChatUser.fromUser(member));
    });
    var self = UserService.getLoggedInUser();
    newChat.addUser(ChatUser.fromUser(self));
    await _saveChat(newChat);
    return newChat;
  }

  static Future<void> addGroupMembers(Chat chat, List<User> members) async {
    if (chat.type != ChatType.GROUP) return;
    var db = await DB().getDb();
    var existingUsers = await getChatUserByid(chat.id);
    members.retainWhere((u) => !existingUsers.contains(u));
    await db.transaction((Transaction txn) async {
      var batch = txn.batch();
      members.forEach((user) {
        Map<String, dynamic> map = Map();
        map["userid"] = user.username;
        map["chatid"] = chat.id;
        map["role"] = enumToInt(UserRole.USER, UserRole.values);
        batch.insert("chat_user", map);
      });
      await batch.commit();
      await ApiService.addMembersToGroup(
          members.map((u) => u.username).toList(), chat.id);
    });
  }

  static Future<void> leaveGroup(Chat chat) async {
    var currentUser = UserService.getLoggedInUser();
    return removeGroupMembers(chat, currentUser);
  }

  static Future<void> removeGroupMembers(Chat chat, User member) async {
    if (chat.type != ChatType.GROUP) return;
    var db = await DB().getDb();
    await db.transaction((Transaction txn) async {
      await txn.delete("chat_user",
          where: "userid=? and chatid=?",
          whereArgs: [member.username, chat.id]);
      await ApiService.removeMemberToGroup(member.username, chat.id);
    });
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

  static Future<SocketMessage> newMessage(SocketMessage msg) async {
    if (msg.type == MessageType.NOTIFICATION) {
      return _onNotificationMsg(msg);
    }
    return _onNewMessage(msg);
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
    map["createdOn"] = DateTime.now().millisecondsSinceEpoch;
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

  static Future<bool> _removeChatUser(
      String chatid, List<ChatUser> users) async {
    var db = await DB().getDb();
    var batch = db.batch();
    users.forEach((user) {
      batch.delete("chat_user", where: "userid=?", whereArgs: [user.username]);
    });
    await batch.commit();
    return true;
  }

  static Future<bool> _saveMessage(Message msg) async {
    var db = await DB().getDb();
    var result = await db.insert("message", msg.toMap());
    return result > 0;
  }

  static Future<bool> _isDuplicate(SocketMessage message) async {
    var db = await DB().getDb();
    var msg =
        await db.query("message", where: "id=?", whereArgs: [message.msgId]);
    return msg.length > 0;
  }

  static Future<SocketMessage> _onNewMessage(SocketMessage msg) async {
    var isduplicat = await _isDuplicate(msg);
    if (isduplicat) return null;
    if (msg.chatId == null) {
      msg.chatId = _createChatIdFromMsg(msg);
    }
    Chat chat = await _getChatById(msg.chatId);
    if (chat == null) {
      if (msg.to == msg.chatId) {
        chat = await _createGroupChat(msg.to);
      } else {
        chat = await _createIndiviualChat(msg.chatId, msg.from);
      }
    }
    Message _msg = Message(msg.msgId, chat.id, msg.from, msg.text,
        MessageState.NEW, DateTime.now().millisecondsSinceEpoch, msg.type);
    await _saveMessage(_msg);
    return msg;
  }

  static String _createChatIdFromMsg(SocketMessage msg) {
    if (msg.to != UserService.getLoggedInUser().username) {
      msg.chatId = msg.to;
    } else {
      msg.chatId = _createIndiviualChatId(User(msg.from, msg.from, null));
    }
    return msg.chatId;
  }

  static Future<SocketMessage> _onNotificationMsg(SocketMessage msg) async {
    var db = await DB().getDb();
    if (msg.from == SocketService.name) {
      await db.update(
          "message",
          {
            "state": enumToInt(msg.state, MessageState.values),
          },
          where: "id=?",
          whereArgs: [msg.msgId]);
    } else if (msg.module == "group") {
      var result = await _getChatById(msg.to);
      if (result == null) {
        await _createGroupChat(msg.to);
      }
      switch (msg.action) {
        case 'add':
          await _addGroupUsers(msg.to);
          break;
        case 'remove':
          await _removeGroupUsers(msg.to);
          break;
        default:
      }
    }
    return msg;
  }

  static Future<Chat> _fetchGroupInfo(String id) async {
    var group = await ApiService.getGroupInfo(id);
    Chat chat = Chat(
      id,
      group["name"],
      group["profilePic"],
      type: ChatType.GROUP,
    );
    List<Map<String, dynamic>> members = (group["members"] as List).map((m) {
      return m as Map<String, dynamic>;
    }).toList();

    members.forEach((member) {
      User u = User(member["username"], member["username"], null,
          status: UserStatus.UNKNOWN, hasAccount: true);
      ChatUser user = ChatUser.fromUser(u);
      user.role = stringToEnum(member["role"], UserRole.values);
      chat.addUser(user);
    });
    return chat;
  }

  static Future<Chat> _createGroupChat(String id) async {
    Chat chat = await _fetchGroupInfo(id);
    await UserService.addUnknowUser(chat.users);
    await _saveChat(chat);
    return chat;
  }

  static Future _addGroupUsers(String id) async {
    Chat chat = await _fetchGroupInfo(id);
    List<ChatUser> users = await _getChatUser(id);
    List<ChatUser> usersToAdd = [];
    chat.users.forEach((user) {
      if (!users.contains(user)) {
        usersToAdd.add(user);
      }
    });
    if (usersToAdd.isNotEmpty) await _saveChatUser(id, usersToAdd);
  }

  static Future _removeGroupUsers(String id) async {
    Chat chat = await _fetchGroupInfo(id);
    List<ChatUser> users = await _getChatUser(id);
    List<ChatUser> usersToRemove = [];
    users.forEach((user) {
      if (!chat.users.contains(user)) {
        usersToRemove.add(user);
      }
    });
    if (usersToRemove.isNotEmpty) await _removeChatUser(id, usersToRemove);
  }

  static Future<Chat> _createIndiviualChat(String id, String from) async {
    Chat chat;
    User user = await UserService.getUserById(from);
    if (user == null) {
      user = User(from, from, null, status: UserStatus.UNKNOWN);
      user.hasAccount = true;
      await UserService.addUser(user);
    }
    var self = UserService.getLoggedInUser();
    User currentUser = await UserService.getUserById(self.username);
    if (currentUser == null) {
      await UserService.addUser(self);
    }
    chat = Chat(id, user.name, user.pic);
    chat.addUser(ChatUser.fromUser(user));

    chat.addUser(ChatUser.fromUser(self));
    await _saveChat(chat);
    return chat;
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
