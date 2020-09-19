import 'package:vartalap/models/chat.dart';
import 'package:vartalap/screens/chats/chat_preview.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:flutter/material.dart';

class Chats extends StatefulWidget {
  @override
  ChatsState createState() => ChatsState();
}

class ChatsState extends State<Chats> {
  Future<List<ChatPreview>> _fChats;
  List<ChatPreview> _selectedChats = [];
  @override
  void initState() {
    super.initState();
    this._fChats = ChatService.getChats();
    this._selectedChats = [];
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: AppBar(
        title: new Text('Vartalap'),
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
            var data = snapshot.data;
            return ListView.builder(
              itemCount: data.length,
              itemBuilder: (context, i) => new ChatPreviewWidget(
                data[i],
                (Chat chat) async {
                  if (this._selectedChats.length > 0) {
                    this.selectOrRemove(chat);
                    return;
                  }
                  if (chat.users.length == 0) {
                    var _users = await ChatService.getChatUserByid(chat.id);
                    _users.forEach((u) {
                      chat.addUser(u);
                    });
                  }
                  navigate(context, '/chat', data: chat);
                },
                this.selectOrRemove,
                isSelected: _selectedChats.contains(data[i]),
              ),
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

  void selectOrRemove(Chat chat) {
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
        icon: Icon(Icons.clear),
        onPressed: () {
          setState(() {
            this._selectedChats = [];
          });
        },
      ));
      actions.add(IconButton(
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
    actions.add(PopupMenuButton(itemBuilder: (BuildContext context) => []));
    return actions;
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
