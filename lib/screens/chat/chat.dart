import 'dart:async';

import 'package:vartalap/models/chat.dart';
import 'package:vartalap/screens/chat/chat_info.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/utils/chat_message_helper.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/chatlist.dart';
import 'package:vartalap/widgets/notifier/iterable_notifier.dart';
import 'package:vartalap/widgets/message_input.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ChatScreen extends StatefulWidget {
  final Channel channel;
  ChatScreen(this.channel) : super(key: Key(channel.id.toString()));

  @override
  ChatState createState() => ChatState(channel);
}

class ChatState extends State<ChatScreen> with WidgetsBindingObserver {
  Channel _channel;
  late Contact _currentUser;
  late VartalapChatClientFlutter client =
      VartalapClientProvider.of(context).client;
  late Stream<List<ChatMessage>> _fMessages;
  ChatMessageController _messageController =
      new ChatMessageController(messages: []);
  final _selectedMessges = SetNotifier<String>(Set<String>());
  StreamSubscription? _notificationSub;
  StreamSubscription? _newMessageSub;
  Timer? _readTimer;
  Timer? _myTypingTimer;
  Timer? _remoteTypingTimer;
  var _typing = ValueNotifier<bool>(false);
  Set<ChatMessage> _unreadMessages = Set<ChatMessage>();

  ChatState(this._channel);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    this._fMessages = this.client.getMessages(this._channel.id).watch();
    this._fMessages.listen((messages) {
      final unread = messages.where((msg) =>
          (msg.senderId != this._currentUser.username &&
              (msg.state == MessageState.pending ||
                  msg.state == MessageState.delivered)));
      _unreadMessages.addAll(unread);
    });
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
                text: this._channel.displayName,
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
              if (this._channel.type == ChannelType.group &&
                  this._hasSendPermission()) {
                Channel? result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ChatInfo(this._channel),
                  ),
                );
                if (result != null) {
                  setState(() {
                    this._channel = result;
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
            child: StreamBuilder<List<ChatMessage>>(
                stream: _fMessages,
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
                      final Map<String, Member> members = {};
                      return ChatList(
                        controller: this._messageController,
                        members: members,
                        showName: this._channel.type == ChannelType.group,
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
                  MessageInputWidget(
                    sendMessage: (String text) async {
                      final msg = TextMessage.chatMessage(this._channel.id,
                          this._currentUser.username, text, MessageType.TEXT);
                      msg.sender = this._currentUser;
                      await ChatService.sendMessage(msg, this._channel);
                      this._messageController.add(msg);
                    },
                    onTyping: (bool state) async {
                      if (state) {
                        if (!(_myTypingTimer?.isActive ?? false)) {
                          ChatService.sendSystemMessage(
                              TypingMessage(
                                this._channel.id,
                                this._currentUser.username,
                                true,
                              ),
                              this._channel);
                          _myTypingTimer = Timer.periodic(Duration(seconds: 2),
                              (Timer timer) {
                            ChatService.sendSystemMessage(
                                TypingMessage(
                                  this._channel.id,
                                  this._currentUser.username,
                                  true,
                                ),
                                this._channel);
                          });
                        }
                      } else {
                        await ChatService.sendSystemMessage(
                            TypingMessage(
                              this._channel.id,
                              this._currentUser.username,
                              false,
                            ),
                            this._channel);
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
    return ValueListenableBuilder<Iterable<String>>(
      valueListenable: this._selectedMessges,
      builder: (BuildContext context, Iterable<String> selectedMessages,
          Widget? child) {
        final subtitle = this._getSubTitle();
        final titleWidgets = <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Text(
              this._selectedMessges.value.isNotEmpty
                  ? _selectedMessges.value.length.toString() + " selected"
                  : _channel.displayName,
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
    if (this._channel.type == ChannelType.group) {
      return this._channel.members.map((u) => u.user.displayName).join(", ");
    }
    return this
        ._channel
        .members
        .firstWhere(
          (u) => this._currentUser != u,
          orElse: () => Member(
            user: Contact(username: '', status: ContactStatus.other),
            role: 'member',
            since: DateTime.now(),
          ),
        )
        .user
        .displayName;
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
    } else if (msgInfo.type == ChannelType.group) {
      // Handle group member change notification
    } else if (msgInfo.action == "typing") {
      TypingMessage typingMsg = toChatMessage(msg) as TypingMessage;
      if (_remoteTypingTimer?.isActive ?? false) _remoteTypingTimer!.cancel();
      this._typing.value = typingMsg.isTyping;
      if (typingMsg.isTyping) {
        _remoteTypingTimer = Timer(Duration(seconds: 5), () {
          this._typing.value = false;
        });
      }
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
    final future = ChatService.markAsRead(unreadMessages, this._channel);
    unawaited(future);
    if (_unreadMessages.isNotEmpty && _readTimer == null ||
        !_readTimer!.isActive) {
      _readTimer = Timer(Duration(milliseconds: 100), _onReadTimerTimeout);
    }
  }

  bool _hasSendPermission() {
    return this
        ._channel
        .members
        .any((u) => u.user.username == this._currentUser.username);
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
