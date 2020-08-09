import 'package:chat_flutter_app/screens/chats/chat_preview.dart';
import 'package:flutter/material.dart';

class Chats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: AppBar(
        title: new Text('Chat App'),
      ),
      body: new Container(
        padding: EdgeInsets.fromLTRB(5, 5, 5, 0),
        child: ListView.builder(
          itemCount: 20,
          itemBuilder: (context, i) => new ChatPreviewWidget(),
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
