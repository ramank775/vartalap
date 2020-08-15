import 'package:chat_flutter_app/models/chat.dart';
import 'package:chat_flutter_app/screens/chats/chat_preview.dart';
import 'package:chat_flutter_app/services/chat_service.dart';
import 'package:flutter/material.dart';

class Chats extends StatefulWidget {
  @override
  ChatsState createState() => ChatsState();
}

class ChatsState extends State<Chats> {
  Future<List<ChatPreview>> _fChats;
  @override
  void initState() {
    super.initState();
    this._fChats = ChatService.getChats();
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: AppBar(
        title: new Text('Chat App'),
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
            var data = snapshot.data;
            return ListView.builder(
              itemCount: data.length,
              itemBuilder: (context, i) =>
                  new ChatPreviewWidget(data[i], (Chat chat) {
                navigate(context, '/chat', data: chat);
              }),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => navigate(context, '/new-chat'),
        tooltip: 'New',
        child: Icon(Icons.add),
      ),
    );
  }

  Future<void> navigate(BuildContext context, String screen,
      {Object data}) async {
    var result = await Navigator.pushNamed(context, screen, arguments: data);
    if (screen == "/new-chat") {
      if (result == null) {
        return;
      }
      var chat = await ChatService.newIndiviualChat(result);
      await Navigator.of(context).pushNamed('/chat', arguments: chat);
    }
    print("Main Screen");
    setState(() {
      _fChats = ChatService.getChats();
    });
  }
}
