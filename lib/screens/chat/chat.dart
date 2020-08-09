import 'package:chat_flutter_app/models/chat.dart';
import 'package:chat_flutter_app/models/message.dart';
import 'package:chat_flutter_app/models/user.dart';
import 'package:chat_flutter_app/screens/profile_img/profile_img.dart';
import 'package:chat_flutter_app/services/chat_service.dart';
import 'package:chat_flutter_app/services/user_service.dart';
import 'package:flutter/material.dart';
import 'message.dart';
import 'message_input.dart';

class ChatScreen extends StatelessWidget {
  final Chat _chat;
  final User _currentUser = UserService.getLoggedInUser();
  ChatScreen(this._chat, {Key key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    var messages = ChatService.getChatMessage(this._chat.id);
    return Scaffold(
      // backgroundColor: chatDetailScaffoldBgColor,
      appBar: AppBar(
        leading: FlatButton(
          shape: CircleBorder(),
          padding: const EdgeInsets.only(left: 1.0),
          onPressed: () {
            Navigator.of(context).pop();
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
                future: messages,
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
                      var msgs = snapshot.data;
                      return ListView.builder(
                          itemCount: msgs.length,
                          itemBuilder: (context, i) {
                            return MessageWidget(
                                msgs[i], msgs[i].sender == this._currentUser);
                          });
                  }
                  return null; //
                }),
          ),
          new MessageInputWidget(sendMessage: (String text) async {
            print("Text: $text");
            var msg = Message.chatMessage(this._chat.id,
                this._currentUser.username, text, MessageType.TEXT);
            var msgText = msg.text;
            print("Message text: $msgText");
            await ChatService.sendMessage(msg, this._chat);
          }),
        ],
      ),
    );
  }
}
