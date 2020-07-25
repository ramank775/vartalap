import 'package:chat_flutter_app/screens/profile_img/profile_img.dart';
import 'package:flutter/material.dart';
import 'message.dart';
import 'message_input.dart';

class Chat extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
              new ProfileImg('images/default-user.png', ProfileImgSize.SM),
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
                        "Raman Kumar", // _chat == null ? '' : _chat.name,
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
        // actions: <Widget>[
        //   Builder(
        //     builder: (BuildContext context) {
        //       return IconButton(
        //         icon: Icon(Icons.videocam),
        //         onPressed: () {
        //           Scaffold.of(context).showSnackBar(
        //               SnackBar(content: Text('Video Call Button tapped')));
        //         },
        //       );
        //     },
        //   ),
        //   Builder(
        //     builder: (BuildContext context) {
        //       return IconButton(
        //         icon: Icon(Icons.call),
        //         onPressed: () {
        //           Scaffold.of(context).showSnackBar(
        //               SnackBar(content: Text('Call Button tapped')));
        //         },
        //       );
        //     },
        //   ),
        //   PopupMenuButton<ChatDetailMenuOptions>(
        //     tooltip: "More options",
        //     onSelected: _onSelectMenuOption,
        //     itemBuilder: (BuildContext context) {
        //       return [
        //         PopupMenuItem<ChatDetailMenuOptions>(
        //           child: Text("View contact"),
        //           value: ChatDetailMenuOptions.viewContact,
        //         ),
        //         PopupMenuItem<ChatDetailMenuOptions>(
        //           child: Text("Media"),
        //           value: ChatDetailMenuOptions.media,
        //         ),
        //         PopupMenuItem<ChatDetailMenuOptions>(
        //           child: Text("Search"),
        //           value: ChatDetailMenuOptions.search,
        //         ),
        //         PopupMenuItem<ChatDetailMenuOptions>(
        //           child: Text("Mute notifications"),
        //           value: ChatDetailMenuOptions.muteNotifications,
        //         ),
        //         PopupMenuItem<ChatDetailMenuOptions>(
        //           child: Text("Wallpaper"),
        //           value: ChatDetailMenuOptions.wallpaper,
        //         ),
        //         PopupMenuItem<ChatDetailMenuOptions>(
        //           child: ListTile(
        //             contentPadding: const EdgeInsets.all(0.0),
        //             title: Text("More"),
        //             trailing: Icon(Icons.arrow_right),
        //           ),
        //           value: ChatDetailMenuOptions.more,
        //         ),
        //       ];
        //     },
        //   ),
        // ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Flexible(
            flex: 1,
            child: FutureBuilder(
                future: null,
                builder: (context, snapshot) {
                  // switch (snapshot.connectionState) {
                  //   case ConnectionState.none:
                  //     return Center(
                  //       child: CircularProgressIndicator(
                  //         valueColor:
                  //             new AlwaysStoppedAnimation<Color>(Colors.grey),
                  //       ),
                  //     );
                  //   case ConnectionState.active:
                  //   case ConnectionState.waiting:
                  //     return Center(
                  //       child: CircularProgressIndicator(
                  //         valueColor:
                  //             new AlwaysStoppedAnimation<Color>(Colors.grey),
                  //       ),
                  //     );
                  //   case ConnectionState.done:
                  //     if (snapshot.hasError) {
                  //       return Center(
                  //         child: Text('Error: ${snapshot.error}'),
                  //       );
                  //     }
                  //     return ListView.builder(
                  //         reverse: true,
                  //         itemCount: 10,
                  //         itemBuilder: (context, i) {
                  //           return Message(
                  //             content: 'messages[i].content',
                  //             timestamp: DateTime.now(),
                  //             isYou: i % 2 == 0,
                  //             isRead: i % 2 == 0,
                  //             isSent: i % 2 == 0,
                  //             fontSize: 14.0,
                  //           );
                  //         });
                  // }
                  // return null; //
                  return ListView.builder(
                      reverse: true,
                      itemCount: 10,
                      itemBuilder: (context, i) {
                        return Message(
                          content:
                              'This is a test message the best chat message every asdjfl;askjf;alskjdfa;lfjalfj',
                          timestamp: DateTime.now(),
                          isYou: i % 2 == 0,
                          isRead: i % 2 == 0,
                          isSent: i % 2 == 0,
                          fontSize: 14.0,
                        );
                      });
                }),
          ),
          new MessageInput(),
        ],
      ),
    );
  }
}
