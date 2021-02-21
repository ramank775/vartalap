import 'dart:async';

import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/socketMessage.dart';
import 'package:vartalap/screens/chats/chat_preview.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/services/push_notification_service.dart';
import 'package:vartalap/services/socket_service.dart';
import 'package:vartalap/widgets/rich_message.dart';

class Chats extends StatefulWidget {
  @override
  ChatsState createState() => ChatsState();
}

class ChatsState extends State<Chats> {
  Future<List<ChatPreview>> _fChats;
  List<ChatPreview> _selectedChats = [];

  ConfigStore config;
  @override
  void initState() {
    super.initState();
    this._fChats = ChatService.getChats();
    this._selectedChats = [];
    this.config = ConfigStore();
    PushNotificationService.instance.config(
      onLaunch: (Map<String, dynamic> message) {
        // TODO: handle background notification
      },
      onResume: (Map<String, dynamic> message) {
        // TODO: handle resume notification
      },
      onMessage: (Map<String, dynamic> payload) {
        if (payload == null || payload["data"] == null) return;
        var msg = payload["data"]["message"];
        if (msg == null) return;
        var source = payload["source"];
        if (source != null &&
            source is String &&
            source == "ON_NOTIFICATION_TAP") {
          return;
        }
        try {
          var smsg = SocketMessage.fromMap(msg);
          SocketService.instance.externalNewMessage(smsg);
        } catch (e, stack) {
          print(e);
          print(stack);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: AppBar(
        title: new Text('Vartalap'),
        actions: getActions(),
      ),
      body: new Container(
        padding: EdgeInsets.fromLTRB(5, 5, 5, 0),
        child: FutureBuilder<List<ChatPreview>>(
          future: this._fChats,
          builder: (context, snapshot) {
            switch (snapshot.connectionState) {
              case ConnectionState.none:
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: new AlwaysStoppedAnimation<Color>(Colors.grey),
                  ),
                );
              case ConnectionState.active:
              case ConnectionState.waiting:
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: new AlwaysStoppedAnimation<Color>(Colors.grey),
                  ),
                );
              case ConnectionState.done:
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }
            }
            return ChatListView(
              chats: snapshot.data,
              selectedChats: _selectedChats,
              selectOrRemove: this.selectOrRemove,
              navigate: this.navigate,
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => navigate('/new-chat'),
        tooltip: 'New',
        child: Icon(Icons.add),
      ),
    );
  }

  void selectOrRemove(Chat chat) {
    setState(() {
      if (!_selectedChats.remove(chat)) {
        _selectedChats.add(chat);
      }
    });
  }

  List<Widget> getActions() {
    List<Widget> actions = [];
    if (this._selectedChats.length > 0) {
      actions.add(IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          setState(() {
            this._selectedChats = [];
          });
        },
      ));
      actions.add(IconButton(
        icon: Icon(Icons.delete),
        onPressed: () async {
          await ChatService.deleteChats(this._selectedChats);
          setState(() {
            this._selectedChats = [];
            this._fChats = ChatService.getChats();
          });
        },
      ));
    }
    actions.add(PopupMenuButton(
        itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                value: 'About Dialog',
                child: GestureDetector(
                  child: Container(
                    child: Text("About us"),
                  ),
                  onTap: () {
                    Navigator.of(context).pop('About Dialog');
                    showAboutDialog(
                      context: context,
                      applicationName: config.packageInfo.appName,
                      applicationIcon: Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.blueAccent,
                        size: 30.0,
                      ),
                      applicationVersion:
                          "${config.packageInfo.version}+${config.packageInfo.buildNumber}",
                      children: <Widget>[
                        Text('Vartalap is an open source chat messager.'),
                        RichMessage(
                          config.get("description"),
                          TextStyle(fontSize: 12, color: Colors.black),
                        ),
                      ],
                    );
                  },
                ),
              )
            ]));
    return actions;
  }

  Future<void> navigate(String screen, {Object data}) async {
    var result = await Navigator.pushNamed(context, screen, arguments: data);
    if (screen == "/new-chat") {
      if (result == null) {
        return;
      }
      Chat chat;
      if (result is Chat) {
        chat = result;
      } else {
        chat = await ChatService.newIndiviualChat(result);
      }
      await Navigator.of(context).pushNamed('/chat', arguments: chat);
    }
    setState(() {
      _fChats = ChatService.getChats();
    });
  }
}

class ChatListView extends StatefulWidget {
  const ChatListView(
      {Key key,
      @required List<ChatPreview> chats,
      @required List<ChatPreview> selectedChats,
      @required Function selectOrRemove,
      @required Function navigate})
      : _chats = chats,
        _selectedChats = selectedChats,
        _selectOrRemove = selectOrRemove,
        _navigate = navigate,
        super(key: key);

  final List<ChatPreview> _chats;
  final List<ChatPreview> _selectedChats;
  final Function _selectOrRemove;
  final Function _navigate;

  @override
  State<StatefulWidget> createState() => ChatListViewState();
}

class ChatListViewState extends State<ChatListView> {
  StreamSubscription _newMessageSub;
  StreamSubscription _groupNotificationSub;
  List<ChatPreview> _chats;
  @override
  void initState() {
    super.initState();
    _chats = widget._chats;
    _newMessageSub = ChatService.onNewMessageStream.listen(_onNewMessage);
    _groupNotificationSub = ChatService.onNotificationMessagStream
        .where((notification) => notification.module == "group")
        .listen(_onGroupNotification);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _chats.length,
      itemBuilder: (context, i) => new ChatPreviewWidget(
        _chats[i],
        (Chat chat) async {
          if (widget._selectedChats.length > 0) {
            widget._selectOrRemove(chat);
            return;
          }
          if (chat.users.length == 0) {
            var _users = await ChatService.getChatUserByid(chat.id);
            _users.forEach((u) {
              chat.addUser(u);
            });
          }
          widget._navigate('/chat', data: chat);
        },
        widget._selectOrRemove,
        isSelected: widget._selectedChats.contains(widget._chats[i]),
      ),
    );
  }

  _onNewMessage(SocketMessage msg) async {
    PushNotificationService.instance
        .showNotification('New Message', msg.text, msg.toMap());
    var chat = _chats.firstWhere((_chat) => _chat.id == msg.chatId,
        orElse: () => null);
    if (chat == null) {
      chat = await ChatService.getChatById(msg.chatId);
      setState(() {
        widget._chats.insert(0, chat);
      });
      return;
    } else {
      var _msg = msg.toMessage();
      chat = ChatPreview(chat.id, chat.title, chat.pic, _msg.text,
          _msg.timestamp, (chat.unread + 1));
    }
    var chats = _chats.where((_chat) => _chat.id != msg.chatId).toList();
    chats.insert(0, chat);
    setState(() {
      _chats = chats;
    });
  }

  _onGroupNotification(SocketMessage msg) async {
    var chatIdx = _chats.indexWhere((_chat) => _chat.id == msg.chatId);
    if (chatIdx == -1) {
      return;
    }
    var chat = _chats[chatIdx];
    if (chat.users.isEmpty) return;

    chat.resetUsers();
    var users = await ChatService.getChatUserByid(chat.id);
    users.forEach((u) => chat.addUser(u));
  }

  @override
  void dispose() {
    _newMessageSub.cancel();
    _groupNotificationSub.cancel();
    super.dispose();
  }
}
