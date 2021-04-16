import 'package:share/share.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/models/chat.dart';
import 'package:vartalap/models/user.dart';
import 'package:vartalap/screens/chats/chat_preview.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/user_service.dart';
import 'package:flutter/material.dart';
import 'contact.dart';

class NewChatScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => NewChatState();
}

class NewChatState extends State<NewChatScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<User>> _contacts;
  late Future<List<Chat>> _groups;
  late TabController _tabController;
  bool _openSearch = false;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _contacts = UserService.getUsers();
    _groups = ChatService.getGroups();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
        appBar: this._openSearch ? buildSearchAppBar() : buildAppBar(),
        body: TabBarView(
          controller: _tabController,
          children: [
            contacts(),
            groups(),
          ],
        ));
  }

  Widget contacts() {
    return FutureBuilder<Iterable<User>>(
      future: _contacts,
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
        List<dynamic> data = [];
        data.addAll(snapshot.data!);
        data.add(ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8.0),
            child: Icon(Icons.share),
          ),
          title: Text('Invite friends',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              )),
          onTap: () {
            Share.share(ConfigStore().get('share_message'));
          },
        ));

        return ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, i) {
              if (i > data.length - 2) {
                return data[i];
              }
              return ContactItem(
                  user: data.elementAt(i),
                  onProfileTap: () =>
                      {}, // onTapProfileContactItem( context, snapshot.data.elementAt(i))
                  onTap: (User user) async {
                    Navigator.of(context).pop(user);
                  });
            });
      },
    );
  }

  Widget groups() {
    return FutureBuilder<Iterable<Chat>>(
      future: _groups,
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
        List<dynamic> data = [];
        data.add(ListTile(
          leading: Container(
            decoration: BoxDecoration(
              //color: fabBgColor,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(4.0),
            child: Icon(
              Icons.group,
              size: 32.0,
              color: Colors.grey,
            ),
          ),
          title: Text('New group',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              )),
          onTap: () {
            Navigator.of(context).pushReplacementNamed('/new-group');
          },
        ));

        data.addAll(snapshot.data!);
        return ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, i) {
              if (i < 1) {
                return data[i];
              }
              Chat chat = data.elementAt(i);
              ChatPreview preview =
                  ChatPreview(chat.id, chat.title, chat.pic, '', 0, 0);
              preview.type = chat.type;
              return ChatPreviewWidget(
                preview,
                onGroupTap,
                onGroupTap,
              );
            });
      },
    );
  }

  Future onGroupTap(Chat ch) async {
    if (ch.users.length == 0) {
      var _users = await ChatService.getChatUserByid(ch.id);
      _users.forEach((u) {
        ch.addUser(u);
      });
    }
    Navigator.of(context).pop(ch);
  }

  AppBar buildAppBar() {
    return AppBar(
      title: Text(
        'New Chat',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'Search',
          icon: Icon(Icons.search),
          onPressed: () {
            setState(() {
              this._openSearch = true;
            });
          },
        ),
        PopupMenuButton(itemBuilder: (BuildContext cntx) {
          List<PopupMenuEntry<Object>> entries = [];
          entries.add(PopupMenuItem(
            child: GestureDetector(
              child: Text("Refresh"),
              onTap: () {
                setState(() {
                  _contacts = UserService.getUsers(sync: true);
                  _groups = ChatService.getGroups();
                });
              },
            ),
          ));
          return entries;
        })
      ],
      bottom: TabBar(
        controller: _tabController,
        tabs: [
          Tab(
            child: Icon(Icons.contacts),
          ),
          Tab(
            child: Icon(Icons.group),
          )
        ],
      ),
    );
  }

  AppBar buildSearchAppBar() {
    return AppBar(
      leading: TextButton(
        style: TextButton.styleFrom(
          shape: CircleBorder(),
          padding: const EdgeInsets.only(left: 1.0),
        ),
        onPressed: () {
          setState(() {
            this._openSearch = false;
            this._contacts = UserService.getUsers();
            this._groups = ChatService.getGroups();
          });
        },
        child: Icon(
          Icons.arrow_back,
          size: 24.0,
          color: Colors.white,
        ),
      ),
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      title: TextField(
        style: TextStyle(
          color: Colors.white,
          fontSize: 20.0,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: "Search",
          hintStyle: TextStyle(
            color: Colors.white,
            fontSize: 20.0,
          ),
        ),
        maxLines: 1,
        autofocus: true,
        onChanged: (value) {
          setState(() {
            if (_tabController.index == 0)
              this._contacts = UserService.getUsers(search: value);
            else
              this._groups = ChatService.getGroups(search: value);
          });
        },
      ),
      actions: [],
    );
  }
}
