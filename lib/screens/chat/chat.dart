import 'dart:async';

import 'package:vartalap/screens/chat/chat_info.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/chatlist.dart';
import 'package:vartalap/widgets/notifier/iterable_notifier.dart';
import 'package:vartalap/widgets/message_input.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ChatScreen extends StatefulWidget {
  final ChatClient chat;
  ChatScreen(this.chat) : super(key: Key(chat.channel.id.toString()));

  @override
  ChatState createState() => ChatState(chat);
}

class ChatState extends State<ChatScreen> with WidgetsBindingObserver {
  final ChatClient chat;
  ChatMessageController _messageController =
      new ChatMessageController(messages: []);
  final _selectedMessges = SetNotifier<int>(Set<int>());
  StreamSubscription? _notificationSub;
  StreamSubscription? _newMessageSub;
  Timer? _readTimer;
  Timer? _myTypingTimer;
  Timer? _remoteTypingTimer;
  var _typing = ValueNotifier<bool>(false);
  Set<ChatMessage> _unreadMessages = Set<ChatMessage>();

  ChatState(this.chat);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    chat.watch();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // These are the callbacks
    switch (state) {
      case AppLifecycleState.resumed:
        this._newMessageSub?.resume();
        this._notificationSub?.resume();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                text: chat.displayName,
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
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChatInfo(this.chat),
                ),
              );
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
            child: StreamBuilder<List<ChatMessage>>(
                stream: chat.messagesStream,
                builder: (context, snapshot) {
                  switch (snapshot.connectionState) {
                    case ConnectionState.none:
                      return Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              new AlwaysStoppedAnimation<Color>(Colors.grey),
                        ),
                      );
                    case ConnectionState.waiting:
                      return Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              new AlwaysStoppedAnimation<Color>(Colors.grey),
                        ),
                      );
                    case ConnectionState.active:
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
                      final Map<String, Member> members = {};
                      return ChatList(
                        controller: this._messageController,
                        members: members,
                        showName: this.chat.channel.type == ChannelType.group,
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
          ...this.chat.hasSendMessagePermission()
              ? [
                  MessageInputWidget(
                    sendMessage: (String text) async {
                      final msg = TextMessage(
                        senderId: chat.currentUser.id,
                        payload: {
                          "text": text,
                        },
                        sender: chat.currentUser,
                      );

                      await chat.sendMessage([msg]);
                      this._messageController.add(msg);
                    },
                    onTyping: (bool state) async {
                      if (state) {
                        if (!(_myTypingTimer?.isActive ?? false)) {
                          // ChatService.sendSystemMessage(
                          //     TypingMessage(
                          //       this._channel.id,
                          //       this._currentUser.username,
                          //       true,
                          //     ),
                          //     this._channel);
                          _myTypingTimer = Timer.periodic(Duration(seconds: 2),
                              (Timer timer) {
                            // ChatService.sendSystemMessage(
                            //     TypingMessage(
                            //       this._channel.id,
                            //       this._currentUser.username,
                            //       true,
                            //     ),
                            //     this._channel);
                          });
                        }
                      } else {
                        // await ChatService.sendSystemMessage(
                        //     TypingMessage(
                        //       this._channel.id,
                        //       this._currentUser.username,
                        //       false,
                        //     ),
                        //     this._channel);
                        if (_myTypingTimer?.isActive ?? false)
                          _myTypingTimer!.cancel();
                        _myTypingTimer = null;
                      }
                    },
                  )
                ]
              : [],
        ],
      ),
    );
  }

  Widget _getTitle(BuildContext context) {
    return ValueListenableBuilder<Iterable<int>>(
      valueListenable: this._selectedMessges,
      builder: (BuildContext context, Iterable<int> selectedMessages,
          Widget? child) {
        final subtitle = this._getSubTitle();
        final titleWidgets = <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Text(
              this._selectedMessges.value.isNotEmpty
                  ? _selectedMessges.value.length.toString() + " selected"
                  : chat.displayName,
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
                child: ValueListenableBuilder<bool>(
                  valueListenable: _typing,
                  builder: (BuildContext context, bool state, Widget? child) {
                    var _value = subtitle;
                    if (state) {
                      _value = "typing...";
                    }
                    return Text(
                      _value,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12.0,
                        color: Colors.white,
                      ),
                    );
                  },
                )),
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
    return this.chat.displayName;
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

  _onReadTimerTimeout() {
    if (_unreadMessages.isEmpty) return;
    // final unreadMessages = _unreadMessages.toList();
    _unreadMessages = Set<ChatMessage>();
    // final future = client.markAsRead(unreadMessages, this._channel);
    // unawaited(future);
    if (_unreadMessages.isNotEmpty && _readTimer == null ||
        !_readTimer!.isActive) {
      _readTimer = Timer(Duration(milliseconds: 100), _onReadTimerTimeout);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_readTimer?.isActive ?? false) _readTimer!.cancel();
    if (_myTypingTimer?.isActive ?? false) _myTypingTimer!.cancel();
    if (_remoteTypingTimer?.isActive ?? false) _remoteTypingTimer!.cancel();
    _notificationSub?.cancel();
    _newMessageSub?.cancel();
    this._messageController.dispose();
    super.dispose();
  }
}
