import 'dart:async';

import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/remoteMessage.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/screens/chat/chat_info.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/utils/chat_message_helper.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/chatlist.dart';
import 'package:vartalap/widgets/notifier/iterable_notifier.dart';
import 'package:vartalap/widgets/message_input.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  ChatScreen(this.chat) : super(key: Key(chat.id));

  @override
  ChatState createState() => ChatState(
        chat,
      );
}

class ChatState extends State<ChatScreen> with WidgetsBindingObserver {
  Chat _chat;
  late User _currentUser;
  late Future<List<ChatMessage>> _fMessages;
  ChatMessageController _messageController =
      new ChatMessageController(messages: []);
  final _selectedMessges = SetNotifier<String>(Set<String>());
  late StreamSubscription _notificationSub;
  late StreamSubscription _newMessageSub;
  Timer? _readTimer;
  Set<ChatMessage> _unreadMessages = Set<ChatMessage>();

  ChatState(this._chat);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
    this._fMessages = ChatService.getChatMessages(this._chat.id);
    this._fMessages.then((messages) {
      final unread = messages.where((msg) =>
          (msg.senderId != this._currentUser.username &&
              (msg.state == MessageState.NEW ||
                  msg.state == MessageState.DELIVERED)));
      _unreadMessages.addAll(unread);
    });

    this._notificationSub = ChatService.onNotificationMessagStream.where((msg) {
      final msgInfo = msg.head;
      if (msgInfo.chatid != null && msgInfo.chatid == _chat.id) {
        return true;
      } else if (msgInfo.type == ChatType.GROUP && msgInfo.to == _chat.id) {
        return true;
      }
      return false;
    }).listen(
      _onNotification,
      onError: (error) {},
      onDone: () {},
      cancelOnError: false,
    );
    this._newMessageSub = ChatService.onNewMessageStream
        .where((msg) => msg.head.chatid == this._chat.id)
        .listen(_onNewMessage, cancelOnError: false);

    _notificationSub.resume();
    _newMessageSub.resume();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // These are the callbacks
    switch (state) {
      case AppLifecycleState.resumed:
        this._newMessageSub.resume();
        this._notificationSub.resume();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    this._currentUser = CurrentUser.of(context).user!;
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          style: TextButton.styleFrom(
            shape: CircleBorder(),
            padding: const EdgeInsets.only(left: 1.0),
          ),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          child: Row(
            children: <Widget>[
              Icon(
                Icons.arrow_back,
                size: 24.0,
                color: Colors.white,
              ),
              Avator(
                text: this._chat.title,
                width: 30.0,
                height: 30.0,
              )
              // new ProfileImg(this._chat.pic ?? 'assets/images/default-user.png',
              //     ProfileImgSize.SM),
            ],
          ),
        ),
        title: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              if (this._chat.type == ChatType.GROUP &&
                  this._hasSendPermission()) {
                Chat? result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ChatInfo(this._chat),
                  ),
                );
                if (result != null) {
                  setState(() {
                    this._chat = result;
                  });
                }
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[this._getTitle(context)],
            ),
          ),
        ),
        actions: this._getActions(),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Flexible(
            flex: 1,
            child: FutureBuilder<List<ChatMessage>>(
                future: _fMessages,
                builder: (context, snapshot) {
                  switch (snapshot.connectionState) {
                    case ConnectionState.none:
                      return Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              new AlwaysStoppedAnimation<Color>(Colors.grey),
                        ),
                      );
                    case ConnectionState.active:
                    case ConnectionState.waiting:
                      return Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              new AlwaysStoppedAnimation<Color>(Colors.grey),
                        ),
                      );
                    case ConnectionState.done:
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Error: ${snapshot.error}'),
                        );
                      }
                      if (_readTimer != null && _readTimer!.isActive) {
                        _readTimer!.cancel();
                      }
                      _readTimer = Timer(
                          Duration(milliseconds: 200), _onReadTimerTimeout);
                      final messages = snapshot.data ?? [];
                      this._messageController =
                          ChatMessageController(messages: messages);
                      final Map<String, ChatUser> users = {};
                      this._chat.users.forEach((u) => users[u.username] = u);
                      return ChatList(
                        controller: this._messageController,
                        users: users,
                        showName: this._chat.type == ChatType.GROUP,
                        onTab: (ChatMessage msg) {
                          if (this._selectedMessges.value.length > 0) {
                            this._selectOrRemove(msg);
                          }
                        },
                        onLongPress: _selectOrRemove,
                      );
                  }
                }),
          ),
          ...this._hasSendPermission()
              ? [
                  MessageInputWidget(sendMessage: (String text) async {
                    final msg = TextMessage.chatMessage(this._chat.id,
                        this._currentUser.username, text, MessageType.TEXT);
                    msg.sender = this._currentUser;
                    await ChatService.sendMessage(msg, this._chat);
                    this._messageController.add(msg);
                  })
                ]
              : [],
        ],
      ),
    );
  }

  Widget _getTitle(BuildContext context) {
    return ValueListenableBuilder<Iterable<String>>(
      valueListenable: this._selectedMessges,
      builder: (BuildContext context, Iterable<String> selectedMessages,
          Widget? child) {
        var subtitle = this._getSubTitle();
        var titleWidgets = <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Text(
              this._selectedMessges.value.isNotEmpty
                  ? _selectedMessges.value.length.toString() + " selected"
                  : _chat.title,
              style: TextStyle(
                fontSize: 18.0,
                color: Colors.white,
              ),
            ),
          ),
        ];
        if (this._selectedMessges.value.isEmpty && subtitle.isNotEmpty) {
          titleWidgets.add(
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.60,
              child: Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12.0,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: titleWidgets,
        );
      },
    );
  }

  String _getSubTitle() {
    if (this._chat.type == ChatType.GROUP) {
      return this._chat.users.map((u) => u.name).join(", ");
    }
    return this
        ._chat
        .users
        .firstWhere(
          (u) => this._currentUser != u,
          orElse: () => ChatUser("", "", null),
        )
        .username;
  }

  void _selectOrRemove(ChatMessage msg) {
    if (!_selectedMessges.value.remove(msg.id)) {
      _selectedMessges.value.add(msg.id);
    }
    msg.isSelected = !msg.isSelected;
    this._messageController.update(msg);
    this._selectedMessges.update();
  }

  List<Widget> _getActions() {
    Widget child = ValueListenableBuilder(
      valueListenable: this._selectedMessges,
      builder: (context, key, child) {
        List<Widget> actions = [];
        if (this._selectedMessges.value.isNotEmpty) {
          actions.add(IconButton(
            icon: Icon(Icons.clear),
            onPressed: () {
              List<ChatMessage> msgs = [];
              this._selectedMessges.value.forEach((id) {
                final notifier =
                    this._messageController.messageChangeNotifier[id];
                if (notifier != null) {
                  notifier.value.isSelected = false;
                  msgs.add(notifier.value);
                }
              });
              this._messageController.updateAll(msgs);
              this._selectedMessges.value.clear();
              this._selectedMessges.update();
            },
          ));
          actions.add(IconButton(
            icon: Icon(Icons.delete),
            onPressed: () async {
              await ChatService.deleteMessages(
                  this._selectedMessges.value.toList());
              this._messageController.deleteAll(this._selectedMessges.value);
              this._selectedMessges.value.clear();
              this._selectedMessges.update();
            },
          ));
        }
        actions.add(PopupMenuButton(itemBuilder: (BuildContext context) => []));
        return Row(children: actions);
      },
    );
    return [child];
  }

  void _onNotification(RemoteMessage msg) async {
    final msgInfo = msg.head;
    if (msgInfo.action == "state") {
      StateMessge state = toChatMessage(msg) as StateMessge;
      state.msgIds.forEach((id) {
        final notifier = this._messageController.messageChangeNotifier[id];
        if (notifier != null) {
          final message = notifier.value;
          if (message.updateState(state.state))
            this._messageController.update(message);
        }
      });
    } else if (msgInfo.type == ChatType.GROUP) {
      var users = await ChatService.getChatUserByid(this._chat.id);
      setState(() {
        this._chat.resetUsers();
        users.forEach((u) => this._chat.addUser(u));
      });
    }
  }

  void _onNewMessage(RemoteMessage msg) {
    final message = toChatMessage(msg);
    this._unreadMessages.add(message);
    this._messageController.add(message);
    if (_readTimer == null || !_readTimer!.isActive) {
      _readTimer = Timer(Duration(milliseconds: 100), _onReadTimerTimeout);
    }
  }

  _onReadTimerTimeout() {
    if (_unreadMessages.isEmpty) return;
    final unreadMessages = _unreadMessages.toList();
    _unreadMessages = Set<ChatMessage>();
    final future = ChatService.markAsRead(unreadMessages, this._chat);
    unawaited(future);
    if (_unreadMessages.isNotEmpty && _readTimer == null ||
        !_readTimer!.isActive) {
      _readTimer = Timer(Duration(milliseconds: 100), _onReadTimerTimeout);
    }
  }

  bool _hasSendPermission() {
    return this._chat.users.contains(this._currentUser);
  }

  @override
  void dispose() {
    WidgetsBinding.instance!.removeObserver(this);
    if (_readTimer != null) _readTimer!.cancel();
    _notificationSub.cancel();
    _newMessageSub.cancel();
    this._messageController.dispose();
    super.dispose();
  }
}
