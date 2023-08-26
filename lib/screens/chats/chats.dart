import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/remoteMessage.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/chat_message_helper.dart';
import 'package:vartalap/widgets/Inherited/config_provider.dart';
import 'package:vartalap/widgets/chat_preview.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/services/push_notification_service.dart';
import 'package:vartalap/services/socket_service.dart';
import 'package:vartalap/utils/find.dart';
import 'package:vartalap/utils/url_helper.dart';
import 'package:vartalap/widgets/app_logo.dart';
import 'package:vartalap/widgets/rich_message.dart';

class Chats extends StatefulWidget {
  @override
  ChatsState createState() => ChatsState();
}

class ChatsState extends State<Chats> {
  late Future<List<ChatPreview>> _fChats;
  List<ChatPreview> _selectedChats = [];
  late ConfigStore config;

  @override
  void initState() {
    super.initState();

    this._fChats = ChatService.getChats();
    this._selectedChats = [];
    PushNotificationService.instance.config(
      onMessage: (Map<String, dynamic> payload) {
        if (payload["data"] == null) return;
        var msg = payload["data"]["message"];
        if (msg == null) return;
        var source = payload["source"];
        if (source != null &&
            source is String &&
            source == "ON_NOTIFICATION_TAP") {
          return;
        }
        try {
          var smsg = RemoteMessage.fromMap(msg);
          SocketService.instance.externalNewMessage(smsg);
        } catch (e) {
          throw e;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    config = ConfigProvider.of(context).configStore;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          config.packageInfo.appName,
          style: VartalapTheme.theme.appTitleStyle.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
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
              chats: snapshot.data!,
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
        backgroundColor: Theme.of(context).iconTheme.color,
      ),
    );
  }

  void selectOrRemove(ChatPreview chat) {
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
        iconSize: 22,
        icon: Icon(Icons.clear),
        onPressed: () {
          setState(() {
            this._selectedChats = [];
          });
        },
      ));
      actions.add(IconButton(
        iconSize: 22,
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
    actions.add(
      PopupMenuButton(
        onSelected: (value) async {
          //Navigator.of(context).pop(value);
          if (value == 'About Dialog') {
            showAboutDialog(
              context: context,
              applicationName: config.packageInfo.appName,
              applicationIcon: AppLogo(size: 25),
              applicationVersion:
                  "${config.packageInfo.version}+${config.packageInfo.buildNumber}",
              children: <Widget>[
                Text(
                  config.subtitle,
                ),
                RichMessage(
                  config.get("description"),
                  TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                Text("------------------------------------------------"),
                RichMessage(
                    """Server Info:\n API URL: ${config.get("api_url")} \n WebSocket: ${config.get("ws_url")}""",
                    TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ))
              ],
            );
          } else if (value == 'Privacy Policy') {
            var link = config.get('privacy_policy');
            launchUrl(link);
          } else if (value == "Logout") {
            await AuthService.instance.signout();
          }
        },
        itemBuilder: (BuildContext context) {
          final options = [
            PopupMenuItem(value: 'About Dialog', child: Text("About us")),
            PopupMenuItem(
              value: 'Privacy Policy',
              child: Text("Privacy Policy"),
            ),
          ];
          if (!kReleaseMode) {
            options.add(PopupMenuItem(child: Text("Logout"), value: "Logout"));
          }
          return options;
        },
      ),
    );
    return actions;
  }

  Future<void> navigate(String screen, {Object? data}) async {
    var result = await Navigator.pushNamed(context, screen, arguments: data);
    if (screen == "/new-chat") {
      if (result == null) {
        return;
      }
      Chat chat;
      if (result is Chat) {
        chat = result;
      } else {
        chat = await ChatService.newIndiviualChat(result as User);
      }
      await Navigator.of(context).pushNamed('/chat', arguments: chat);
    }
    setState(() {
      _fChats = ChatService.getChats();
    });
  }
}

class ChatListView extends StatefulWidget {
  const ChatListView({
    Key? key,
    required List<ChatPreview> chats,
    required List<ChatPreview> selectedChats,
    required Function selectOrRemove,
    required Function navigate,
  })  : _chats = chats,
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

class ChatListViewState extends State<ChatListView>
    with WidgetsBindingObserver {
  late StreamSubscription _newMessageSub;
  late StreamSubscription _groupNotificationSub;
  late List<ChatPreview> _chats;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chats = widget._chats;
    _newMessageSub = ChatService.onNewMessageStream.listen(_onNewMessage);
    _groupNotificationSub = ChatService.onNotificationMessagStream
        .where((notification) => notification.head.type == ChatType.GROUP)
        .listen(_onGroupNotification);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // These are the callbacks
    switch (state) {
      case AppLifecycleState.resumed:
        this._newMessageSub.resume();
        this._groupNotificationSub.resume();
        PushNotificationService.instance.clearAllNotification();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _chats.length == 0
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.group_add,
                  size: 50,
                ),
                SizedBox(
                  height: 5,
                ),
                RichText(
                  text: TextSpan(
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                      children: [
                        TextSpan(text: "Click"),
                        TextSpan(
                          text: " + ",
                          style: TextStyle(
                            color: Theme.of(context).iconTheme.color,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: "to create chat")
                      ]),
                )
              ],
            ),
          )
        : ListView.builder(
            itemCount: _chats.length,
            itemBuilder: (context, i) => new ChatPreviewWidget(
              _chats[i],
              (Chat chat) async {
                if (widget._selectedChats.length > 0) {
                  widget._selectOrRemove(chat);
                  return;
                }
                if (chat.users.length <= 1) {
                  final _users = await ChatService.getChatUserByid(chat.id);
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

  _onNewMessage(RemoteMessage msg) async {
    final msgInfo = msg.head;
    ChatPreview? chat = find(_chats, (_chat) => _chat.id == msgInfo.chatid);
    if (chat == null) {
      chat = await ChatService.getChatById(msgInfo.chatid!);
      setState(() {
        widget._chats.insert(0, chat!);
      });
      return;
    } else {
      var _msg = toChatMessage(msg);
      chat = ChatPreview(chat.id, chat.title, chat.pic, _msg.previewContent,
          _msg.timestamp, (chat.unread + 1));
    }
    PushNotificationService.instance.showNotification(
      chat.title,
      chat.content,
      msg.toMap(),
      groupKey: chat.id,
      id: chat.id.hashCode,
    );

    var chats = _chats.where((_chat) => _chat.id != msg.head.chatid).toList();
    chats.insert(0, chat);
    setState(() {
      _chats = chats;
    });
  }

  _onGroupNotification(RemoteMessage msg) async {
    var chatIdx = _chats.indexWhere((_chat) => _chat.id == msg.head.chatid);
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
