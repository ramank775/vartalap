import 'package:chat_flutter_app/models/chat.dart';
import 'package:chat_flutter_app/screens/chats/chat_preview.dart';
import 'package:chat_flutter_app/services/chat_service.dart';
import 'package:flutter/material.dart';

class Chats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var chats = ChatService.getChats();
    return new Scaffold(
      appBar: AppBar(
        title: new Text('Chat App'),
      ),
      body: new Container(
        padding: EdgeInsets.fromLTRB(5, 5, 5, 0),
        child: FutureBuilder<List<Chat>>(
          future: chats,
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
              itemBuilder: (context, i) => new ChatPreviewWidget(data[i]),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/new-chat'),
        tooltip: 'New',
        child: Icon(Icons.add),
      ),
    );
  }
}
