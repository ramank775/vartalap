import 'dart:async';

import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/socketMessage.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/socket_service.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/widgets/avator.dart';
import 'message.dart';
import 'message_input.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  final User currentUser = UserService.getLoggedInUser();
  ChatScreen(this.chat) : super(key: Key(chat.id));

  @override
  ChatState createState() => ChatState(chat);
}

class ChatState extends State<ChatScreen> {
  final Chat _chat;
  Future<List<Message>> _fMessages;
  List<Message> _messages;
  List<Message> _selectedMessges = [];
  StreamSubscription _notificationSub;
  StreamSubscription _newMessageSub;
  Timer _readTimer;
  List<Message> _unreadMessages = [];

  ChatState(this._chat);
  @override
  void initState() {
    super.initState();
    this._fMessages = ChatService.getChatMessages(this._chat.id);
    _notificationSub = ChatService.onNotificationMessagStream
        .where((msg) => msg.chatId == this._chat.id)
        .listen(_onNotification);
    _newMessageSub = ChatService.onNewMessageStream
        .where((msg) => msg.chatId == this._chat.id)
        .listen(_onNewMessage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: chatDetailScaffoldBgColor,
      appBar: AppBar(
        leading: FlatButton(
          shape: CircleBorder(),
          padding: const EdgeInsets.only(left: 1.0),
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
                width: 32.0,
                height: 32.0,
              )
              // new ProfileImg(this._chat.pic ?? 'assets/images/default-user.png',
              //     ProfileImgSize.SM),
            ],
          ),
        ),
        title: Material(
          color: Colors.white.withOpacity(0.0),
          child: InkWell(
            // highlightColor: highlightColor,
            // splashColor: secondaryColor,
            onTap: () {
              // Application.router.navigateTo(
              //   context,
              //   //"/profile?id=${_chat.id}",
              //   Routes.futureTodo,
              //   transition: TransitionType.inFromRight,
              // );
            },
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                Column(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Text(
                        this._selectedMessges.length > 0
                            ? _selectedMessges.length.toString() + " selected"
                            : _chat.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18.0,
                        ),
                      ),
                    ),
                  ],
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
            child: FutureBuilder<List<Message>>(
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
                      if (_readTimer != null && _readTimer.isActive) {
                        _readTimer.cancel();
                      }
                      _readTimer =
                          Timer(Duration(seconds: 1), _onReadTimerTimeout);
                      this._messages = snapshot.data;
                      return ListView.builder(
                          itemCount: this._messages.length,
                          reverse: true,
                          itemBuilder: (context, i) {
                            if (this._messages[i].sender == null) {
                              this._messages[i].sender =
                                  getSender(this._messages[i].senderId);
                            }
                            bool isYou = this._messages[i].sender ==
                                this.widget.currentUser;
                            bool showUserInfo =
                                !isYou && this._chat.type == ChatType.GROUP;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 5.0),
                              child: MessageWidget(
                                this._messages[i],
                                isYou,
                                showUserInfo: showUserInfo,
                                isSelected: this
                                    ._selectedMessges
                                    .contains(this._messages[i]),
                                onTab: (Message msg) {
                                  if (this._selectedMessges.length > 0) {
                                    this.selectOrRemove(msg);
                                  }
                                },
                                onLongPress: selectOrRemove,
                              ),
                            );
                          });
                  }
                  return null; //
                }),
          ),
          new MessageInputWidget(sendMessage: (String text) async {
            var msg = Message.chatMessage(this._chat.id,
                this.widget.currentUser.username, text, MessageType.TEXT);
            msg.sender = this.widget.currentUser;
            await ChatService.sendMessage(msg, this._chat);
            setState(() {
              _messages.insert(0, msg);
            });
          }),
        ],
      ),
    );
  }

  void selectOrRemove(Message msg) {
    setState(() {
      if (!_selectedMessges.remove(msg)) {
        _selectedMessges.add(msg);
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

  void _onNotification(SocketMessage msg) {
    if (msg.from == SocketService.name) {
      setState(() {
        this._messages = this._messages.map<Message>((_msg) {
          if (_msg.id == msg.msgId) {
            _msg.updateState(msg.state);
          }
          return _msg;
        }).toList();
      });
    }
  }

  void _onNewMessage(SocketMessage msg) {
    var message = msg.toMessage();

    setState(() {
      this._unreadMessages.add(message);
      this._messages.insert(0, message);
    });
    if (_readTimer != null && !_readTimer.isActive) {
      _readTimer = Timer(Duration(seconds: 1), _onReadTimerTimeout);
    }
  }

  void _onReadTimerTimeout() {
    var messages = this
        ._messages
        .where((msg) => (msg.senderId != this.widget.currentUser.username &&
            msg.state == MessageState.NEW))
        .map((e) => e.id)
        .toList();
    if (_unreadMessages.length > 0) {
      messages.addAll(_unreadMessages.map((e) => e.id));
      _unreadMessages = [];
    }
    ChatService.markAsDelivered(messages);
  }

  User getSender(String senderId) {
    return this._chat.users.singleWhere((u) => u.username == senderId,
        orElse: () => ChatUser(senderId, senderId, null));
  }

  @override
  void dispose() {
    _readTimer.cancel();
    _notificationSub.cancel();
    _newMessageSub.cancel();
    super.dispose();
  }
}
