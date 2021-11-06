import 'dart:async';

import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/dateHeader.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/messageSpacer.dart';
import 'package:vartalap/models/remoteMessage.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/screens/chat/chat_info.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/socket_service.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/chat_message_helper.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap/widgets/avator.dart';
import 'message.dart';
import 'message_input.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  ChatScreen(this.chat) : super(key: Key(chat.id));

  @override
  ChatState createState() => ChatState(
        chat,
      );
}

class ChatState extends State<ChatScreen> {
  Chat _chat;
  late User _currentUser;
  late Future<List<TextMessage>> _fMessages;
  late List<TextMessage> _messages;
  late List<Object> _displayMessages;
  List<String> _selectedMessges = [];
  late StreamSubscription _notificationSub;
  late StreamSubscription _newMessageSub;
  Timer? _readTimer;
  List<String> _unreadMessages = [];
  Map<String, User> _users = Map();
  Map<String, UserNotifier> _userChangeNotifier = Map();

  ChatState(this._chat);
  @override
  void initState() {
    super.initState();
    this._chat.users.forEach((u) => _users[u.username] = u);
    this._fMessages = ChatService.getChatMessages(this._chat.id);
    _notificationSub = ChatService.onNotificationMessagStream.where((msg) {
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
    _notificationSub.resume();
    _newMessageSub = ChatService.onNewMessageStream
        .where((msg) => msg.head.chatid == this._chat.id)
        .listen(_onNewMessage, cancelOnError: false);
  }

  @override
  Widget build(BuildContext context) {
    this._currentUser = CurrentUser.of(context).user!;
    var subtitle = this.getSubTitle();
    var titleWidgets = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: Text(
          this._selectedMessges.length > 0
              ? _selectedMessges.length.toString() + " selected"
              : _chat.title,
          style: TextStyle(
            fontSize: 18.0,
            color: Colors.white,
          ),
        ),
      ),
    ];
    if (this._selectedMessges.length == 0 && subtitle.length > 0) {
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
                  this.hasSendPermission()) {
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
              children: <Widget>[
                Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: titleWidgets,
                ),
              ],
            ),
          ),
        ),
        actions: this.getActions(),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Flexible(
            flex: 1,
            child: FutureBuilder<List<TextMessage>>(
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
                      _readTimer =
                          Timer(Duration(seconds: 1), _onReadTimerTimeout);
                      this._messages = snapshot.data ?? [];
                      this._displayMessages = calculateChatMessages(
                        this._messages,
                        _currentUser,
                        showUserNames: this._chat.type == ChatType.GROUP,
                      )[0] as List<Object>;
                      return ListView.builder(
                          itemCount: this._displayMessages.length,
                          reverse: true,
                          itemBuilder: (context, i) {
                            return _messageBuilder(this._displayMessages[i]);
                          });
                  }
                }),
          ),
          ...this.hasSendPermission()
              ? [
                  MessageInputWidget(sendMessage: (String text) async {
                    var msg = TextMessage.chatMessage(this._chat.id,
                        this._currentUser.username, text, MessageType.TEXT);
                    msg.sender = this._currentUser;
                    await ChatService.sendMessage(msg, this._chat);
                    setState(() {
                      _messages.insert(0, msg);
                    });
                  })
                ]
              : [],
        ],
      ),
    );
  }

  Widget _messageBuilder(Object object) {
    if (object is DateHeader) {
      return Container(
        alignment: Alignment.center,
        margin: const EdgeInsets.only(
          bottom: 32,
          top: 16,
        ),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: VartalapTheme.theme.receiverColor,
            borderRadius: BorderRadius.all(
              Radius.circular(5),
            ),
          ),
          child: Text(
            object.date,
            //style: widget.theme.dateDividerTextStyle,
          ),
        ),
      );
    } else if (object is MessageSpacer) {
      return SizedBox(
        height: object.height,
      );
    } else if (object is Map) {
      TextMessage _msg = object["message"];
      if (_msg.sender == null) {
        _msg.sender = getSender(_msg);
      }
      bool isYou = _msg.sender == this._currentUser;
      bool showUserInfo = !isYou && this._chat.type == ChatType.GROUP;

      Widget child;

      if (this._userChangeNotifier.containsKey(_msg.senderId)) {
        child = ValueListenableBuilder<User>(
          builder: (context, key, child) {
            return MessageWidget(
              _msg,
              isYou,
              showUserInfo: showUserInfo,
              isSelected: this._selectedMessges.contains(_msg.id),
              onTab: (TextMessage msg) {
                if (this._selectedMessges.length > 0) {
                  this.selectOrRemove(msg);
                }
              },
              onLongPress: selectOrRemove,
            );
          },
          valueListenable: this._userChangeNotifier[_msg.senderId]!,
        );
      } else {
        child = MessageWidget(
          _msg,
          isYou,
          showUserInfo: showUserInfo,
          isSelected: this._selectedMessges.contains(_msg.id),
          onTab: (TextMessage msg) {
            if (this._selectedMessges.length > 0) {
              this.selectOrRemove(msg);
            }
          },
          onLongPress: selectOrRemove,
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 5.0),
        child: child,
      );
    }
    return const SizedBox();
  }

  String getSubTitle() {
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

  void selectOrRemove(TextMessage msg) {
    setState(() {
      if (!_selectedMessges.remove(msg.id)) {
        _selectedMessges.add(msg.id);
      }
    });
  }

  List<Widget> getActions() {
    List<Widget> actions = [];
    if (this._selectedMessges.length > 0) {
      actions.add(IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          setState(() {
            this._selectedMessges = [];
          });
        },
      ));
      actions.add(IconButton(
        icon: Icon(Icons.delete),
        onPressed: () async {
          await ChatService.deleteMessages(this._selectedMessges);
          setState(() {
            this
                ._messages
                .removeWhere((msg) => this._selectedMessges.contains(msg));
            this._selectedMessges = [];
          });
        },
      ));
    }
    actions.add(PopupMenuButton(itemBuilder: (BuildContext context) => []));
    return actions;
  }

  void _onNotification(RemoteMessage msg) async {
    final msgInfo = msg.head;
    if (msgInfo.from == SocketService.name) {
      setState(() {
        this._messages = this._messages.map<TextMessage>((_msg) {
          if (_msg.id == msg.body["id"]) {
            _msg.updateState(msg.body["state"]);
          }
          return _msg;
        }).toList();
      });
    } else if (msgInfo.action == "state") {
      StateMessge state = toChatMessage(msg) as StateMessge;
      setState(() {
        this._messages = this._messages.map<TextMessage>((msg) {
          if (state.msgIds.contains(msg.id)) {
            msg.updateState(state.state);
          }
          return msg;
        }).toList();
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
    TextMessage message = toChatMessage(msg) as TextMessage;

    setState(() {
      this._unreadMessages.add(message.id);
      this._messages.insert(0, message);
    });
    if (_readTimer == null || !_readTimer!.isActive) {
      _readTimer = Timer(Duration(seconds: 1), _onReadTimerTimeout);
    }
  }

  Future _onReadTimerTimeout() async {
    var messages = this
        ._messages
        .where((msg) => (msg.senderId != this._currentUser.username &&
            (msg.state == MessageState.NEW ||
                msg.state == MessageState.DELIVERED)))
        .map((e) => e.id)
        .toList();
    if (_unreadMessages.length > 0) {
      messages.addAll(_unreadMessages.map((e) => e));
      _unreadMessages = [];
    }
    if (messages.length == 0) return;
    await ChatService.markAsRead(messages, this._chat);
    setState(() {
      this._messages = this._messages.map((msg) {
        if (messages.contains(msg.id)) {
          msg.updateState(MessageState.READ);
        }
        return msg;
      }).toList();
    });
  }

  User getSender(TextMessage msg) {
    if (this._users.containsKey(msg.senderId)) {
      return this._users[msg.senderId]!;
    } else {
      var user = ChatUser(msg.senderId, msg.senderId, null);
      if (!this._userChangeNotifier.containsKey(msg.senderId)) {
        this._userChangeNotifier[msg.senderId] = UserNotifier(user);
      }
      UserService.getUserById(msg.senderId).then((User? user) {
        if (user == null) return;
        this._users[user.username] = user;
        msg.sender = user;
        this._userChangeNotifier[msg.senderId]!.update(user);
      }, onError: (user) {});
      return user;
    }
  }

  bool hasSendPermission() {
    return this._chat.users.contains(this._currentUser);
  }

  @override
  void dispose() {
    if (_readTimer != null) _readTimer!.cancel();
    _notificationSub.cancel();
    _newMessageSub.cancel();
    super.dispose();
  }
}
