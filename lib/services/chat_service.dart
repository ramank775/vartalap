import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:vartalap/dataAccessLayer/db.dart';
import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/remoteMessage.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/services/api_service.dart';
import 'package:vartalap/services/socket_service.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:vartalap/utils/enum_helper.dart';
import 'package:vartalap/utils/find.dart';

class ChatService {
  static late Stream<RemoteMessage> onNewMessageStream;
  static late Stream<RemoteMessage> onNotificationMessagStream;
  static late StreamSubscription<RemoteMessage> _newMessageSub$;
  static late StreamSubscription<RemoteMessage> _notificationSub$;

  static Future<void> init() async {
    onNewMessageStream = SocketService.instance.stream
        .where((msg) => msg.head.contentType != MessageType.NOTIFICATION)
        .asyncMap(_onNewMessage)
        .where((RemoteMessage? msg) => msg != null)
        .map((event) => event!)
        .asBroadcastStream();
    onNotificationMessagStream = SocketService.instance.stream
        .where((msg) => msg.head.contentType == MessageType.NOTIFICATION)
        .asyncMap(_onNotificationMsg)
        .where((RemoteMessage? msg) => msg != null)
        .asBroadcastStream();
    _newMessageSub$ = onNewMessageStream.listen((msg) async {
      await ackMessageDelivery([msg], socket: true);
    });
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
      where chatid == chat.id and senderid !=? and state in (0,2)
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

  static Future<Chat?> getChatInfo(String chatid) async {
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
    Chat? chat = await _getChatById(chatid);
    if (chat == null) {
      chat = Chat(chatid, user.name, user.pic);
      chat.addUser(ChatUser.fromUser(user));
      var currentUser = ChatUser.fromUser(UserService.getLoggedInUser());
      chat.addUser(currentUser);
    } else {
      var chatUsers = await _getChatUser(chat.id);
      chatUsers.forEach((u) {
        chat!.addUser(u);
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

  static Future<void> sendMessage(TextMessage msg, Chat chat) async {
    var _isNew = (await _getChatById(chat.id)) == null;
    if (_isNew) {
      await _saveChat(chat);
    }
    await _saveMessage(msg);
    if (_isSelfChat(chat)) return;
    RemoteMessage smsg = RemoteMessage.fromChatMessage(msg, chat);
    await SocketService.instance.send(smsg);
  }

  static Future<List<TextMessage>> getChatMessages(String chatid) async {
    var db = await DB().getDb();
    var result = await db.query("message",
        where: "chatid=?", whereArgs: [chatid], orderBy: "ts");
    var userResult = (await _getChatUser(chatid)).toSet();
    List<TextMessage> msgs = [];
    var currentUser = UserService.getLoggedInUser();
    result.forEach((msgMap) {
      var msg = TextMessage.fromMap(msgMap);
      ChatUser? user = find(userResult, (u) => u.username == msg.senderId);
      if (user == null && msg.senderId == currentUser.username) {
        user = ChatUser.fromUser(currentUser);
      }
      msg.sender = user;
      msgs.add(msg);
    });
    return msgs.reversed.toList();
  }

  static Future<bool> deleteMessages(List<String> msgIds) async {
    var db = await DB().getDb();
    var batch = db.batch();
    for (var id in msgIds) {
      batch.delete("message", where: "id=?", whereArgs: [id]);
    }
    var result = await batch.commit();
    return result.length > 0;
  }

  static Future markAsRead(List<String> msgIds, Chat chat) async {
    if (msgIds.length == 0) return;
    await updateMessageState(msgIds, MessageState.READ);
    final current = UserService.getLoggedInUser();
    final stateNotification =
        StateMessge(chat.id, current.username, MessageState.READ);
    stateNotification.msgIds.addAll(msgIds);
    final smsg = RemoteMessage.fromChatMessage(stateNotification, chat);
    await SocketService.instance.send(smsg);
  }

  static Future updateMessageState(
      List<String> msgIds, MessageState state) async {
    final db = await DB().getDb();
    int stateIdx = enumToInt(state, MessageState.values);
    var batch = db.batch();
    msgIds.forEach((id) {
      batch.update(
          "message",
          {
            "state": stateIdx,
          },
          where: "id=? and state < ? and state !=?",
          whereArgs: [
            id,
            stateIdx,
            enumToInt(MessageState.OTHER, MessageState.values)
          ]);
    });
    await batch.commit();
  }

  static Future<RemoteMessage?> newMessage(RemoteMessage msg) async {
    if (msg.head.contentType == MessageType.NOTIFICATION) {
      return _onNotificationMsg(msg);
    }
    return _onNewMessage(msg);
  }

  static Future ackMessageDelivery(List<RemoteMessage> msgs,
      {bool socket = false}) async {
    final List<RemoteMessage> messages = [];
    final Set<String> chatIds = new Set();
    for (var i = 0; i < msgs.length; i++) {
      final msg = msgs[i];
      if (msg.head.chatid == null) continue;
      messages.add(msg);
      chatIds.add(msg.head.chatid!);
    }
    if (messages.isEmpty) return;
    Map<String, Chat> chats = {};
    for (var i = 0; i < chatIds.length; i++) {
      final chatid = chatIds.elementAt(i);
      final chat = await getChatInfo(chatid);
      if (chat == null) continue;
      if (chat.type == ChatType.INDIVIDUAL) {
        final chatusers = await getChatUserByid(chatid);
        chatusers.forEach((user) {
          chat.addUser(user);
        });
      }
      chats[chatid] = chat;
    }

    if (chats.isEmpty) return;

    final currentUser = UserService.getLoggedInUser();
    final deliveryAck = messages.map((msg) {
      final stateNotification = StateMessge(
          msg.head.chatid!, currentUser.username, MessageState.DELIVERED);
      stateNotification.msgIds.add(msg.id);
      final chat = chats[msg.head.chatid!]!;
      final smsg = RemoteMessage.fromChatMessage(stateNotification, chat);
      return smsg;
    });

    if (socket) {
      deliveryAck.forEach((smsg) {
        SocketService.instance.send(smsg);
      });
    } else {
      await ApiService.sendMessages(deliveryAck);
    }
  }

  static Future<Chat?> _getChatById(String chatid) async {
    var db = await DB().getDb();
    var result = await db.query("chat", where: "id=?", whereArgs: [chatid]);
    if (result.length > 0) {
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

  static Future<bool> _saveMessage(TextMessage msg) async {
    var db = await DB().getDb();
    var result = await db.insert(
      "message",
      msg.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return result > 0;
  }

  static Future<bool> _isDuplicate(RemoteMessage message) async {
    var db = await DB().getDb();
    var msg = await db.query("message", where: "id=?", whereArgs: [message.id]);
    return msg.length > 0;
  }

  static Future<RemoteMessage?> _onNewMessage(RemoteMessage msg) async {
    var isduplicat = await _isDuplicate(msg);
    if (isduplicat) return null;
    if (msg.head.chatid == null) {
      msg.head.chatid = _createChatIdFromMsg(msg);
    }
    Chat? chat = await _getChatById(msg.head.chatid!);
    if (chat == null) {
      if (msg.head.to == msg.head.chatid) {
        chat = await _createGroupChat(msg.head.to);
      } else {
        chat = await _createIndiviualChat(msg.head.chatid!, msg.head.from);
      }
    }
    TextMessage _msg = TextMessage(
      msg.id,
      chat.id,
      msg.head.from,
      msg.body['text'],
      MessageState.DELIVERED,
      msg.head.contentType,
    );
    await _saveMessage(_msg);
    return msg;
  }

  static String _createChatIdFromMsg(RemoteMessage msg) {
    if (msg.head.to != UserService.getLoggedInUser().username) {
      msg.head.chatid = msg.head.to;
    } else {
      msg.head.chatid =
          _createIndiviualChatId(User(msg.head.from, msg.head.from, null));
    }
    return msg.head.chatid!;
  }

  static Future<RemoteMessage> _onNotificationMsg(RemoteMessage msg) async {
    if (msg.head.action == "state") {
      final List<String> ids =
          (msg.body["ids"] as List).map((e) => e.toString()).toList();
      final MessageState state =
          stringToEnum(msg.body["state"], MessageState.values);
      await updateMessageState(ids, state);
    } else if (msg.head.type == ChatType.GROUP) {
      var result = await _getChatById(msg.head.to);
      if (result == null) {
        await _createGroupChat(msg.head.to);
      }
      switch (msg.head.action) {
        case 'add':
          await _addGroupUsers(msg.head.to);
          break;
        case 'remove':
          await _removeGroupUsers(msg.head.to);
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
    User? user = await UserService.getUserById(from);
    if (user == null) {
      user = User(from, from, null, status: UserStatus.UNKNOWN);
      user.hasAccount = true;
      await UserService.addUser(user);
    }
    var self = UserService.getLoggedInUser();
    User? currentUser = await UserService.getUserById(self.username);
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
