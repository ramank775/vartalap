import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/message.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/screens/profile_img/profile_img.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
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
  ChatState(this._chat);
  @override
  void initState() {
    super.initState();
    this._fMessages = ChatService.getChatMessage(this._chat.id);
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
              new ProfileImg(this._chat.pic ?? 'assets/images/default-user.png',
                  ProfileImgSize.SM),
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
                        _chat.title,
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
                      this._messages = snapshot.data;
                      return ListView.builder(
                          itemCount: this._messages.length,
                          reverse: true,
                          itemBuilder: (context, i) {
                            return MessageWidget(
                              this._messages[i],
                              this._messages[i].sender ==
                                  this.widget.currentUser,
                            );
                          });
                  }
                  return null; //
                }),
          ),
          new MessageInputWidget(sendMessage: (String text) async {
            print("Text: $text");
            var msg = Message.chatMessage(this._chat.id,
                this.widget.currentUser.username, text, MessageType.TEXT);
            msg.sender = this.widget.currentUser;
            var msgText = msg.text;
            print("Message text: $msgText");
            await ChatService.sendMessage(msg, this._chat);
            setState(() {
              _messages.insert(0, msg);
            });
          }),
        ],
      ),
    );
  }
}
